using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using DisplayShot.Capture;

namespace DisplayShot.Overlay;

/// <summary>A brief "Copied"/"Saved" HUD near the bottom of the monitor the shot came from.</summary>
public sealed class Toast
{
    private readonly string _text;
    private readonly VirtualScreenCapture _capture;
    private readonly MonitorInfo _monitor;

    public Toast(string text, VirtualScreenCapture capture, MonitorInfo monitor)
    {
        _text = text;
        _capture = capture;
        _monitor = monitor;
    }

    public void ShowNear()
    {
        var window = new Window
        {
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            Topmost = true,
            ShowActivated = false,
            SizeToContent = SizeToContent.WidthAndHeight,
        };
        window.Content = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(240, 26, 26, 26)),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16, 9, 16, 9),
            Child = new TextBlock { Text = _text, Foreground = Brushes.White, FontSize = 13, FontWeight = FontWeights.Medium },
        };
        window.Loaded += (_, _) =>
        {
            var scale = _monitor.DpiScale;
            var w = window.ActualWidth * scale;
            window.Left = (_monitor.Bounds.X + (_monitor.Bounds.Width - w) / 2) / scale;
            window.Top = (_monitor.Bounds.Y + _monitor.Bounds.Height - 110 * scale) / scale;
            var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150));
            window.BeginAnimation(UIElement.OpacityProperty, fade);
        };
        window.Show();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.4) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(300));
            fade.Completed += (_, _) => window.Close();
            window.BeginAnimation(UIElement.OpacityProperty, fade);
        };
        timer.Start();
    }
}
