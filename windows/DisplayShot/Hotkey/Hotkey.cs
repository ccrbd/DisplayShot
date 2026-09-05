using System.Windows.Input;

namespace DisplayShot.Hotkeys;

/// <summary>A global shortcut. Default is Print Screen; Ctrl+Shift+1 is the fallback when the
/// Snipping Tool owns Print Screen.</summary>
public readonly record struct Hotkey(Key Key, ModifierKeys Modifiers)
{
    public static Hotkey Default => new(Key.PrintScreen, ModifierKeys.None);
    public static Hotkey Fallback => new(Key.D1, ModifierKeys.Control | ModifierKeys.Shift);

    /// <summary>Function keys and Print Screen may stand alone; everything else needs Ctrl, Alt or Win.</summary>
    public bool IsValid =>
        Key is Key.PrintScreen or (>= Key.F1 and <= Key.F24)
        || (Modifiers & ~ModifierKeys.Shift) != 0 && Key is not (Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin or Key.None);

    public override string ToString()
    {
        var parts = new List<string>(5);
        if (Modifiers.HasFlag(ModifierKeys.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(ModifierKeys.Windows)) parts.Add("Win");
        parts.Add(KeyLabel(Key));
        return string.Join("+", parts);
    }

    public static string KeyLabel(Key key) => key switch
    {
        Key.PrintScreen => "PrtScn",
        >= Key.D0 and <= Key.D9 => ((char)('0' + (key - Key.D0))).ToString(),
        >= Key.NumPad0 and <= Key.NumPad9 => "Num" + (key - Key.NumPad0),
        Key.OemPlus => "=",
        Key.OemMinus => "-",
        Key.OemComma => ",",
        Key.OemPeriod => ".",
        Key.OemQuestion => "/",
        Key.OemTilde => "`",
        Key.OemOpenBrackets => "[",
        Key.OemCloseBrackets => "]",
        Key.OemPipe => "\\",
        Key.OemSemicolon => ";",
        Key.OemQuotes => "'",
        Key.Return => "Enter",
        Key.Space => "Space",
        Key.Escape => "Esc",
        Key.Back => "Backspace",
        Key.Delete => "Del",
        Key.Insert => "Ins",
        Key.PageUp => "PgUp",
        Key.PageDown => "PgDn",
        _ => key.ToString(),
    };
}
