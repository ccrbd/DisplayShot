using System.Globalization;
using System.Windows;
using System.Windows.Media;
using DisplayShot.Annotations;
using DisplayShot.Capture;
using DisplayShot.Export;

namespace DisplayShot.Overlay;

/// <summary>The full canvas for the whole virtual screen. Draws in physical pixels: the frozen
/// capture, the dim mask with the selection cut out, redactions, annotations, the selection
/// border/handles and the W×H label. Toolbars are separate elements positioned by the session.</summary>
public sealed class OverlayCanvas : FrameworkElement
{
    private readonly OverlaySession _session;
    private static readonly Brush DimBrush = Frozen(Color.FromArgb(115, 0, 0, 0));
    private static readonly Brush ChromeBrush = Frozen(Color.FromArgb(240, 26, 26, 26));
    private static readonly Brush HintBrush = Frozen(Color.FromArgb(140, 26, 26, 26));
    private static readonly Pen WhitePen = FrozenPen(Colors.White, 1);
    private static readonly Pen DarkPen = FrozenPen(Color.FromArgb(128, 0, 0, 0), 1);
    private static readonly Pen HandleStroke = FrozenPen(Color.FromArgb(153, 0, 0, 0), 1);
    private static readonly Pen DashPen = MakeDashPen();
    private static readonly Typeface LabelTypeface = new(new FontFamily("Consolas"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);
    private static readonly Typeface HintTypeface = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);

    public OverlayCanvas(OverlaySession session)
    {
        _session = session;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.NearestNeighbor);
        IsHitTestVisible = false; // the window handles input; the canvas only paints
    }

    private static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    private static Pen FrozenPen(Color c, double w) { var p = new Pen(new SolidColorBrush(c), w); p.Freeze(); return p; }
    private static Pen MakeDashPen()
    {
        var p = new Pen(new SolidColorBrush(Color.FromArgb(204, 255, 255, 255)), 1) { DashStyle = new DashStyle(new double[] { 4, 3 }, 0) };
        p.Freeze();
        return p;
    }

    protected override void OnRender(DrawingContext dc)
    {
        var capture = _session.Capture;
        var full = new Rect(0, 0, capture.Bounds.Width, capture.Bounds.Height);
        dc.DrawImage(capture.Image, full);

        var sel = _session.Selection?.Rect;
        if (sel is { } s)
        {
            var geometry = new CombinedGeometry(GeometryCombineMode.Exclude,
                new RectangleGeometry(full), new RectangleGeometry(s));
            dc.DrawGeometry(DimBrush, null, geometry);
        }
        else
        {
            dc.DrawRectangle(DimBrush, null, full);
            DrawHint(dc);
            return;
        }

        var selection = sel.Value;
        dc.PushClip(new RectangleGeometry(selection));

        foreach (var a in AllItems())
        {
            if (a is not RedactAnnotation redact) continue;
            var patch = _session.Redactor.GetPatch(capture.Image, ImageComposer.ToInt32Rect(redact.Rect), redact.Mode, redact.Block);
            if (patch is not null)
                dc.DrawImage(patch.Image, new Rect(patch.PixelRect.X, patch.PixelRect.Y, patch.PixelRect.Width, patch.PixelRect.Height));
        }

        AnnotationRenderer.Draw(dc, _session.Store.Items, selection);
        if (_session.InProgress is { } ip)
        {
            if (ip is RedactAnnotation r)
                dc.DrawRectangle(null, DashPen, r.Rect);
            else
                AnnotationRenderer.DrawOne(dc, ip);
        }
        dc.Pop();

        // Selection border (dark under, white over) and handles.
        dc.DrawRectangle(null, DarkPen, Inflate(selection, 1.5));
        dc.DrawRectangle(null, WhitePen, Inflate(selection, 0.5));
        if (_session.ShowsHandles)
        {
            foreach (var (_, rect) in _session.Selection!.HandleRects())
            {
                dc.DrawRectangle(Brushes.White, HandleStroke, rect);
            }
        }

        DrawLabel(dc, selection);
    }

    private IEnumerable<Annotation> AllItems()
    {
        foreach (var a in _session.Store.Items) yield return a;
        if (_session.InProgress is { } ip) yield return ip;
    }

    private void DrawLabel(DrawingContext dc, Rect selection)
    {
        if (!_session.ShowsChrome) return;
        var text = $"{Math.Round(selection.Width)} × {Math.Round(selection.Height)}";
        var ft = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, LabelTypeface, 12, Brushes.White, 1.0);
        var size = new Size(Math.Ceiling(ft.Width) + 12, Math.Ceiling(ft.Height) + 6);
        var rect = new Rect(_session.LabelOrigin, size);
        dc.DrawRoundedRectangle(ChromeBrush, null, rect, 4, 4);
        dc.DrawText(ft, new Point(rect.X + 6, rect.Y + 3));
    }

    private void DrawHint(DrawingContext dc)
    {
        var primary = _session.Capture.Monitors.FirstOrDefault(m => m.IsPrimary) ?? _session.Capture.Monitors[0];
        var center = _session.Capture.CanvasRect(primary);
        var text = $"Drag to select an area   ·   Ctrl+A full screen   ·   Esc to cancel";
        var ft = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, HintTypeface, 13 * primary.DpiScale, Brushes.White, primary.DpiScale);
        // 10 % above centre so the box does not cover what people usually capture; translucent so the screen shows through.
        var rect = new Rect(center.X + (center.Width - ft.Width) / 2 - 14, center.Y + center.Height * 0.40 - ft.Height / 2 - 8, ft.Width + 28, ft.Height + 16);
        dc.DrawRoundedRectangle(HintBrush, null, rect, 8, 8);
        dc.DrawText(ft, new Point(rect.X + 14, rect.Y + 8));
    }

    private static Rect Inflate(Rect r, double d)
    {
        var c = r;
        c.Inflate(d, d);
        return c;
    }
}
