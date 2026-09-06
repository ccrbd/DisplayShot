using System.Windows;
using System.Windows.Media;

namespace DisplayShot.Annotations;

public enum ToolKind { Pen, Line, Arrow, Rectangle, Marker, Text, Emoji, Redact }

public enum RedactMode { Pixelate, Blur, Blackout }

public static class RedactModeExtensions
{
    public static string Title(this RedactMode mode) => mode switch
    {
        RedactMode.Pixelate => "Mosaic (pixelate)",
        RedactMode.Blur => "Blur",
        RedactMode.Blackout => "Blackout",
        _ => mode.ToString(),
    };
}

public static class ToolKindExtensions
{
    public static IReadOnlyList<ToolKind> All { get; } = Enum.GetValues<ToolKind>();

    /// <summary>Default width (font size for Text, block size for Redact) in device-independent units.</summary>
    public static double DefaultWidth(this ToolKind tool) => tool switch
    {
        ToolKind.Pen => 3,
        ToolKind.Line => 3,
        ToolKind.Arrow => 4,
        ToolKind.Rectangle => 3,
        ToolKind.Marker => 14,
        ToolKind.Text => 18,
        ToolKind.Emoji => 48,
        ToolKind.Redact => 8,
        _ => 3,
    };

    public static (double Min, double Max) WidthRange(this ToolKind tool) => tool switch
    {
        ToolKind.Text => (8, 96),
        ToolKind.Emoji => (16, 256),
        ToolKind.Redact => (2, 64),
        _ => (1, 32),
    };

    public static string Title(this ToolKind tool) => tool switch
    {
        ToolKind.Pen => "Pen",
        ToolKind.Line => "Line",
        ToolKind.Arrow => "Arrow",
        ToolKind.Rectangle => "Rectangle",
        ToolKind.Marker => "Marker",
        ToolKind.Text => "Text",
        ToolKind.Emoji => "Emoji",
        ToolKind.Redact => "Redact",
        _ => tool.ToString(),
    };

    /// <summary>Single-key shortcut inside the overlay.</summary>
    public static char Key(this ToolKind tool) => tool switch
    {
        ToolKind.Pen => 'P',
        ToolKind.Line => 'L',
        ToolKind.Arrow => 'A',
        ToolKind.Rectangle => 'R',
        ToolKind.Marker => 'M',
        ToolKind.Text => 'T',
        ToolKind.Emoji => 'E',
        ToolKind.Redact => 'X',
        _ => '?',
    };
}

public readonly record struct Stroke(Color Color, double Width);

/// <summary>One annotation in canvas coordinates (physical pixels, top-left origin).</summary>
public abstract record Annotation
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public abstract bool IsMeaningful { get; }
    public abstract Annotation WithWidth(double width);
    public bool IsMarker => this is MarkerAnnotation;
    public bool IsRedaction => this is RedactAnnotation;
}

public sealed record PenAnnotation(IReadOnlyList<Point> Points, Stroke Stroke) : Annotation
{
    public override bool IsMeaningful => Points.Count > 0;
    public override Annotation WithWidth(double width) => this with { Stroke = Stroke with { Width = width } };
}

public sealed record MarkerAnnotation(IReadOnlyList<Point> Points, Stroke Stroke) : Annotation
{
    public override bool IsMeaningful => Points.Count > 0;
    public override Annotation WithWidth(double width) => this with { Stroke = Stroke with { Width = width } };
}

public sealed record LineAnnotation(Point From, Point To, Stroke Stroke) : Annotation
{
    public override bool IsMeaningful => (To - From).Length >= 2;
    public override Annotation WithWidth(double width) => this with { Stroke = Stroke with { Width = width } };
}

public sealed record ArrowAnnotation(Point From, Point To, Stroke Stroke) : Annotation
{
    public override bool IsMeaningful => (To - From).Length >= 2;
    public override Annotation WithWidth(double width) => this with { Stroke = Stroke with { Width = width } };
}

public sealed record RectangleAnnotation(Rect Rect, Stroke Stroke) : Annotation
{
    public override bool IsMeaningful => Rect.Width >= 2 && Rect.Height >= 2;
    public override Annotation WithWidth(double width) => this with { Stroke = Stroke with { Width = width } };
}

public sealed record TextAnnotation(Point Origin, string Text, Color Color, double FontSize) : Annotation
{
    public override bool IsMeaningful => !string.IsNullOrWhiteSpace(Text);
    public override Annotation WithWidth(double width) => this with { FontSize = width };
}

/// <summary>A single emoji stamped on the canvas; Size is the font size, Rotation in degrees.
/// WPF renders emoji as monochrome glyphs, so the annotation colour is used as the fill.</summary>
public sealed record EmojiAnnotation(Point Center, string Text, double Size, double Rotation, Color Color) : Annotation
{
    public override bool IsMeaningful => !string.IsNullOrEmpty(Text) && Size > 0;
    public override Annotation WithWidth(double width) => this with { Size = width };

    /// <summary>Unrotated bounding box used for hit-testing.</summary>
    public Rect Bounds => new(Center.X - Size * 0.6, Center.Y - Size * 0.6, Size * 1.2, Size * 1.2);
}

/// <summary>Rect, mode and block size (pixels) of a pixelate/blur/blackout region.</summary>
public sealed record RedactAnnotation(Rect Rect, RedactMode Mode, double Block) : Annotation
{
    public override bool IsMeaningful => Rect.Width >= 2 && Rect.Height >= 2;
    public override Annotation WithWidth(double width) => this with { Block = width };
}
