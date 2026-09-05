using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace DisplayShot.Export;

/// <summary>Pixelate / blur patches computed from the source image. The pixelation grid is
/// anchored at the image origin so blocks never shift when a region moves.</summary>
public sealed class Redactor
{
    public sealed record Patch(BitmapSource Image, Int32Rect PixelRect);

    private readonly Dictionary<string, Patch> _cache = new();
    private byte[]? _sourcePixels;
    private int _sourceStride;
    private BitmapSource? _source;

    public void ClearCache() => _cache.Clear();

    private void EnsureSource(BitmapSource source)
    {
        if (ReferenceEquals(_source, source) && _sourcePixels is not null) return;
        _source = source;
        _sourceStride = source.PixelWidth * 4;
        _sourcePixels = new byte[_sourceStride * source.PixelHeight];
        var converted = source.Format == PixelFormats.Bgra32 || source.Format == PixelFormats.Bgr32 || source.Format == PixelFormats.Pbgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgr32, null, 0);
        converted.CopyPixels(_sourcePixels, _sourceStride, 0);
        _cache.Clear();
    }

    public Patch? GetPatch(BitmapSource source, Int32Rect pixelRect, Annotations.RedactMode mode, double blockPixels)
    {
        EnsureSource(source);
        var r = Intersect(pixelRect, new Int32Rect(0, 0, source.PixelWidth, source.PixelHeight));
        if (r.Width < 1 || r.Height < 1) return null;
        var block = Math.Max(2, (int)Math.Round(blockPixels));
        var key = $"{mode}|{block}|{r.X},{r.Y},{r.Width},{r.Height}";
        if (_cache.TryGetValue(key, out var cached)) return cached;
        if (_cache.Count > 256) _cache.Clear();

        var pixels = mode == Annotations.RedactMode.Pixelate
            ? Pixelate(_sourcePixels!, _sourceStride, source.PixelWidth, source.PixelHeight, r, block)
            : Blur(_sourcePixels!, _sourceStride, source.PixelWidth, source.PixelHeight, r, (int)Math.Round(block * 1.5));
        var bmp = BitmapSource.Create(r.Width, r.Height, 96, 96, PixelFormats.Bgr32, null, pixels, r.Width * 4);
        bmp.Freeze();
        var patch = new Patch(bmp, r);
        _cache[key] = patch;
        return patch;
    }

    public static Int32Rect Intersect(Int32Rect a, Int32Rect b)
    {
        var x0 = Math.Max(a.X, b.X);
        var y0 = Math.Max(a.Y, b.Y);
        var x1 = Math.Min(a.X + a.Width, b.X + b.Width);
        var y1 = Math.Min(a.Y + a.Height, b.Y + b.Height);
        return x1 <= x0 || y1 <= y0 ? Int32Rect.Empty : new Int32Rect(x0, y0, x1 - x0, y1 - y0);
    }

    /// <summary>Block average with the grid anchored at (0,0) of the source image.</summary>
    internal static byte[] Pixelate(byte[] src, int stride, int width, int height, Int32Rect r, int block)
    {
        var outStride = r.Width * 4;
        var dst = new byte[outStride * r.Height];
        var bx0 = FloorDiv(r.X, block);
        var by0 = FloorDiv(r.Y, block);
        var bx1 = FloorDiv(r.X + r.Width - 1, block);
        var by1 = FloorDiv(r.Y + r.Height - 1, block);
        for (var by = by0; by <= by1; by++)
        {
            for (var bx = bx0; bx <= bx1; bx++)
            {
                // Average the whole block (clamped to the image), then paint the part inside r.
                var x0 = Math.Max(bx * block, 0);
                var y0 = Math.Max(by * block, 0);
                var x1 = Math.Min((bx + 1) * block, width);
                var y1 = Math.Min((by + 1) * block, height);
                long sb = 0, sg = 0, sr = 0, n = 0;
                for (var y = y0; y < y1; y++)
                {
                    var row = y * stride;
                    for (var x = x0; x < x1; x++)
                    {
                        var i = row + x * 4;
                        sb += src[i]; sg += src[i + 1]; sr += src[i + 2]; n++;
                    }
                }
                if (n == 0) continue;
                var b = (byte)(sb / n);
                var g = (byte)(sg / n);
                var rr = (byte)(sr / n);
                var px0 = Math.Max(x0, r.X);
                var py0 = Math.Max(y0, r.Y);
                var px1 = Math.Min(x1, r.X + r.Width);
                var py1 = Math.Min(y1, r.Y + r.Height);
                for (var y = py0; y < py1; y++)
                {
                    var row = (y - r.Y) * outStride;
                    for (var x = px0; x < px1; x++)
                    {
                        var i = row + (x - r.X) * 4;
                        dst[i] = b; dst[i + 1] = g; dst[i + 2] = rr; dst[i + 3] = 255;
                    }
                }
            }
        }
        return dst;
    }

    /// <summary>Three-pass box blur (≈ Gaussian) sampling from the full image so edges have no seams.</summary>
    internal static byte[] Blur(byte[] src, int stride, int width, int height, Int32Rect r, int radius)
    {
        radius = Math.Max(1, radius);
        var pad = radius * 3;
        var x0 = Math.Max(0, r.X - pad);
        var y0 = Math.Max(0, r.Y - pad);
        var x1 = Math.Min(width, r.X + r.Width + pad);
        var y1 = Math.Min(height, r.Y + r.Height + pad);
        var w = x1 - x0;
        var h = y1 - y0;

        var a = new float[w * h * 3];
        for (var y = 0; y < h; y++)
        {
            var row = (y + y0) * stride;
            for (var x = 0; x < w; x++)
            {
                var i = row + (x + x0) * 4;
                var o = (y * w + x) * 3;
                a[o] = src[i]; a[o + 1] = src[i + 1]; a[o + 2] = src[i + 2];
            }
        }
        var b = new float[a.Length];
        for (var pass = 0; pass < 3; pass++)
        {
            BoxBlurH(a, b, w, h, radius);
            BoxBlurV(b, a, w, h, radius);
        }

        var outStride = r.Width * 4;
        var dst = new byte[outStride * r.Height];
        for (var y = 0; y < r.Height; y++)
        {
            for (var x = 0; x < r.Width; x++)
            {
                var o = ((y + r.Y - y0) * w + (x + r.X - x0)) * 3;
                var i = y * outStride + x * 4;
                dst[i] = (byte)Math.Clamp(a[o], 0, 255);
                dst[i + 1] = (byte)Math.Clamp(a[o + 1], 0, 255);
                dst[i + 2] = (byte)Math.Clamp(a[o + 2], 0, 255);
                dst[i + 3] = 255;
            }
        }
        return dst;
    }

    private static void BoxBlurH(float[] src, float[] dst, int w, int h, int r)
    {
        var norm = 1f / (2 * r + 1);
        for (var y = 0; y < h; y++)
        {
            var row = y * w;
            for (var c = 0; c < 3; c++)
            {
                float sum = 0;
                for (var x = -r; x <= r; x++) sum += src[(row + Math.Clamp(x, 0, w - 1)) * 3 + c];
                for (var x = 0; x < w; x++)
                {
                    dst[(row + x) * 3 + c] = sum * norm;
                    var addX = Math.Clamp(x + r + 1, 0, w - 1);
                    var subX = Math.Clamp(x - r, 0, w - 1);
                    sum += src[(row + addX) * 3 + c] - src[(row + subX) * 3 + c];
                }
            }
        }
    }

    private static void BoxBlurV(float[] src, float[] dst, int w, int h, int r)
    {
        var norm = 1f / (2 * r + 1);
        for (var x = 0; x < w; x++)
        {
            for (var c = 0; c < 3; c++)
            {
                float sum = 0;
                for (var y = -r; y <= r; y++) sum += src[(Math.Clamp(y, 0, h - 1) * w + x) * 3 + c];
                for (var y = 0; y < h; y++)
                {
                    dst[(y * w + x) * 3 + c] = sum * norm;
                    var addY = Math.Clamp(y + r + 1, 0, h - 1);
                    var subY = Math.Clamp(y - r, 0, h - 1);
                    sum += src[(addY * w + x) * 3 + c] - src[(subY * w + x) * 3 + c];
                }
            }
        }
    }

    private static int FloorDiv(int a, int b) => (int)Math.Floor(a / (double)b);
}
