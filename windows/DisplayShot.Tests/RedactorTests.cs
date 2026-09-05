using System.Windows;
using DisplayShot.Export;
using Xunit;

namespace DisplayShot.Tests;

/// <summary>Tests the pure pixel functions directly (no UI thread needed).</summary>
public class RedactorTests
{
    // 2px checkerboard as a BGR32 byte buffer.
    private static byte[] Checkerboard(int w, int h, int stride)
    {
        var data = new byte[stride * h];
        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var dark = ((x / 2) + (y / 2)) % 2 == 0;
            var v = (byte)(dark ? 0 : 255);
            var i = y * stride + x * 4;
            data[i] = v; data[i + 1] = v; data[i + 2] = v; data[i + 3] = 255;
        }
        return data;
    }

    [Fact]
    public void Pixelate_ChangesPixels_AndIsGridAlignedToImage()
    {
        const int w = 64, h = 64, stride = w * 4;
        var src = Checkerboard(w, h, stride);

        // Same block region requested at two rects offset by 3px: the overlapping output must match,
        // proving the grid is anchored to the image, not the rect.
        var r1 = new Int32Rect(8, 8, 32, 32);
        var r2 = new Int32Rect(11, 10, 32, 32);
        var a = Redactor.Pixelate(src, stride, w, h, r1, 8);
        var b = Redactor.Pixelate(src, stride, w, h, r2, 8);

        // Compare the shared pixel window [16,40) x [16,40) in image space.
        for (var y = 16; y < 40; y++)
        for (var x = 16; x < 40; x++)
        {
            var ia = (y - r1.Y) * (r1.Width * 4) + (x - r1.X) * 4;
            var ib = (y - r2.Y) * (r2.Width * 4) + (x - r2.X) * 4;
            Assert.Equal(a[ia], b[ib]);
        }

        // A checkerboard block averages to mid-grey, i.e. not the original 0/255.
        Assert.True(a[0] is > 40 and < 215, $"expected averaged grey, got {a[0]}");
    }

    [Fact]
    public void Blur_ChangesPixels()
    {
        const int w = 40, h = 40, stride = w * 4;
        var src = Checkerboard(w, h, stride);
        var r = new Int32Rect(8, 8, 20, 20);
        var blurred = Redactor.Blur(src, stride, w, h, r, 6);
        // The centre of a blurred checkerboard is grey, not a hard 0/255.
        var centre = (10 * (r.Width * 4)) + 10 * 4;
        Assert.True(blurred[centre] is > 40 and < 215, $"expected blurred grey, got {blurred[centre]}");
    }

    [Fact]
    public void Intersect()
    {
        Assert.Equal(new Int32Rect(5, 5, 5, 5), Redactor.Intersect(new Int32Rect(0, 0, 10, 10), new Int32Rect(5, 5, 20, 20)));
        Assert.True(Redactor.Intersect(new Int32Rect(0, 0, 5, 5), new Int32Rect(10, 10, 5, 5)).IsEmpty);
    }
}
