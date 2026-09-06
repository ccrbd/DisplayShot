using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Input;
using DisplayShot.Annotations;
using DisplayShot.Export;
using DisplayShot.Hotkeys;

namespace DisplayShot.Configuration;

/// <summary>JSON settings stored in %APPDATA%\DisplayShot\settings.json.</summary>
public sealed class Settings
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public Key HotkeyKey { get; set; } = Hotkey.Default.Key;
    public ModifierKeys HotkeyModifiers { get; set; } = Hotkey.Default.Modifiers;
    public string SaveDirectory { get; set; } = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    public bool SaveWithoutAsking { get; set; }
    public bool PlaySound { get; set; } = true;
    public Dictionary<string, double> ToolWidths { get; set; } = new();
    public int LastColorIndex { get; set; }
    /// <summary>Format the save dialog defaults to; silent save always uses it.</summary>
    public ImageFormat SaveFormat { get; set; } = ImageFormat.Jpeg;
    public RedactMode RedactMode { get; set; } = RedactMode.Pixelate;
    public string LastEmoji { get; set; } = "👍";

    [JsonIgnore]
    public Hotkey Hotkey
    {
        get => new(HotkeyKey, HotkeyModifiers);
        set { HotkeyKey = value.Key; HotkeyModifiers = value.Modifiers; }
    }

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DisplayShot", "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Options) ?? new Settings();
        }
        catch
        {
            // Corrupt settings fall back to defaults.
        }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
        }
        catch
        {
            // Settings are a convenience; never crash the app over them.
        }
    }

    /// <summary>Stroke width / font size / block size per tool, in device-independent units.</summary>
    public double WidthFor(ToolKind tool) =>
        ToolWidths.TryGetValue(tool.ToString(), out var w) ? w : tool.DefaultWidth();

    public void SetWidth(ToolKind tool, double width) => ToolWidths[tool.ToString()] = width;
}
