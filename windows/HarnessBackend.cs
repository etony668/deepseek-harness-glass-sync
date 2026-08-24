using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DeepSeekHarnessGlass.Windows;

public sealed record PluginCommandResult(bool Success, string Output);
public sealed record SyncResult(bool Success, string Detail, string? Commit);
public sealed record SyncProgress(string Phase, double Fraction, string Title, string Detail);

/// <summary>
/// Owns the Windows host's connection to the official dsh web profile.
/// This class never implements a substitute plugin runtime: it invokes the
/// deployed official <c>dsh</c> command and leaves profile/package resolution to
/// the upstream Harness runtime.
/// </summary>
public sealed class HarnessBackend
{
    private const string OfficialCommitApi =
        "https://api.github.com/repos/deepseek-ai/deepseek-harness/commits/master";
    private static readonly Regex BackendUrlPattern = new(
        @"dsh web:\s*(http://127\.0\.0\.1:\d+)",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex CommitPattern = new(
        "^[0-9a-f]{40}$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly object _processGate = new();
    private readonly HttpClient _http = new();
    private Process? _process;
    private TaskCompletionSource<Uri>? _ready;
    private bool _stopping;

    public HarnessBackend()
    {
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("DeepSeek-Harness-Glass-Sync-Windows");
        _http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    public event EventHandler<SyncProgress>? SyncProgress;

    public Uri? Url { get; private set; }
    public bool OwnsBackend { get; private set; } = true;

    public string ResourceRoot => Path.Combine(AppContext.BaseDirectory, "Resources");
    public string DshHome => Environment.GetEnvironmentVariable("DSH_HOME") is { Length: > 0 } configured
        ? configured
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dsh");
    public string RuntimeRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DeepSeek Harness Glass",
        "runtime");
    public string LogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DeepSeek Harness Glass",
        "backend.log");
    public string SyncLogPath => Path.Combine(RuntimeRoot, "latest-sync.log");

    private string NodePath => Path.Combine(ResourceRoot, "node", "node.exe");
    private string BundledBackendPath => Path.Combine(ResourceRoot, "backend", "lib", "bin.js");
    private string SyncScriptPath => Path.Combine(ResourceRoot, "bin", "sync-official-runtime.ps1");
    private string BundledBinPath => Path.Combine(ResourceRoot, "bin");
    private string PluginRuntimeRoot => Path.Combine(RuntimeRoot, "plugin-runtime");
    private static readonly string[] RequiredRuntimeFiles =
    [
        Path.Combine("lib", "bin.js"),
        "package.json",
        Path.Combine("node_modules", "@deepseek-ai", "dsh-app-boot", "package.json"),
        Path.Combine("node_modules", "@deepseek-ai", "dsh-base", "package.json"),
        Path.Combine("node_modules", "@deepseek-ai", "dsh-web-app", "package.json"),
    ];

    public async Task<Uri> StartAsync(CancellationToken cancellationToken = default)
    {
        lock (_processGate)
        {
            if (Url is not null) return Url;
        }

        if (await IsExternalBackendReadyAsync(cancellationToken))
        {
            OwnsBackend = false;
            Url = new Uri("http://127.0.0.1:3080/");
            AppendLog("[backend] attached to an existing dsh process on port 3080");
            return Url;
        }

        OwnsBackend = true;
        var node = NodePath;
        _ = EnsureActiveRuntimeDirectory();
        var backend = ActiveBackendPath();
        if (!File.Exists(node))
        {
            throw new InvalidOperationException(
                $"Bundled Node.js is missing: {node}. Rebuild the Windows app with windows/package.ps1.");
        }
        if (!File.Exists(backend))
        {
            throw new InvalidOperationException(
                $"Official Harness runtime is missing: {backend}. Run windows/package.ps1 again.");
        }

        Directory.CreateDirectory(DshHome);
        RepairUserPluginFallbacks();
        Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);

        var ready = new TaskCompletionSource<Uri>(TaskCreationOptions.RunContinuationsAsynchronously);
        var process = new Process
        {
            StartInfo = CreateNodeStartInfo(
                backend,
                ["web", "--no-open", "--port", "0"],
                redirectOutput: true),
            EnableRaisingEvents = true,
        };
        process.OutputDataReceived += (_, args) => HandleBackendLine(args.Data, ready);
        process.ErrorDataReceived += (_, args) => HandleBackendLine(args.Data, ready);
        process.Exited += (_, _) => HandleBackendExit(process, ready);

        lock (_processGate)
        {
            _stopping = false;
            _ready = ready;
            _process = process;
        }

        try
        {
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
        }
        catch
        {
            lock (_processGate)
            {
                if (ReferenceEquals(_process, process)) _process = null;
            }
            process.Dispose();
            throw;
        }

        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var timeout = Task.Delay(TimeSpan.FromSeconds(45), cancellation.Token);
        var completed = await Task.WhenAny(ready.Task, timeout);
        if (completed != ready.Task)
        {
            Stop();
            throw new TimeoutException(
                "Timed out while waiting for the official dsh web profile to start. See the backend log.");
        }

        cancellation.Cancel();
        return await ready.Task;
    }

    public async Task<Uri> RestartAsync(CancellationToken cancellationToken = default)
    {
        if (!OwnsBackend && Url is not null)
        {
            return Url;
        }
        Stop();
        return await StartAsync(cancellationToken);
    }

    public void Stop()
    {
        Process? process;
        lock (_processGate)
        {
            _stopping = true;
            process = _process;
            _process = null;
            _ready = null;
            Url = null;
        }

        if (process is null) return;
        try
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
            // The backend exited between the HasExited check and Kill.
        }
    }

    public async Task<PluginCommandResult> RunPluginCommandAsync(
        string command,
        string packageSpec,
        CancellationToken cancellationToken = default)
    {
        if (command is not ("add" or "remove"))
            throw new ArgumentOutOfRangeException(nameof(command));
        if (string.IsNullOrWhiteSpace(packageSpec) || packageSpec.Any(char.IsWhiteSpace))
            throw new ArgumentException("A plugin package spec must be a single non-empty value.", nameof(packageSpec));

        RepairUserPluginFallbacks();
        var backend = PluginBackendPath();
        if (!File.Exists(NodePath) || !File.Exists(backend))
            throw new InvalidOperationException(
                "The isolated plugin runtime is incomplete and could not be rebuilt from a healthy official runtime.");

        var result = await RunProcessAsync(
            CreateNodeStartInfo(
                backend,
                ["plugin", "--profile", "web", command, packageSpec],
                redirectOutput: true),
            cancellationToken);
        var healthy = EnsureActiveRuntimeDirectory() is not null;
        return new PluginCommandResult(
            result.ExitCode == 0 && healthy,
            result.ExitCode == 0 && healthy
                ? result.Output
                : result.ExitCode == 0
                    ? "Plugin operation completed, but the active official runtime failed integrity checks and was rolled back."
                    : result.Output);
    }

    public async Task<SyncResult> SyncOfficialRuntimeAsync(CancellationToken cancellationToken = default)
    {
        EmitProgress(new SyncProgress("check", 0, "Checking official Harness", "Resolving the latest official GitHub commit."));
        var commit = await FetchLatestOfficialCommitAsync(cancellationToken);
        if (string.Equals(commit, CurrentRuntimeCommit(), StringComparison.Ordinal))
        {
            var detail = $"The active official runtime already uses {commit}.";
            EmitProgress(new SyncProgress("complete", 1, "Official Harness is current", detail));
            return new SyncResult(true, detail, commit);
        }

        if (!File.Exists(SyncScriptPath))
            throw new InvalidOperationException(
                $"The bundled Windows sync script is missing: {SyncScriptPath}. Rebuild the app.");

        Directory.CreateDirectory(RuntimeRoot);
        var powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) powershell = "powershell.exe";

        var startInfo = new ProcessStartInfo
        {
            FileName = powershell,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = ResourceRoot,
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(SyncScriptPath);
        startInfo.ArgumentList.Add("-RuntimeRoot");
        startInfo.ArgumentList.Add(RuntimeRoot);
        startInfo.ArgumentList.Add("-Commit");
        startInfo.ArgumentList.Add(commit);
        ApplyRuntimeEnvironment(startInfo);

        var result = await RunProcessAsync(
            startInfo,
            cancellationToken,
            line =>
            {
                if (TryParseSyncProgress(line, out var progress))
                {
                    EmitProgress(progress);
                }
                else if (!string.IsNullOrWhiteSpace(line))
                {
                    AppendLog($"[sync] {line}");
                }
            });

        if (result.ExitCode == 0)
        {
            var detail = $"Official Harness runtime {commit} is ready.";
            EmitProgress(new SyncProgress("complete", 1, "Official Harness updated", detail));
            return new SyncResult(true, detail, commit);
        }

        var failure = result.Output.Length == 0
            ? $"The official sync process exited with code {result.ExitCode}. Diagnostic log: {SyncLogPath}"
            : $"{result.Output}\n\nDiagnostic log: {SyncLogPath}";
        return new SyncResult(false, failure, commit);
    }

    private async Task<string> FetchLatestOfficialCommitAsync(CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(OfficialCommitApi, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Official GitHub returned HTTP {(int)response.StatusCode} while checking Harness updates.");
        }
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var commit = document.RootElement.GetProperty("sha").GetString();
        if (commit is null || !CommitPattern.IsMatch(commit))
            throw new InvalidDataException("Official GitHub did not return a valid Harness commit.");
        return commit;
    }

    private string ActiveBackendPath()
    {
        var active = EnsureActiveRuntimeDirectory();
        if (active is not null) return Path.Combine(active, "lib", "bin.js");
        return BundledBackendPath;
    }

    private string? PluginBackendPath()
    {
        var source = EnsureActiveRuntimeDirectory();
        if (source is null) return null;
        var commit = CurrentRuntimeCommit() ?? BundledRuntimeCommit();
        var target = Path.Combine(PluginRuntimeRoot, commit);
        if (!RuntimeIsComplete(target))
        {
            Directory.CreateDirectory(PluginRuntimeRoot);
            if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
            CopyDirectory(source, target);
        }
        return RuntimeIsComplete(target)
            ? Path.Combine(target, "lib", "bin.js")
            : null;
    }

    /// <summary>
    /// Keep user-installed plugin packages resolvable from the web profile
    /// after the immutable official runtime changes. The plugin source remains
    /// under DSH_HOME; only a profile fallback junction is repaired. This
    /// mirrors the macOS shell behavior without copying plugin source into the
    /// repository or mutating the official runtime.
    /// </summary>
    private void RepairUserPluginFallbacks()
    {
        var pluginsRoot = Path.Combine(DshHome, "plugins");
        if (!Directory.Exists(pluginsRoot)) return;

        var profileModules = Path.Combine(DshHome, "profiles", "node_modules");
        foreach (var pluginDirectory in Directory.EnumerateDirectories(pluginsRoot))
        {
            var manifestPath = Path.Combine(pluginDirectory, "package.json");
            if (!File.Exists(manifestPath)) continue;

            string? packageName;
            try
            {
                using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
                packageName = document.RootElement.TryGetProperty("name", out var name)
                    ? name.GetString()
                    : null;
            }
            catch (Exception error)
            {
                AppendLog($"[plugin] could not read {manifestPath}: {error.Message}");
                continue;
            }

            if (!TryGetPackagePath(profileModules, packageName, out var fallback))
                continue;

            if (File.Exists(Path.Combine(fallback, "package.json"))) continue;

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(fallback)!);
                RemovePluginFallback(fallback);
                if (TryCreateDirectoryJunction(fallback, pluginDirectory))
                {
                    AppendLog($"[plugin] repaired profile fallback {packageName}");
                }
                else
                {
                    AppendLog($"[plugin] could not repair profile fallback {packageName}");
                }
            }
            catch (Exception error)
            {
                AppendLog($"[plugin] could not repair {packageName}: {error.Message}");
            }
        }
    }

    private static bool TryGetPackagePath(
        string profileModules,
        string? packageName,
        out string fallback)
    {
        fallback = string.Empty;
        if (string.IsNullOrWhiteSpace(packageName)) return false;

        var components = packageName.Split('/');
        if (components.Length == 0
            || components.Any(component =>
                string.IsNullOrWhiteSpace(component)
                || component is "." or ".."
                || component.Contains('\\')))
        {
            return false;
        }

        fallback = components.Aggregate(
            profileModules,
            (current, component) => Path.Combine(current, component));
        var root = Path.GetFullPath(profileModules)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        return Path.GetFullPath(fallback).StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }

    private static void RemovePluginFallback(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            try
            {
                var attributes = File.GetAttributes(path);
                if (!attributes.HasFlag(FileAttributes.ReparsePoint)) return;
            }
            catch
            {
                return;
            }
        }

        var currentAttributes = File.GetAttributes(path);
        if (currentAttributes.HasFlag(FileAttributes.ReparsePoint))
        {
            Directory.Delete(path);
        }
        else if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
        else if (File.Exists(path))
        {
            File.Delete(path);
        }
    }

    private static bool TryCreateDirectoryJunction(string link, string target)
    {
        var cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = cmd,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("/d");
        startInfo.ArgumentList.Add("/c");
        startInfo.ArgumentList.Add("mklink");
        startInfo.ArgumentList.Add("/J");
        startInfo.ArgumentList.Add(link);
        startInfo.ArgumentList.Add(target);

        using var process = Process.Start(startInfo);
        if (process is null) return false;
        process.WaitForExit(5000);
        return process.ExitCode == 0
            && File.Exists(Path.Combine(link, "package.json"));
    }

    private bool RuntimeIsComplete(string root)
    {
        return RequiredRuntimeFiles.All(relative =>
            File.Exists(Path.Combine(root, relative)));
    }

    /// <summary>
    /// Treat versioned runtimes as immutable. A damaged current pointer is
    /// preserved, then the newest complete version is activated automatically.
    /// </summary>
    private string? EnsureActiveRuntimeDirectory()
    {
        Directory.CreateDirectory(RuntimeRoot);
        var currentPointer = Path.Combine(RuntimeRoot, "current.txt");
        var currentCommit = File.Exists(currentPointer)
            ? File.ReadAllText(currentPointer).Trim().ToLowerInvariant()
            : null;
        var current = currentCommit is not null && CommitPattern.IsMatch(currentCommit)
            ? Path.Combine(RuntimeRoot, "versions", currentCommit)
            : null;
        if (current is not null && RuntimeIsComplete(current)) return current;

        if (File.Exists(currentPointer))
        {
            var broken = Path.Combine(
                RuntimeRoot,
                $"current.broken-{DateTimeOffset.Now:yyyyMMdd-HHmmssfff}");
            try
            {
                File.Move(currentPointer, broken, overwrite: true);
                AppendLog($"[runtime] current runtime failed integrity check; preserved at {broken}");
            }
            catch (Exception error)
            {
                AppendLog($"[runtime] could not preserve broken current pointer: {error.Message}");
            }
        }

        var versions = Path.Combine(RuntimeRoot, "versions");
        var candidate = Directory.Exists(versions)
            ? Directory.EnumerateDirectories(versions)
                .Where(RuntimeIsComplete)
                .OrderByDescending(Directory.GetLastWriteTimeUtc)
                .FirstOrDefault()
            : null;
        if (candidate is not null)
        {
            WriteCurrentPointer(Path.GetFileName(candidate));
            AppendLog($"[runtime] automatically rolled back to {Path.GetFileName(candidate)}");
            return candidate;
        }

        var bundled = Path.Combine(ResourceRoot, "backend");
        if (RuntimeIsComplete(bundled))
        {
            AppendLog("[runtime] using bundled runtime fallback");
            return bundled;
        }
        return null;
    }

    private string? CurrentRuntimeCommit()
    {
        var pointer = Path.Combine(RuntimeRoot, "current.txt");
        if (!File.Exists(pointer)) return null;
        var commit = File.ReadAllText(pointer).Trim().ToLowerInvariant();
        return CommitPattern.IsMatch(commit)
            && Directory.Exists(Path.Combine(RuntimeRoot, "versions", commit))
            ? commit
            : null;
    }

    private string BundledRuntimeCommit()
    {
        var path = Path.Combine(ResourceRoot, "bundled-runtime-commit");
        return File.Exists(path) ? File.ReadAllText(path).Trim() : "bundled";
    }

    private void WriteCurrentPointer(string value)
    {
        var pointer = Path.Combine(RuntimeRoot, "current.txt");
        var temporary = Path.Combine(RuntimeRoot, $".current-{Guid.NewGuid():N}.tmp");
        File.WriteAllText(temporary, value, Encoding.ASCII);
        File.Move(temporary, pointer, overwrite: true);
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.EnumerateDirectories(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, directory);
            Directory.CreateDirectory(Path.Combine(destination, relative));
        }
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, file);
            var target = Path.Combine(destination, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    private ProcessStartInfo CreateNodeStartInfo(
        string entryPoint,
        IEnumerable<string> arguments,
        bool redirectOutput)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = NodePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(entryPoint)!,
            RedirectStandardOutput = redirectOutput,
            RedirectStandardError = redirectOutput,
        };
        startInfo.ArgumentList.Add("--expose-internals");
        startInfo.ArgumentList.Add(entryPoint);
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        ApplyRuntimeEnvironment(startInfo);
        return startInfo;
    }

    private void ApplyRuntimeEnvironment(ProcessStartInfo startInfo)
    {
        startInfo.Environment["DSH_HOME"] = DshHome;
        var existingPath = startInfo.Environment.TryGetValue("PATH", out var path)
            ? path
            : Environment.GetEnvironmentVariable("PATH") ?? "";
        startInfo.Environment["PATH"] = $"{BundledBinPath};{existingPath}";
    }

    private void HandleBackendLine(string? line, TaskCompletionSource<Uri> ready)
    {
        if (string.IsNullOrWhiteSpace(line)) return;
        AppendLog($"[backend] {line}");
        var match = BackendUrlPattern.Match(line);
        if (!match.Success || !Uri.TryCreate(match.Groups[1].Value, UriKind.Absolute, out var url)) return;
        Url = url;
        ready.TrySetResult(url);
    }

    private void HandleBackendExit(Process process, TaskCompletionSource<Uri> ready)
    {
        var exitCode = 0;
        try { exitCode = process.ExitCode; } catch (InvalidOperationException) { }
        AppendLog($"[backend] exited with code {exitCode}");
        var stopping = false;
        lock (_processGate)
        {
            stopping = _stopping;
            if (ReferenceEquals(_process, process)) _process = null;
            if (!stopping) Url = null;
        }
        if (!stopping)
        {
            ready.TrySetException(new InvalidOperationException(
                $"The official dsh backend exited before becoming ready (code {exitCode})."));
        }
        process.Dispose();
    }

    private async Task<bool> IsExternalBackendReadyAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(2));
            using var response = await _http.GetAsync("http://127.0.0.1:3080/", timeout.Token);
            var text = await response.Content.ReadAsStringAsync(timeout.Token);
            return response.IsSuccessStatusCode && text.Contains("__DSH_BOOT__", StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private async Task<ProcessResult> RunProcessAsync(
        ProcessStartInfo startInfo,
        CancellationToken cancellationToken,
        Action<string>? lineReceived = null)
    {
        var output = new StringBuilder();
        using var process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, args) => CaptureProcessLine(args.Data, output, lineReceived);
        process.ErrorDataReceived += (_, args) => CaptureProcessLine(args.Data, output, lineReceived);
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync(cancellationToken);
        return new ProcessResult(process.ExitCode, output.ToString().Trim());
    }

    private static void CaptureProcessLine(string? line, StringBuilder output, Action<string>? lineReceived)
    {
        if (line is null) return;
        lineReceived?.Invoke(line);
        const int maximumOutputLength = 16_000;
        if (output.Length >= maximumOutputLength) return;
        var remaining = maximumOutputLength - output.Length;
        output.Append(line.AsSpan(0, Math.Min(line.Length, remaining)));
        output.AppendLine();
    }

    private static bool TryParseSyncProgress(string line, out SyncProgress progress)
    {
        const string prefix = "@@DSH_SYNC@@";
        progress = default!;
        if (!line.StartsWith(prefix, StringComparison.Ordinal)) return false;
        try
        {
            var parsed = JsonSerializer.Deserialize<SyncProgress>(
                line[prefix.Length..],
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (parsed is null) return false;
            progress = parsed with { Fraction = Math.Clamp(parsed.Fraction, 0, 1) };
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private void EmitProgress(SyncProgress progress) => SyncProgress?.Invoke(this, progress);

    private void AppendLog(string text)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {text}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never make the official runtime unavailable.
        }
    }

    private sealed record ProcessResult(int ExitCode, string Output);
}
