using System.Windows;
using System.Windows.Media;
using DisplayShot.Annotations;
using Xunit;

namespace DisplayShot.Tests;

public class AnnotationTests
{
    private static readonly Stroke S = new(Colors.Black, 2);
    private static LineAnnotation Line(double x) => new(new Point(x, 0), new Point(x, 10), S);

    [Fact]
    public void UndoRedo_Sequential_NewActionClearsRedo()
    {
        var store = new AnnotationStore();
        Assert.False(store.CanUndo);
        store.Add(Line(1)); store.Add(Line(2)); store.Add(Line(3));
        Assert.Equal(3, store.Items.Count);
        Assert.True(store.Undo());
        Assert.Equal(2, store.Items.Count);
        Assert.True(store.CanRedo);
        Assert.True(store.Undo());
        Assert.True(store.Redo());
        Assert.Equal(2, store.Items.Count);
        store.Add(Line(4));
        Assert.False(store.CanRedo);
        store.Clear();
        Assert.True(store.IsEmpty);
        Assert.False(store.Undo());
    }

    [Fact]
    public void Meaningfulness()
    {
        Assert.False(new LineAnnotation(new Point(0, 0), new Point(1, 0), S).IsMeaningful);
        Assert.True(new LineAnnotation(new Point(0, 0), new Point(5, 0), S).IsMeaningful);
        Assert.False(new RectangleAnnotation(new Rect(0, 0, 1, 10), S).IsMeaningful);
        Assert.True(new RedactAnnotation(new Rect(0, 0, 4, 4), RedactMode.Pixelate, 8).IsMeaningful);
        Assert.False(new TextAnnotation(new Point(0, 0), "  \n", Colors.White, 18).IsMeaningful);
    }

    [Fact]
    public void WithWidth_ReplacesSize()
    {
        var a = (ArrowAnnotation)new ArrowAnnotation(new Point(0, 0), new Point(10, 10), S).WithWidth(7);
        Assert.Equal(7, a.Stroke.Width);
        var t = (TextAnnotation)new TextAnnotation(new Point(0, 0), "x", Colors.White, 18).WithWidth(30);
        Assert.Equal(30, t.FontSize);
        var r = (RedactAnnotation)new RedactAnnotation(new Rect(0, 0, 4, 4), RedactMode.Blur, 8).WithWidth(12);
        Assert.Equal(12, r.Block);
    }

    [Fact]
    public void SnapAngle_KeepsLength()
    {
        var snapped = DrawingTools.SnapAngle(new Point(0, 0), new Point(100, 8));
        Assert.Equal(0, snapped.Y, 3);
        Assert.Equal(Math.Sqrt(100 * 100 + 8 * 8), snapped.X, 3);
        var diag = DrawingTools.SnapAngle(new Point(0, 0), new Point(100, 90));
        Assert.Equal(diag.X, diag.Y, 3);
    }

    [Fact]
    public void SquareRect_EveryDirection()
    {
        Assert.Equal(new Rect(10, 10, 30, 30), DrawingTools.RectFrom(new Point(10, 10), new Point(40, 20), true));
        Assert.Equal(new Rect(60, 60, 40, 40), DrawingTools.RectFrom(new Point(100, 100), new Point(90, 60), true));
    }

    [Fact]
    public void DrawingTools_BeginUpdate()
    {
        Assert.Null(DrawingTools.Begin(ToolKind.Text, new Point(0, 0), Colors.White, 18, false));
        var pen = DrawingTools.Begin(ToolKind.Pen, new Point(1, 1), Colors.White, 3, false)!;
        var pen2 = (PenAnnotation)DrawingTools.Update(pen, new Point(1, 1), new Point(5, 5), false);
        Assert.Equal(2, pen2.Points.Count);
        var redact = DrawingTools.Begin(ToolKind.Redact, new Point(10, 10), Colors.White, 8, false)!;
        var blurred = (RedactAnnotation)DrawingTools.Update(redact, new Point(10, 10), new Point(30, 20), true);
        Assert.Equal(RedactMode.Blur, blurred.Mode);
        Assert.Equal(new Rect(10, 10, 20, 10), blurred.Rect);
    }
}
