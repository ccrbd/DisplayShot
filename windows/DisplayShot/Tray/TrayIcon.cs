using System.Drawing;
using System.Windows.Forms;
using DisplayShot.Configuration;

namespace DisplayShot.Tray;

/// <summary>Notification-area icon with the app menu. WinForms is used only for this.</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _captureItem;

    public event EventHandler? CaptureRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? QuitRequested;

    public TrayIcon()
    {
        var menu = new ContextMenuStrip();
        _captureItem = new ToolStripMenuItem("Capture area", null, (_, _) => CaptureRequested?.Invoke(this, EventArgs.Empty));
        menu.Items.Add(_captureItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Settings…", null, (_, _) => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        var startup = new ToolStripMenuItem("Start with Windows") { CheckOnClick = true, Checked = StartupRegistrar.IsEnabled };
        startup.Click += (_, _) =>
        {
            try { StartupRegistrar.SetEnabled(startup.Checked); }
            catch (Exception ex) { ShowBalloon("Couldn't change startup setting", ex.Message); startup.Checked = StartupRegistrar.IsEnabled; }
        };
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit DisplayShot", null, (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty)));

        _icon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "DisplayShot",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _icon.DoubleClick += (_, _) => CaptureRequested?.Invoke(this, EventArgs.Empty);
    }

    private static Icon LoadIcon()
    {
        var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/DisplayShot.ico"));
        return resource is null ? SystemIcons.Application : new Icon(resource.Stream);
    }

    public void SetHotkeyText(string hotkey)
    {
        _captureItem.ShortcutKeyDisplayString = hotkey;
        var text = $"DisplayShot — {hotkey}";
        _icon.Text = text.Length > 63 ? text[..63] : text;
    }

    public void ShowBalloon(string title, string text) => _icon.ShowBalloonTip(6000, title, text, ToolTipIcon.Info);

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
