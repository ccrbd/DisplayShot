using System.Windows;

namespace DisplayShot.Overlay;

public enum Handle { TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left }

public static class HandleExtensions
{
    public static bool AffectsLeft(this Handle h) => h is Handle.TopLeft or Handle.Left or Handle.BottomLeft;
    public static bool AffectsRight(this Handle h) => h is Handle.TopRight or Handle.Right or Handle.BottomRight;
    public static bool AffectsTop(this Handle h) => h is Handle.TopLeft or Handle.Top or Handle.TopRight;
    public static bool AffectsBottom(this Handle h) => h is Handle.BottomLeft or Handle.Bottom or Handle.BottomRight;
    public static bool IsCorner(this Handle h) => (h.AffectsLeft() || h.AffectsRight()) && (h.AffectsTop() || h.AffectsBottom());

    public static Handle? Make(bool left, bool right, bool top, bool bottom) => (left, right, top, bottom) switch
    {
        (true, false, true, false) => Handle.TopLeft,
        (false, false, true, false) => Handle.Top,
        (false, true, true, false) => Handle.TopRight,
        (false, true, false, false) => Handle.Right,
        (false, true, false, true) => Handle.BottomRight,
        (false, false, false, true) => Handle.Bottom,
        (true, false, false, true) => Handle.BottomLeft,
        (true, false, false, false) => Handle.Left,
        _ => null,
    };

    public static Handle FlippedHorizontally(this Handle h) =>
        Make(h.AffectsRight(), h.AffectsLeft(), h.AffectsTop(), h.AffectsBottom()) ?? h;

    public static Handle FlippedVertically(this Handle h) =>
        Make(h.AffectsLeft(), h.AffectsRight(), h.AffectsBottom(), h.AffectsTop()) ?? h;
}

public abstract record SelectionHit
{
    public sealed record HandleHit(Handle Handle) : SelectionHit;
    public sealed record Inside : SelectionHit;
    public sealed record Outside : SelectionHit;
}

/// <summary>The selection rectangle in canvas pixels, always kept inside <see cref="Bounds"/>.</summary>
public sealed class SelectionModel
{
    public const double MinSize = 1;
    public const double HandleSize = 8;
    public const double HandleHitRadius = 9;

    public Rect Rect { get; private set; }
    public Rect Bounds { get; }

    public SelectionModel(Rect rect, Rect bounds)
    {
        Bounds = bounds;
        Rect = Normalize(rect, bounds);
    }

    public static double Clamp(double v, double lo, double hi) => Math.Min(Math.Max(v, lo), hi);

    public static Point ClampPoint(Point p, Rect r) => new(Clamp(p.X, r.Left, r.Right), Clamp(p.Y, r.Top, r.Bottom));

    /// <summary>Shifts the rect into bounds, shrinking only if it is larger than bounds.</summary>
    public static Rect Fit(Rect r, Rect bounds)
    {
        var w = Math.Min(r.Width, bounds.Width);
        var h = Math.Min(r.Height, bounds.Height);
        var x = r.X;
        var y = r.Y;
        if (x < bounds.Left) x = bounds.Left;
        if (x + w > bounds.Right) x = bounds.Right - w;
        if (y < bounds.Top) y = bounds.Top;
        if (y + h > bounds.Bottom) y = bounds.Bottom - h;
        return new Rect(x, y, w, h);
    }

    public static Rect Normalize(Rect r, Rect bounds)
    {
        var x0 = Clamp(r.Left, bounds.Left, bounds.Right);
        var x1 = Clamp(r.Right, bounds.Left, bounds.Right);
        var y0 = Clamp(r.Top, bounds.Top, bounds.Bottom);
        var y1 = Clamp(r.Bottom, bounds.Top, bounds.Bottom);
        return Fit(new Rect(x0, y0, Math.Max(MinSize, x1 - x0), Math.Max(MinSize, y1 - y0)), bounds);
    }

    /// <summary>Rect for a fresh drag; <paramref name="square"/> is the Shift constraint.</summary>
    public static Rect RectFromDrag(Point origin, Point current, bool square, Rect bounds)
    {
        var c = ClampPoint(current, bounds);
        var dx = c.X - origin.X;
        var dy = c.Y - origin.Y;
        if (square)
        {
            var side = Math.Max(Math.Abs(dx), Math.Abs(dy));
            var limX = dx >= 0 ? bounds.Right - origin.X : origin.X - bounds.Left;
            var limY = dy >= 0 ? bounds.Bottom - origin.Y : origin.Y - bounds.Top;
            side = Math.Min(side, Math.Min(limX, limY));
            dx = (dx < 0 ? -1 : 1) * side;
            dy = (dy < 0 ? -1 : 1) * side;
        }
        return new Rect(origin, new Point(origin.X + dx, origin.Y + dy));
    }

    public Point HandleCenter(Handle h)
    {
        var x = h.AffectsLeft() ? Rect.Left : h.AffectsRight() ? Rect.Right : Rect.Left + Rect.Width / 2;
        var y = h.AffectsTop() ? Rect.Top : h.AffectsBottom() ? Rect.Bottom : Rect.Top + Rect.Height / 2;
        return new Point(x, y);
    }

    public IEnumerable<(Handle Handle, Rect Rect)> HandleRects()
    {
        foreach (var h in Enum.GetValues<Handle>())
        {
            var c = HandleCenter(h);
            yield return (h, new Rect(c.X - HandleSize / 2, c.Y - HandleSize / 2, HandleSize, HandleSize));
        }
    }

    public SelectionHit HitTest(Point p)
    {
        var handles = Enum.GetValues<Handle>();
        foreach (var h in handles.Where(h => h.IsCorner()).Concat(handles.Where(h => !h.IsCorner())))
        {
            if ((HandleCenter(h) - p).Length <= HandleHitRadius) return new SelectionHit.HandleHit(h);
        }
        var inflated = Rect;
        inflated.Inflate(2, 2);
        return inflated.Contains(p) ? new SelectionHit.Inside() : new SelectionHit.Outside();
    }

    /// <summary>Drags a handle. Returns the handle now under the pointer (flips when inverted).</summary>
    public Handle Resize(Handle handle, Point point, bool square)
    {
        var p = ClampPoint(point, Bounds);
        double l = Rect.Left, r = Rect.Right, t = Rect.Top, b = Rect.Bottom;

        if (square && handle.IsCorner())
        {
            var ax = handle.AffectsLeft() ? r : l;
            var ay = handle.AffectsTop() ? b : t;
            var sx = p.X >= ax ? 1 : -1;
            var sy = p.Y >= ay ? 1 : -1;
            var side = Math.Max(Math.Abs(p.X - ax), Math.Abs(p.Y - ay));
            var limX = sx > 0 ? Bounds.Right - ax : ax - Bounds.Left;
            var limY = sy > 0 ? Bounds.Bottom - ay : ay - Bounds.Top;
            side = Math.Min(side, Math.Min(limX, limY));
            var nx = ax + sx * side;
            var ny = ay + sy * side;
            Rect = Normalize(new Rect(new Point(ax, ay), new Point(nx, ny)), Bounds);
            return HandleExtensions.Make(sx < 0, sx > 0, sy < 0, sy > 0) ?? handle;
        }

        if (handle.AffectsLeft()) l = p.X;
        if (handle.AffectsRight()) r = p.X;
        if (handle.AffectsTop()) t = p.Y;
        if (handle.AffectsBottom()) b = p.Y;
        var h = handle;
        if (l > r) { (l, r) = (r, l); h = h.FlippedHorizontally(); }
        if (t > b) { (t, b) = (b, t); h = h.FlippedVertically(); }
        Rect = Normalize(new Rect(l, t, r - l, b - t), Bounds);
        return h;
    }

    public void MoveTo(Point origin) => Rect = Fit(new Rect(origin, Rect.Size), Bounds);

    public void Nudge(double dx, double dy) => MoveTo(new Point(Rect.X + dx, Rect.Y + dy));

    /// <summary>Grows/shrinks the right and bottom edges.</summary>
    public void Grow(double dw, double dh)
    {
        var w = Clamp(Rect.Width + dw, MinSize, Bounds.Right - Rect.Left);
        var h = Clamp(Rect.Height + dh, MinSize, Bounds.Bottom - Rect.Top);
        Rect = new Rect(Rect.X, Rect.Y, w, h);
    }
}
