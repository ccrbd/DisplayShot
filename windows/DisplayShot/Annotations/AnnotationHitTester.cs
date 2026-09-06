using System.Windows;

namespace DisplayShot.Annotations;

/// <summary>Decides whether an annotation is touched by the eraser circle (centre p, radius r).</summary>
public static class AnnotationHitTester
{
    public static double DistanceToSegment(Point p, Point a, Point b)
    {
        var dx = b.X - a.X;
        var dy = b.Y - a.Y;
        var len2 = dx * dx + dy * dy;
        if (len2 <= 0) return (p - a).Length;
        var t = Math.Max(0, Math.Min(1, ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / len2));
        return (p - new Point(a.X + t * dx, a.Y + t * dy)).Length;
    }

    private static bool Polyline(IReadOnlyList<Point> pts, Point p, double reach)
    {
        if (pts.Count == 0) return false;
        if (pts.Count == 1) return (pts[0] - p).Length <= reach;
        for (var i = 0; i < pts.Count - 1; i++)
            if (DistanceToSegment(p, pts[i], pts[i + 1]) <= reach) return true;
        return false;
    }

    private static Rect Inflated(Rect r, double d) { var c = r; c.Inflate(d, d); return c; }

    public static bool Hits(Annotation a, Point p, double r) => a switch
    {
        PenAnnotation pen => Polyline(pen.Points, p, r + pen.Stroke.Width / 2),
        MarkerAnnotation m => Polyline(m.Points, p, r + m.Stroke.Width / 2),
        LineAnnotation l => DistanceToSegment(p, l.From, l.To) <= r + Math.Max(l.Stroke.Width / 2, l.Stroke.Width * 1.6),
        ArrowAnnotation ar => DistanceToSegment(p, ar.From, ar.To) <= r + Math.Max(ar.Stroke.Width / 2, ar.Stroke.Width * 1.6),
        RectangleAnnotation rect => Outline(rect.Rect, p, r + rect.Stroke.Width / 2),
        TextAnnotation t => Inflated(new Rect(t.Origin, AnnotationRenderer.MeasureText(t)), r).Contains(p),
        EmojiAnnotation e => Inflated(e.Bounds, r).Contains(p),
        RedactAnnotation rd => Inflated(rd.Rect, r).Contains(p),
        _ => false,
    };

    private static bool Outline(Rect rect, Point p, double reach)
    {
        var tl = rect.TopLeft; var tr = rect.TopRight; var bl = rect.BottomLeft; var br = rect.BottomRight;
        return DistanceToSegment(p, tl, tr) <= reach || DistanceToSegment(p, tr, br) <= reach
            || DistanceToSegment(p, br, bl) <= reach || DistanceToSegment(p, bl, tl) <= reach;
    }
}
