using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using DisplayShot.Configuration;
using DisplayShot.Export;
using DisplayShot.Hotkeys;

namespace DisplayShot;

public partial class SettingsWindow : Window
{
    private readonly Settings _settings;
    private readonly App _app;

    public SettingsWindow(Settings settings, App app)
    {
        _settings = settings;
        _app = app;
        InitializeComponent();
        HotkeyBox.Text = _settings.Hotkey.ToString();
        PathText.Text = _settings.SaveDirectory;
        SilentCheck.IsChecked = _settings.SaveWithoutAsking;
        SoundCheck.IsChecked = _settings.PlaySound;
        StartupCheck.IsChecked = StartupRegistrar.IsEnabled;
        foreach (var f in ImageFormatExtensions.All) FormatBox.Items.Add(f.Title());
        FormatBox.SelectedIndex = ImageFormatExtensions.All.ToList().IndexOf(_settings.SaveFormat);
    }

    private void Format_Changed(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (FormatBox.SelectedIndex < 0) return;
        _settings.SaveFormat = ImageFormatExtensions.All[FormatBox.SelectedIndex];
        _settings.Save();
    }

    private void HotkeyBox_GotFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        HotkeyBox.Text = "Press the new shortcut… (Esc to cancel)";
        HotkeyBox.Background = new SolidColorBrush(Color.FromArgb(0x22, 0x00, 0x78, 0xD4));
    }

    private void HotkeyBox_LostFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        HotkeyBox.Text = _settings.Hotkey.ToString();
        HotkeyBox.ClearValue(BackgroundProperty);
    }

    private void HotkeyBox_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape)
        {
            Keyboard.ClearFocus();
            ChooseButton.Focus();
            return;
        }
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return; // wait for the actual key

        var hotkey = new Hotkey(key, Keyboard.Modifiers);
        if (!hotkey.IsValid)
        {
            System.Media.SystemSounds.Beep.Play();
            return;
        }
        _app.ApplyHotkey(hotkey);
        Keyboard.ClearFocus();
        ChooseButton.Focus();
        HotkeyBox.Text = _settings.Hotkey.ToString();
    }

    private void Choose_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Choose where screenshots are saved",
            InitialDirectory = _settings.SaveDirectory,
        };
        if (dialog.ShowDialog(this) == true)
        {
            _settings.SaveDirectory = dialog.FolderName;
            _settings.Save();
            PathText.Text = dialog.FolderName;
        }
    }

    private void Silent_Click(object sender, RoutedEventArgs e)
    {
        _settings.SaveWithoutAsking = SilentCheck.IsChecked == true;
        _settings.Save();
    }

    private void Sound_Click(object sender, RoutedEventArgs e)
    {
        _settings.PlaySound = SoundCheck.IsChecked == true;
        _settings.Save();
    }

    private void Startup_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            StartupRegistrar.SetEnabled(StartupCheck.IsChecked == true);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "DisplayShot", MessageBoxButton.OK, MessageBoxImage.Warning);
            StartupCheck.IsChecked = StartupRegistrar.IsEnabled;
        }
    }
}
