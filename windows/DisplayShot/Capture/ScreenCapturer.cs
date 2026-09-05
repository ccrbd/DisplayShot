using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace DisplayShot.Capture;

/// <summary>One monitor: physical-pixel bounds in virtual-screen coordinates plus its DPI scale.</summary>
public sealed record MonitorInfo(Int32Rect Bounds, double DpiScale, bool IsPrimary)
{
    public bool Contains(int x, int y) =>
        x >= Bounds.X && x < Bounds.X + Bounds.Width && y >= Bounds.Y && y < Bounds.Y + Bounds.Height;
}

/// <summary>The whole virtual screen frozen into one bitmap, in physical pixels.</summary>
public sealed class VirtualScreenCapture
{
    public required BitmapSource Image { get; init; }
    /// <summary>Virtual-screen bounds in physical pixels (origin may be negative).</summary>
    public required Int32Rect Bounds { get; init; }
    public required IReadOnlyList<MonitorInfo> Monitors { get; init; }

    /// <summary>Monitor under a canvas point (canvas origin = virtual-screen origin).</summary>
    public MonitorInfo MonitorAt(System.Windows.Point canvasPoint)
    {
        var x = (int)Math.Floor(canvasPoint.X) + Bounds.X;
        var y = (int)Math.Floor(canvasPoint.Y) + Bounds.Y;
        return Monitors.FirstOrDefault(m => m.Contains(x, y))
               ?? Monitors.FirstOrDefault(m => m.IsPrimary)
               ?? Monitors[0];
    }

    /// <summary>Monitor rect in canvas coordinates.</summary>
    public Rect CanvasRect(MonitorInfo m) =>
        new(m.Bounds.X - Bounds.X, m.Bounds.Y - Bounds.Y, m.Bounds.Width, m.Bounds.Height);
}

public static class ScreenCapturer
{
    /// <summary>Copies every monitor into one BGR bitmap via GDI (fast, no cursor).</summary>
    public static VirtualScreenCapture CaptureVirtualScreen()
    {
        var monitors = MonitorEnumerator.Enumerate();
        var minX = monitors.Min(m => m.Bounds.X);
        var minY = monitors.Min(m => m.Bounds.Y);
        var maxX = monitors.Max(m => m.Bounds.X + m.Bounds.Width);
        var maxY = monitors.Max(m => m.Bounds.Y + m.Bounds.Height);
        var width = maxX - minX;
        var height = maxY - minY;

        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppRgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.CopyFromScreen(minX, minY, 0, 0, new System.Drawing.Size(width, height), CopyPixelOperation.SourceCopy);
        }

        var data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
        try
        {
            var source = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgr32, null,
                data.Scan0, data.Stride * height, data.Stride);
            source.Freeze();
            return new VirtualScreenCapture
            {
                Image = source,
                Bounds = new Int32Rect(minX, minY, width, height),
                Monitors = monitors,
            };
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }
}

internal static class MonitorEnumerator
{
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hMonitor, int dpiType, out uint dpiX, out uint dpiY);

    public static List<MonitorInfo> Enumerate()
    {
        var list = new List<MonitorInfo>();
        MonitorEnumProc callback = (IntPtr hMonitor, IntPtr _, ref RECT _, IntPtr _) =>
        {
            var info = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
            if (!GetMonitorInfo(hMonitor, ref info)) return true;
            var scale = 1.0;
            if (GetDpiForMonitor(hMonitor, 0 /* MDT_EFFECTIVE_DPI */, out var dpiX, out _) == 0 && dpiX > 0)
                scale = dpiX / 96.0;
            var r = info.rcMonitor;
            list.Add(new MonitorInfo(new Int32Rect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top), scale, (info.dwFlags & 1) != 0));
            return true;
        };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);
        if (list.Count == 0) throw new InvalidOperationException("No monitors were found.");
        return list;
    }
}
