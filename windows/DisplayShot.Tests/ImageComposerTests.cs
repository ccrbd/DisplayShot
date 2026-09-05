using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DisplayShot.Annotations;
using DisplayShot.Export;
using Xunit;

namespace DisplayShot.Tests;

/// <summary>End-to-end composition. Runs on an STA thread because RenderTargetBitmap requires it.</summary>
public class ImageComposerTests
{
    private static BitmapSource Checkerboard(int w, int h)
    {
        var stride = w * 4;
        var data = new byte[stride * h];
        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var dark = ((x / 2) + (y / 2)) % 2 == 0;
            var v = (byte)(dark ? 0 : 255);
            var i = y * stride + x * 4;
            data[i] = v; data[i + 1] = v; data[i + 2] = v; data[i + 3] = 255;
        }
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, data, stride);
        bmp.Freeze();
        return bmp;
    }

    private static byte[] Pixels(BitmapSource image, out int stride)
    {
        stride = image.PixelWidth * 4;
        var data = new byte[stride * image.PixelHeight];
        var converted = image.Format == PixelFormats.Bgra32 ? image : new FormatConvertedBitmap(image, PixelFormats.Bgra32, null, 0);
        converted.CopyPixels(data, stride, 0);
        return data;
    }

    private static bool RegionEqual(byte[] a, int sa, byte[] b, int sb, Int32Rect r)
    {
        for (var y = r.Y; y < r.Y + r.Height; y++)
        for (var x = r.X; x < r.X + r.Width; x++)
        {
            var ia = y * sa + x * 4;
            var ib = y * sb + x * 4;
            for (var c = 0; c < 4; c++) if (a[ia + c] != b[ib + c]) return false;
        }
        return true;
    }

    [Fact]
    public void OutputSize_MatchesSelection() => StaRunner.Run(() =>
    {
        var img = ImageComposer.Compose(Checkerboard(400, 200), new Rect(10, 10, 100, 50), Array.Empty<Annotation>(), new Redactor());
        Assert.NotNull(img);
        Assert.Equal(100, img!.PixelWidth);
        Assert.Equal(50, img.PixelHeight);
    });

    [Fact]
    public void Redaction_ChangesOnlyInsideRect() => StaRunner.Run(() =>
    {
        var src = Checkerboard(400, 200);
        var sel = new Rect(0, 0, 200, 100);
        var redactor = new Redactor();
        var plain = Pixels(ImageComposer.Compose(src, sel, Array.Empty<Annotation>(), redactor)!, out var s1);
        var redact = new RedactAnnotation(new Rect(50, 20, 40, 20), RedactMode.Pixelate, 8);
        var done = Pixels(ImageComposer.Compose(src, sel, new Annotation[] { redact }, redactor)!, out var s2);

        Assert.False(RegionEqual(plain, s1, done, s2, new Int32Rect(52, 22, 36, 16)), "inside should differ");
        Assert.True(RegionEqual(plain, s1, done, s2, new Int32Rect(0, 0, 200, 18)), "above must be untouched");
        Assert.True(RegionEqual(plain, s1, done, s2, new Int32Rect(100, 22, 100, 16)), "right must be untouched");
    });

    [Fact]
    public void Annotation_IsDrawnAndClipped() => StaRunner.Run(() =>
    {
        var src = Checkerboard(200, 100);
        var sel = new Rect(20, 20, 40, 20);
        var stroke = new Stroke(Colors.Red, 6);
        var plain = Pixels(ImageComposer.Compose(src, sel, Array.Empty<Annotation>(), new Redactor())!, out var s1);
        // A line entirely outside the selection must not appear.
        var outside = new LineAnnotation(new Point(0, 0), new Point(10, 10), stroke);
        var clipped = Pixels(ImageComposer.Compose(src, sel, new Annotation[] { outside }, new Redactor())!, out var s2);
        Assert.True(RegionEqual(plain, s1, clipped, s2, new Int32Rect(0, 0, 40, 20)), "outside line must be clipped away");
        // A rectangle inside the selection must change pixels.
        var inside = new RectangleAnnotation(new Rect(25, 25, 20, 10), stroke);
        var drawn = Pixels(ImageComposer.Compose(src, sel, new Annotation[] { inside }, new Redactor())!, out var s3);
        Assert.False(RegionEqual(plain, s1, drawn, s3, new Int32Rect(0, 0, 40, 20)), "inside rectangle should draw");
    });

    [Fact]
    public void PngEncoding() => StaRunner.Run(() =>
    {
        var png = ImageComposer.EncodePng(Checkerboard(16, 16));
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47 }, png.Take(4).ToArray());
    });

    [Fact]
    public void DefaultFilename_Format()
    {
        var name = FileExporter.DefaultFilename(new DateTime(2026, 9, 5, 17, 52, 10));
        Assert.StartsWith("DisplayShot ", name);
        Assert.EndsWith(".png", name);
        Assert.Contains(" at ", name);
    }
}
