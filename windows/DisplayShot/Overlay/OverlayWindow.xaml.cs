using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace DisplayShot.Overlay;

/// <summary>One borderless window spanning the whole virtual screen. Its content is scaled so
/// child coordinates are physical pixels regardless of per-monitor DPI.</summary>
public partial class OverlayWindow : Window
{
    public Canvas Host => HostCanvas;

    public OverlayWindow()
    {
        InitializeComponent();
    }

    /// <summary>Places the window over the virtual screen (physical pixels) and neutralises WPF DPI scaling.</summary>
    public void PositionOverVirtualScreen(int x, int y, int width, int height)
    {
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var source = (HwndSource)PresentationSource.FromVisual(this)!;
            var m = source.CompositionTarget!.TransformToDevice;
            var dpiX = m.M11;
            var dpiY = m.M22;
            // Cancel WPF's device transform so 1 child unit == 1 physical pixel.
            Root.LayoutTransform = new ScaleTransform(1 / dpiX, 1 / dpiY);
            SetWindowPos(handle, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        // Keep native focus so key events arrive even though ShowActivated stays default.
        Activate();
    }

    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_SHOWWINDOW = 0x0040;
    private static readonly IntPtr HWND_TOPMOST = new(-1);

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);
}
