using System.Windows;
using DisplayShot.Overlay;
using Xunit;

namespace DisplayShot.Tests;

public class ToolbarLayoutTests
{
    private static readonly Rect Screen = new(0, 0, 1440, 900);
    private static readonly Size Palette = new(38, 278);
    private static readonly Size Bar = new(150, 38);
    private static readonly Size Label = new(70, 22);
    private const double Gap = ToolbarLayout.Gap;

    private static ToolbarLayout.Result Place(Rect sel) => ToolbarLayout.Place(sel, Screen, Palette, Bar, Label);

    private static void AssertOnScreen(ToolbarLayout.Result r)
    {
        Assert.True(Screen.Contains(r.Palette), $"palette off-screen: {r.Palette}");
        Assert.True(Screen.Contains(r.ActionBar), $"bar off-screen: {r.ActionBar}");
        Assert.True(Screen.Contains(r.Label), $"label off-screen: {r.Label}");
        Assert.False(r.ActionBar.IntersectsWith(r.Palette), "bar overlaps palette");
        Assert.False(r.Label.IntersectsWith(r.ActionBar), "label overlaps bar");
        Assert.False(r.Label.IntersectsWith(r.Palette), "label overlaps palette");
    }

    [Fact]
    public void DefaultPlacement_RightAndBelow()
    {
        var sel = new Rect(200, 200, 400, 300);
        var r = Place(sel);
        Assert.Equal(sel.Right + Gap, r.Palette.Left);
        Assert.Equal(sel.Top, r.Palette.Top);
        Assert.Equal(sel.Bottom + Gap, r.ActionBar.Top);
        AssertOnScreen(r);
    }

    [Fact]
    public void FlipsNearRightAndBottomEdges()
    {
        var sel = new Rect(1000, 500, 430, 390);
        var r = Place(sel);
        Assert.Equal(sel.Left - Gap, r.Palette.Right);
        Assert.Equal(sel.Top - Gap, r.ActionBar.Bottom);
        AssertOnScreen(r);
    }

    [Fact]
    public void FallsInsideWhenNoRoom()
    {
        AssertOnScreen(Place(Screen));
    }

    [Fact]
    public void LabelMovesInsideAtTopEdge()
    {
        var sel = new Rect(100, 5, 300, 200);
        var r = Place(sel);
        Assert.True(sel.Contains(r.Label));
        AssertOnScreen(r);
    }

    [Theory]
    [InlineData(1420, 880)]
    [InlineData(0, 0)]
    [InlineData(0, 880)]
    [InlineData(1420, 0)]
    public void TinySelectionsInCornersFit(double x, double y)
    {
        AssertOnScreen(Place(new Rect(x, y, 15, 15)));
    }
}
