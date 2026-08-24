using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Web.WebView2.Core;
using Windows.Graphics;
using WinRT.Interop;

namespace DeepSeekHarnessGlass.Windows;

public sealed partial class MainWindow : Window
{
    private readonly HarnessBackend _backend = new();
    private bool _webViewInitialized;
    private bool _syncInFlight;
    private bool _started;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        ConfigureWindow();
        ConfigureBackdrop();

        Closed += (_, _) => _backend.Stop();
    }

    private void ConfigureWindow()
    {
        var windowId = Win32Interop.GetWindowIdFromWindow(WindowNative.GetWindowHandle(this));
        var appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new SizeInt32(1240, 820));
    }

    private void ConfigureBackdrop()
    {
        // Mica is the native Windows 11 glass surface. The XAML status overlay
        // uses AcrylicInAppFillColorDefaultBrush, with a solid system fallback
        // on Windows 10 / Remote Desktop / unsupported hardware.
        if (MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
        }
    }

    private async void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        if (_started) return;
        _started = true;
        await StartBackendAsync();
    }

    private async Task StartBackendAsync()
    {
        ShowStatus(
            title: "Starting DeepSeek Harness…",
            detail: "Launching the official web profile with the bundled runtime.",
            busy: true);
        try
        {
            var url = await _backend.StartAsync();
            await NavigateToHarnessAsync(url);
            HideStatus();
        }
        catch (Exception error)
        {
            ShowStatus(
                title: "DeepSeek Harness could not start",
                detail: $"{error.Message}\n\nLog: {_backend.LogPath}",
                busy: false,
                canRetry: true);
        }
    }

    private async Task NavigateToHarnessAsync(Uri url)
    {
        if (!_webViewInitialized)
        {
            string? webViewVersion;
            try
            {
                webViewVersion = CoreWebView2Environment.GetAvailableBrowserVersionString();
            }
            catch (Exception error)
            {
                throw new InvalidOperationException(
                    "Microsoft Edge WebView2 Runtime is not installed. "
                    + "Install the Evergreen WebView2 Runtime, then launch DeepSeek Harness Glass again.",
                    error);
            }
            if (string.IsNullOrWhiteSpace(webViewVersion))
            {
                throw new InvalidOperationException(
                    "Microsoft Edge WebView2 Runtime is not installed. "
                    + "Install the Evergreen WebView2 Runtime, then launch DeepSeek Harness Glass again.");
            }
            await HarnessWebView.EnsureCoreWebView2Async();
            HarnessWebView.CoreWebView2.NewWindowRequested += OpenExternalWindow;
            HarnessWebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
            HarnessWebView.CoreWebView2.Settings.AreDevToolsEnabled = true;
            await HarnessWebView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                HarnessUiInjection.Script);
            _webViewInitialized = true;
        }
        HarnessWebView.Source = url;
    }

    private static void OpenExternalWindow(
        CoreWebView2 sender,
        CoreWebView2NewWindowRequestedEventArgs args)
    {
        args.Handled = true;
        Process.Start(new ProcessStartInfo(args.Uri) { UseShellExecute = true });
    }

    private void ShowStatus(
        string title,
        string detail,
        bool busy,
        bool canRetry = false,
        double? progress = null)
    {
        StatusOverlay.Visibility = Visibility.Visible;
        StatusTitle.Text = title;
        StatusDetail.Text = detail;
        StatusRing.IsActive = busy && progress is null;
        StatusRing.Visibility = busy && progress is null ? Visibility.Visible : Visibility.Collapsed;
        RetryButton.Visibility = canRetry ? Visibility.Visible : Visibility.Collapsed;
        SyncProgress.Visibility = progress is null ? Visibility.Collapsed : Visibility.Visible;
        if (progress is not null) SyncProgress.Value = Math.Clamp(progress.Value, 0, 1);
    }

    private void HideStatus()
    {
        StatusOverlay.Visibility = Visibility.Collapsed;
    }

    private async void RetryButton_Click(object sender, RoutedEventArgs e)
    {
        await StartBackendAsync();
    }

    private async void RestartBackend_Click(object sender, RoutedEventArgs e)
    {
        await RestartBackendAsync();
    }

    private async Task RestartBackendAsync()
    {
        ShowStatus(
            title: "Restarting DeepSeek Harness…",
            detail: "Preserving the current runtime and plugin configuration.",
            busy: true);
        try
        {
            var url = await _backend.RestartAsync();
            await NavigateToHarnessAsync(url);
            HideStatus();
        }
        catch (Exception error)
        {
            ShowStatus(
                title: "DeepSeek Harness could not restart",
                detail: $"{error.Message}\n\nLog: {_backend.LogPath}",
                busy: false,
                canRetry: true);
        }
    }

    private void OpenInBrowser_Click(object sender, RoutedEventArgs e)
    {
        if (_backend.Url is { } url)
        {
            Process.Start(new ProcessStartInfo(url.ToString()) { UseShellExecute = true });
        }
    }

    private async void InstallPlugin_Click(object sender, RoutedEventArgs e)
    {
        var spec = await PromptForPluginAsync(
            title: "Install Harness plugin",
            description: "Enter an npm package name or version spec. The bundled official pnpm installs it into the Web profile.",
            placeholder: "@scope/dsh-plugin@1.2.3",
            action: "Install");
        if (spec is not null) await RunPluginCommandAsync("add", spec, "Plugin installation");
    }

    private async void RemovePlugin_Click(object sender, RoutedEventArgs e)
    {
        var spec = await PromptForPluginAsync(
            title: "Remove Harness plugin",
            description: "Enter the npm package name to remove from the Web profile.",
            placeholder: "@scope/dsh-plugin",
            action: "Remove");
        if (spec is not null) await RunPluginCommandAsync("remove", spec, "Plugin removal");
    }

    private async Task<string?> PromptForPluginAsync(
        string title,
        string description,
        string placeholder,
        string action)
    {
        var input = new TextBox { PlaceholderText = placeholder, MinWidth = 420 };
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = title,
            Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = description, TextWrapping = TextWrapping.Wrap },
                    input,
                },
            },
            PrimaryButtonText = action,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        var result = await dialog.ShowAsync();
        var value = input.Text.Trim();
        if (result != ContentDialogResult.Primary || string.IsNullOrWhiteSpace(value)) return null;
        if (value.Any(char.IsWhiteSpace))
        {
            await ShowMessageAsync("Invalid plugin package", "Enter a single npm package spec without spaces.");
            return null;
        }
        return value;
    }

    private async Task RunPluginCommandAsync(string command, string spec, string title)
    {
        ShowStatus(
            title: $"{title}…",
            detail: "Calling the official dsh plugin command with bundled Node and pnpm.",
            busy: true);
        var result = await _backend.RunPluginCommandAsync(command, spec);
        HideStatus();
        if (result.Success && _backend.OwnsBackend)
        {
            await RestartBackendAsync();
        }
        var detail = result.Output.Length == 0
            ? "The official dsh plugin command completed."
            : result.Output;
        if (result.Success && _backend.OwnsBackend)
        {
            detail += "\n\nThe bundled backend was restarted so the updated profile can load.";
        }
        await ShowMessageAsync(result.Success ? $"{title} complete" : $"{title} failed", detail);
    }

    private async void SyncOfficialHarness_Click(object sender, RoutedEventArgs e)
    {
        if (_syncInFlight) return;
        _syncInFlight = true;
        SyncOfficialMenuItem.IsEnabled = false;
        _backend.SyncProgress += UpdateSyncProgress;
        ShowStatus(
            title: "Checking official Harness…",
            detail: "Resolving the latest official GitHub commit.",
            busy: true,
            progress: 0);

        try
        {
            var result = await _backend.SyncOfficialRuntimeAsync();
            if (result.Success && _backend.OwnsBackend)
            {
                ShowStatus(
                    title: "Restarting with the updated runtime…",
                    detail: result.Detail,
                    busy: true,
                    progress: 1);
                var url = await _backend.RestartAsync();
                await NavigateToHarnessAsync(url);
            }
            HideStatus();
            var suffix = result.Success && _backend.OwnsBackend
                ? "\n\nThe embedded Harness was restarted and now uses the new official runtime."
                : result.Success
                    ? "\n\nAn external dsh instance is attached. Restart that instance to use its updated profile."
                    : "\n\nThe current working runtime has been left unchanged.";
            await ShowMessageAsync(
                result.Success ? "Official Harness sync complete" : "Official Harness sync failed",
                result.Detail + suffix);
        }
        catch (Exception error)
        {
            ShowStatus(
                title: "Official Harness sync failed",
                detail: $"{error.Message}\n\nDiagnostic log: {_backend.SyncLogPath}",
                busy: false,
                canRetry: true);
        }
        finally
        {
            _backend.SyncProgress -= UpdateSyncProgress;
            _syncInFlight = false;
            SyncOfficialMenuItem.IsEnabled = true;
        }
    }

    private void UpdateSyncProgress(object? sender, SyncProgress progress)
    {
        DispatcherQueue.TryEnqueue(() => ShowStatus(
            title: $"{progress.Title}  {Math.Round(progress.Fraction * 100)}%",
            detail: progress.Detail,
            busy: true,
            progress: progress.Fraction));
    }

    private void OpenDshHome_Click(object sender, RoutedEventArgs e)
    {
        OpenFolder(_backend.DshHome);
    }

    private void OpenWebProfile_Click(object sender, RoutedEventArgs e)
    {
        OpenFolder(Path.Combine(_backend.DshHome, "profiles", "web"));
    }

    private void OpenBackendLog_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_backend.LogPath)!);
        if (!File.Exists(_backend.LogPath)) File.WriteAllText(_backend.LogPath, "");
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{_backend.LogPath}\"")
        {
            UseShellExecute = true,
        });
    }

    private void About_Click(object sender, RoutedEventArgs e)
    {
        _ = ShowMessageAsync(
            "DeepSeek Harness Glass Sync",
            "Windows native host: WinUI 3 + WebView2 with Mica and Acrylic.\n\n"
            + "It launches the unmodified official DeepSeek Harness web profile and preserves its plugin system.");
    }

    private static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    private async Task ShowMessageAsync(string title, string text)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = title,
            Content = new ScrollViewer
            {
                MaxHeight = 380,
                Content = new TextBlock
                {
                    Text = text,
                    TextWrapping = TextWrapping.Wrap,
                    IsTextSelectionEnabled = true,
                },
            },
            CloseButtonText = "OK",
        };
        await dialog.ShowAsync();
    }
}
