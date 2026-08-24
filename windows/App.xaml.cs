using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;

namespace DeepSeekHarnessGlass.Windows;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        try
        {
            InitializeComponent();
        }
        catch (Exception error)
        {
            StartupDiagnostics.Write(error);
            throw;
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception error)
        {
            StartupDiagnostics.Write(error);
            StartupDiagnostics.ShowMessage(
                "DeepSeek Harness Glass could not start.",
                $"{error.Message}\n\nA diagnostic log was written to:\n{StartupDiagnostics.LogPath}");
            throw;
        }
    }
}

internal static class StartupDiagnostics
{
    public static string LogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DeepSeek Harness Glass",
        "startup.log");

    public static void Write(Exception error)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(
                LogPath,
                $"{DateTimeOffset.Now:O}\n{error}\n\n");
        }
        catch
        {
            // Diagnostics must never be allowed to mask the original failure.
        }
    }

    public static void ShowMessage(string title, string text)
    {
        try
        {
            MessageBoxW(IntPtr.Zero, text, title, 0x00000010);
        }
        catch
        {
            // The process is already on a failure path; logging is sufficient.
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(
        IntPtr hWnd,
        string text,
        string caption,
        uint type);
}
