using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using DisplayShot.Annotations;

namespace DisplayShot.Overlay;

/// <summary>Builds the tool palette, action bar and colour strip as lightweight WPF panels.
/// Buttons use the tool's own shortcut letter (P/L/A/R/M/T/X) so nothing depends on an icon font.</summary>
public static class OverlayChrome
{
    public const double ButtonSize = 28;
    public static readonly Brush Chrome = Freeze(Color.FromArgb(240, 26, 26, 26));
    public static readonly Brush ChromeBorder = Freeze(Color.FromArgb(31, 255, 255, 255));
    public static readonly Brush Highlight = Freeze(Color.FromArgb(46, 255, 255, 255));

    public static readonly Color[] Palette =
    {
        Color.FromRgb(0xFF, 0x3B, 0x30), Color.FromRgb(0xFF, 0x95, 0x00), Color.FromRgb(0xFF, 0xD6, 0x0A),
        Color.FromRgb(0x34, 0xC7, 0x59), Color.FromRgb(0x0A, 0x84, 0xFF), Color.FromRgb(0xBF, 0x5A, 0xF2),
        Color.FromRgb(0xFF, 0x2D, 0x55), Color.FromRgb(0x00, 0x00, 0x00), Color.FromRgb(0xFF, 0xFF, 0xFF),
        Color.FromRgb(0x8E, 0x8E, 0x93),
    };

    public static readonly string[] EmojiPresets =
        { "👍", "❤️", "😀", "😂", "🔥", "✅", "❌", "⭐", "👉", "⚠️", "💡", "🎯", "📌", "❓" };

    private static Brush Freeze(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

    public static Border Panel(UIElement child) => new()
    {
        Background = Chrome,
        BorderBrush = ChromeBorder,
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(5),
        Child = child,
        SnapsToDevicePixels = true,
    };

    /// <summary>A flat square button showing a short glyph or letter in Segoe UI.</summary>
    public static Button LabelButton(string label, string tooltip, double fontSize = 13, double width = ButtonSize)
    {
        var button = new Button
        {
            Content = new TextBlock
            {
                Text = label,
                FontFamily = new FontFamily("Segoe UI"),
                FontWeight = FontWeights.SemiBold,
                FontSize = fontSize,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
            Width = width,
            Height = ButtonSize,
            ToolTip = tooltip,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Focusable = false,
            Cursor = System.Windows.Input.Cursors.Arrow,
            Template = FlatButtonTemplate(),
        };
        return button;
    }

    public static Button ToolButton(ToolKind tool) =>
        LabelButton(tool.Key().ToString(), $"{tool.Title()} ({tool.Key()})");

    private static ControlTemplate FlatButtonTemplate()
    {
        var template = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);
        template.VisualTree = border;
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Control.BackgroundProperty, Highlight));
        template.Triggers.Add(hover);
        return template;
    }

    public static Ellipse Swatch(Color color, double size) => new()
    {
        Width = size,
        Height = size,
        Fill = new SolidColorBrush(color),
        Stroke = new SolidColorBrush(Color.FromArgb(128, 255, 255, 255)),
        StrokeThickness = 1,
    };
}
