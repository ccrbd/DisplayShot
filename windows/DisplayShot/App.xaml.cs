using System.Windows;
using DisplayShot.Capture;
using DisplayShot.Configuration;
using DisplayShot.Hotkeys;
using DisplayShot.Overlay;
using DisplayShot.Tray;

namespace DisplayShot;

/// <summary>Tray-only application: no main window, a global hotkey opens the overlay.</summary>
public partial class App : Application
{
    private Mutex? _mutex;
    private bool _ownsMutex;
    private TrayIcon? _tray;
    private GlobalHotkey? _hotkey;
    private OverlaySession? _session;
    private SettingsWindow? _settingsWindow;
    private Settings _settings = new();

    public Settings Settings => _settings;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _mutex = new Mutex(true, @"Local\DisplayShot.SingleInstance", out _ownsMutex);
        if (!_ownsMutex)
        {
            Shutdown();
            return;
        }

        _settings = Settings.Load();

        _tray = new TrayIcon();
        _tray.CaptureRequested += (_, _) => BeginCapture();
        _tray.SettingsRequested += (_, _) => ShowSettings();
        _tray.QuitRequested += (_, _) => Shutdown();

        _hotkey = new GlobalHotkey();
        _hotkey.Pressed += (_, _) => BeginCapture();
        RegisterHotkey(showFallbackNotice: true);
    }

    private void RegisterHotkey(bool showFallbackNotice)
    {
        if (_hotkey is null || _tray is null) return;

        if (_hotkey.Register(_settings.Hotkey))
        {
            _tray.SetHotkeyText(_settings.Hotkey.ToString());
            return;
        }

        var fallback = Hotkey.Fallback;
        if (_settings.Hotkey != fallback && _hotkey.Register(fallback))
        {
            if (showFallbackNotice)
            {
                _tray.ShowBalloon($"Shortcut changed to {fallback}",
                    $"{_settings.Hotkey} is already in use. On Windows 11 the Snipping Tool owns Print Screen while " +
                    "\"Use the Print screen key to open screen capture\" is on (Settings → Accessibility → Keyboard). " +
                    "You can pick any shortcut in DisplayShot Settings.");
            }
            _settings.Hotkey = fallback;
            _settings.Save();
            _tray.SetHotkeyText(fallback.ToString());
        }
        else
        {
            _tray.ShowBalloon("Shortcut unavailable",
                $"Couldn't register {_settings.Hotkey}. Choose another shortcut in Settings.");
        }
    }

    /// <summary>Called by the settings window after the user records a new shortcut.</summary>
    public void ApplyHotkey(Hotkey hotkey)
    {
        _settings.Hotkey = hotkey;
        _settings.Save();
        RegisterHotkey(showFallbackNotice: true);
    }

    private void BeginCapture()
    {
        if (_session is not null) return;
        try
        {
            var capture = ScreenCapturer.CaptureVirtualScreen();
            var session = new OverlaySession(capture, _settings);
            session.Finished += (_, _) => _session = null;
            _session = session;
            session.Start();
        }
        catch (Exception ex)
        {
            _session = null;
            _tray?.ShowBalloon("Capture failed", ex.Message);
        }
    }

    private void ShowSettings()
    {
        if (_settingsWindow is null || !_settingsWindow.IsLoaded)
        {
            _settingsWindow = new SettingsWindow(_settings, this);
        }
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkey?.Dispose();
        _tray?.Dispose();
        if (_ownsMutex) _mutex?.ReleaseMutex();
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
