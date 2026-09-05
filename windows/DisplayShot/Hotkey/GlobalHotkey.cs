using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;

namespace DisplayShot.Hotkeys;

/// <summary>Registers one system-wide hotkey with RegisterHotKey on a message-only window.</summary>
public sealed class GlobalHotkey : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const int HotkeyId = 0x4453; // "DS"
    private const uint ModAlt = 0x1, ModControl = 0x2, ModShift = 0x4, ModWin = 0x8, ModNoRepeat = 0x4000;
    private static readonly IntPtr HwndMessage = new(-3);

    private readonly HwndSource _source;
    private bool _registered;

    public event EventHandler? Pressed;

    public GlobalHotkey()
    {
        var parameters = new HwndSourceParameters("DisplayShotHotkeyWindow")
        {
            WindowStyle = 0,
            ExtendedWindowStyle = 0,
            Width = 0,
            Height = 0,
            ParentWindow = HwndMessage,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    public bool Register(Hotkey hotkey)
    {
        Unregister();
        uint mods = ModNoRepeat;
        if (hotkey.Modifiers.HasFlag(ModifierKeys.Alt)) mods |= ModAlt;
        if (hotkey.Modifiers.HasFlag(ModifierKeys.Control)) mods |= ModControl;
        if (hotkey.Modifiers.HasFlag(ModifierKeys.Shift)) mods |= ModShift;
        if (hotkey.Modifiers.HasFlag(ModifierKeys.Windows)) mods |= ModWin;
        var vk = (uint)KeyInterop.VirtualKeyFromKey(hotkey.Key);
        _registered = RegisterHotKey(_source.Handle, HotkeyId, mods, vk);
        return _registered;
    }

    public void Unregister()
    {
        if (!_registered) return;
        UnregisterHotKey(_source.Handle, HotkeyId);
        _registered = false;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && wParam.ToInt32() == HotkeyId)
        {
            handled = true;
            Pressed?.Invoke(this, EventArgs.Empty);
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        Unregister();
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
