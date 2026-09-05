using System.Windows;
using System.Windows.Media;

namespace DisplayShot.Annotations;

/// <summary>Pure helpers that create and extend the in-progress annotation for each tool.</summary>
public static class DrawingTools
{
    /// <summary>Starts an annotation for <paramref name="tool"/>; null for tools that do not drag (Text).</summary>
    public static Annotation? Begin(ToolKind tool, Point p, Color color, double width, bool blur)
    {
        var stroke = new Stroke(color, width);
        return tool switch
        {
            ToolKind.Pen => new PenAnnotation(new List<Point> { p }, stroke),
            ToolKind.Marker => new MarkerAnnotation(new List<Point> { p }, stroke),
            ToolKind.Line => new LineAnnotation(p, p, stroke),
            ToolKind.Arrow => new ArrowAnnotation(p, p, stroke),
            ToolKind.Rectangle => new RectangleAnnotation(new Rect(p, new Size(0, 0)), stroke),
            ToolKind.Redact => new RedactAnnotation(new Rect(p, new Size(0, 0)), blur ? RedactMode.Blur : RedactMode.Pixelate, width),
            _ => null,
        };
    }

    /// <summary>Extends the annotation to the pointer. <paramref name="constrain"/> is Shift:
    /// 45° snapping for line/arrow, square for rectangle, blur for redaction.</summary>
    public static Annotation Update(Annotation annotation, Point origin, Point p, bool constrain)
    {
        switch (annotation)
        {
            case PenAnnotation pen:
                return pen with { Points = Append(pen.Points, p) };
            case MarkerAnnotation marker:
                return marker with { Points = Append(marker.Points, p) };
            case LineAnnotation line:
                return line with { To = constrain ? SnapAngle(line.From, p) : p };
            case ArrowAnnotation arrow:
                return arrow with { To = constrain ? SnapAngle(arrow.From, p) : p };
            case RectangleAnnotation rect:
                return rect with { Rect = RectFrom(origin, p, constrain) };
            case RedactAnnotation redact:
                return redact with { Rect = new Rect(origin, p), Mode = constrain ? RedactMode.Blur : RedactMode.Pixelate };
            default:
                return annotation;
        }
    }

    private static IReadOnlyList<Point> Append(IReadOnlyList<Point> points, Point p)
    {
        if (points.Count > 0 && points[^1] == p) return points;
        var list = new List<Point>(points.Count + 1);
        list.AddRange(points);
        list.Add(p);
        return list;
    }

    public static Rect RectFrom(Point o, Point p, bool square)
    {
        if (!square) return new Rect(o, p);
        var dx = p.X - o.X;
        var dy = p.Y - o.Y;
        var side = Math.Max(Math.Abs(dx), Math.Abs(dy));
        var sx = dx < 0 ? -1 : 1;
        var sy = dy < 0 ? -1 : 1;
        return new Rect(o, new Point(o.X + sx * side, o.Y + sy * side));
    }

    /// <summary>Snaps the segment a→b to the nearest multiple of 45°, keeping its length.</summary>
    public static Point SnapAngle(Point a, Point b)
    {
        var dx = b.X - a.X;
        var dy = b.Y - a.Y;
        var len = Math.Sqrt(dx * dx + dy * dy);
        if (len <= 0) return b;
        var step = Math.PI / 4;
        var angle = Math.Round(Math.Atan2(dy, dx) / step) * step;
        return new Point(a.X + Math.Cos(angle) * len, a.Y + Math.Sin(angle) * len);
    }
}
