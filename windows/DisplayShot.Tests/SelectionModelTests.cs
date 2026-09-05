using System.Windows;
using DisplayShot.Overlay;
using Xunit;

namespace DisplayShot.Tests;

public class SelectionModelTests
{
    private static readonly Rect Bounds = new(0, 0, 1000, 600);

    [Fact]
    public void DragRect_NormalizesAndClamps()
    {
        var r = SelectionModel.RectFromDrag(new Point(300, 200), new Point(100, 700), false, Bounds);
        Assert.Equal(new Rect(100, 200, 200, 400), r);
    }

    [Fact]
    public void SquareDrag_UsesLargerSide_AndRespectsBounds()
    {
        Assert.Equal(new Rect(100, 100, 200, 200),
            SelectionModel.RectFromDrag(new Point(100, 100), new Point(300, 150), true, Bounds));
        Assert.Equal(new Rect(900, 100, 100, 100),
            SelectionModel.RectFromDrag(new Point(900, 100), new Point(990, 500), true, Bounds));
    }

    [Fact]
    public void HitTest_HandlesInsideOutside()
    {
        var m = new SelectionModel(new Rect(100, 100, 200, 100), Bounds);
        Assert.Equal(Handle.TopLeft, ((SelectionHit.HandleHit)m.HitTest(new Point(100, 100))).Handle);
        Assert.Equal(Handle.Right, ((SelectionHit.HandleHit)m.HitTest(new Point(300, 150))).Handle);
        Assert.Equal(Handle.BottomRight, ((SelectionHit.HandleHit)m.HitTest(new Point(300, 200))).Handle);
        Assert.IsType<SelectionHit.Inside>(m.HitTest(new Point(200, 150)));
        Assert.IsType<SelectionHit.Outside>(m.HitTest(new Point(50, 50)));
    }

    [Fact]
    public void Resize_Edge_ThenFlipThroughItself()
    {
        var m = new SelectionModel(new Rect(100, 100, 200, 100), Bounds);
        Assert.Equal(Handle.Right, m.Resize(Handle.Right, new Point(400, 999), false));
        Assert.Equal(new Rect(100, 100, 300, 100), m.Rect);
        Assert.Equal(Handle.Left, m.Resize(Handle.Right, new Point(50, 0), false));
        Assert.Equal(new Rect(50, 100, 50, 100), m.Rect);
    }

    [Fact]
    public void Resize_Corner_Square()
    {
        var m = new SelectionModel(new Rect(100, 100, 200, 100), Bounds);
        Assert.Equal(Handle.BottomRight, m.Resize(Handle.BottomRight, new Point(400, 150), true));
        Assert.Equal(new Rect(100, 100, 300, 300), m.Rect);
    }

    [Fact]
    public void Move_ClampsToBounds()
    {
        var m = new SelectionModel(new Rect(100, 100, 200, 100), Bounds);
        m.MoveTo(new Point(950, -20));
        Assert.Equal(new Rect(800, 0, 200, 100), m.Rect);
    }

    [Fact]
    public void NudgeAndGrow()
    {
        var m = new SelectionModel(new Rect(100, 100, 200, 100), Bounds);
        m.Nudge(1, -1);
        Assert.Equal(new Point(101, 99), m.Rect.TopLeft);
        m.Grow(10, 10);
        Assert.Equal(new Size(210, 110), m.Rect.Size);
        m.Grow(100000, 0);
        Assert.Equal(Bounds.Right, m.Rect.Right);
        m.Grow(-100000, 0);
        Assert.Equal(SelectionModel.MinSize, m.Rect.Width);
    }

    [Fact]
    public void OversizedRect_ClampedToBounds()
    {
        var big = Bounds;
        big.Inflate(50, 50);
        Assert.Equal(Bounds, new SelectionModel(big, Bounds).Rect);
    }

    [Fact]
    public void HandleFlips()
    {
        Assert.Equal(Handle.TopRight, Handle.TopLeft.FlippedHorizontally());
        Assert.Equal(Handle.Right, Handle.Left.FlippedHorizontally());
        Assert.Equal(Handle.Top, Handle.Top.FlippedHorizontally());
        Assert.Equal(Handle.TopLeft, Handle.BottomLeft.FlippedVertically());
    }
}
