using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace DisplayShot.Annotations;

/// <summary>Draws annotations into a DrawingContext. Units are canvas pixels; the caller sets up
/// any transform. Used by both the live overlay and the exporter.</summary>
public static class AnnotationRenderer
{
    public const double MarkerAlpha = 0.35;
    private static readonly Typeface TextTypeface = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);

    /// <summary>Draws everything except redactions (pixel operations handled by ImageComposer).
    /// Markers are grouped so overlapping strokes never double-darken.</summary>
    public static void Draw(DrawingContext dc, IReadOnlyList<Annotation> items, Rect? clip, bool includeMarkers = true)
    {
        if (clip is { } c) dc.PushClip(new RectangleGeometry(c));

        if (includeMarkers && items.Any(a => a.IsMarker))
        {
            dc.PushOpacity(MarkerAlpha);
            foreach (var a in items)
                if (a is MarkerAnnotation m) DrawStroke(dc, m.Points, m.Stroke);
            dc.Pop();
        }

        foreach (var a in items)
        {
            if (a.IsMarker || a.IsRedaction) continue;
            DrawOne(dc, a);
        }

        if (clip is not null) dc.Pop();
    }

    /// <summary>Draws only the marker strokes, fully opaque (used for the multiply pass on export).</summary>
    public static void DrawMarkersOpaque(DrawingContext dc, IReadOnlyList<Annotation> items)
    {
        foreach (var a in items)
            if (a is MarkerAnnotation m) DrawStroke(dc, m.Points, m.Stroke);
    }

    /// <summary>Draws one annotation (used for the in-progress shape).</summary>
    public static void DrawOne(DrawingContext dc, Annotation a)
    {
        switch (a)
        {
            case PenAnnotation pen:
                DrawStroke(dc, pen.Points, pen.Stroke);
                break;
            case MarkerAnnotation marker:
                dc.PushOpacity(MarkerAlpha);
                DrawStroke(dc, marker.Points, marker.Stroke);
                dc.Pop();
                break;
            case LineAnnotation line:
                dc.DrawLine(MakePen(line.Stroke), line.From, line.To);
                break;
            case ArrowAnnotation arrow:
                DrawArrow(dc, arrow.From, arrow.To, arrow.Stroke);
                break;
            case RectangleAnnotation rect:
                dc.DrawRectangle(null, MakePen(rect.Stroke), rect.Rect);
                break;
            case TextAnnotation text:
                DrawText(dc, text);
                break;
        }
    }

    public static Pen MakePen(Stroke s)
    {
        var pen = new Pen(new SolidColorBrush(s.Color), s.Width)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        return pen;
    }

    /// <summary>Smooth freehand stroke: quadratic curves through the midpoints.</summary>
    public static void DrawStroke(DrawingContext dc, IReadOnlyList<Point> pts, Stroke s)
    {
        if (pts.Count == 0) return;
        var pen = MakePen(s);
        if (pts.Count <= 2)
        {
            dc.DrawLine(pen, pts[0], pts[^1]);
            return;
        }
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            ctx.BeginFigure(pts[0], false, false);
            for (var i = 1; i < pts.Count - 1; i++)
            {
                var mid = new Point((pts[i].X + pts[i + 1].X) / 2, (pts[i].Y + pts[i + 1].Y) / 2);
                ctx.QuadraticBezierTo(pts[i], mid, true, false);
            }
            ctx.LineTo(pts[^1], true, false);
        }
        geometry.Freeze();
        dc.DrawGeometry(null, pen, geometry);
    }

    public static void DrawArrow(DrawingContext dc, Point p, Point q, Stroke s)
    {
        var dx = q.X - p.X;
        var dy = q.Y - p.Y;
        var len = Math.Sqrt(dx * dx + dy * dy);
        if (len < 0.5) return;
        var ux = dx / len;
        var uy = dy / len;
        var headLength = Math.Max(12, s.Width * 4);
        var headWidth = Math.Max(10, s.Width * 3.2);
        var basePoint = new Point(q.X - ux * headLength, q.Y - uy * headLength);
        var shaftEnd = new Point(q.X - ux * headLength * 0.7, q.Y - uy * headLength * 0.7);

        dc.DrawLine(MakePen(s), p, shaftEnd);

        var nx = -uy;
        var ny = ux;
        var left = new Point(basePoint.X + nx * headWidth / 2, basePoint.Y + ny * headWidth / 2);
        var right = new Point(basePoint.X - nx * headWidth / 2, basePoint.Y - ny * headWidth / 2);
        var head = new StreamGeometry();
        using (var ctx = head.Open())
        {
            ctx.BeginFigure(q, true, true);
            ctx.LineTo(left, false, false);
            ctx.LineTo(right, false, false);
        }
        head.Freeze();
        dc.DrawGeometry(new SolidColorBrush(s.Color), null, head);
    }

    public static FormattedText MakeFormattedText(TextAnnotation t, Brush brush) =>
        new(t.Text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, TextTypeface, t.FontSize, brush, 1.0);

    public static Size MeasureText(TextAnnotation t)
    {
        var ft = MakeFormattedText(t, Brushes.Black);
        return new Size(Math.Ceiling(ft.WidthIncludingTrailingWhitespace), Math.Ceiling(ft.Height));
    }

    /// <summary>Text with a soft dark shadow so it stays legible on any background.</summary>
    public static void DrawText(DrawingContext dc, TextAnnotation t)
    {
        var shadow = MakeFormattedText(t, new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0)));
        var offset = Math.Max(1, t.FontSize / 18);
        dc.DrawText(shadow, new Point(t.Origin.X + offset, t.Origin.Y + offset));
        dc.DrawText(MakeFormattedText(t, new SolidColorBrush(t.Color)), t.Origin);
    }
}
