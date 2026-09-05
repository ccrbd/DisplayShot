using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DisplayShot.Annotations;

namespace DisplayShot.Export;

/// <summary>Produces the final image: cropped source, redactions burned in, annotations drawn
/// with the same renderer the overlay uses, markers composited with a real multiply blend.</summary>
public static class ImageComposer
{
    public static BitmapSource? Compose(BitmapSource source, Rect selection, IReadOnlyList<Annotation> annotations, Redactor redactor)
    {
        var bounds = new Int32Rect(0, 0, source.PixelWidth, source.PixelHeight);
        var sel = Redactor.Intersect(ToInt32Rect(selection), bounds);
        if (sel.Width < 1 || sel.Height < 1) return null;

        // 1. Base pixels (BGRA) from the crop.
        var stride = sel.Width * 4;
        var pixels = new byte[stride * sel.Height];
        var crop = new CroppedBitmap(source, sel);
        var converted = new FormatConvertedBitmap(crop, PixelFormats.Bgra32, null, 0);
        converted.CopyPixels(pixels, stride, 0);
        for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;

        // 2. Redactions.
        foreach (var a in annotations)
        {
            if (a is not RedactAnnotation redact) continue;
            var patch = redactor.GetPatch(source, ToInt32Rect(redact.Rect), redact.Mode, redact.Block);
            if (patch is null) continue;
            var patchStride = patch.PixelRect.Width * 4;
            var patchPixels = new byte[patchStride * patch.PixelRect.Height];
            patch.Image.CopyPixels(patchPixels, patchStride, 0);
            var overlap = Redactor.Intersect(patch.PixelRect, sel);
            for (var y = overlap.Y; y < overlap.Y + overlap.Height; y++)
            {
                var srcRow = (y - patch.PixelRect.Y) * patchStride;
                var dstRow = (y - sel.Y) * stride;
                for (var x = overlap.X; x < overlap.X + overlap.Width; x++)
                {
                    var si = srcRow + (x - patch.PixelRect.X) * 4;
                    var di = dstRow + (x - sel.X) * 4;
                    pixels[di] = patchPixels[si];
                    pixels[di + 1] = patchPixels[si + 1];
                    pixels[di + 2] = patchPixels[si + 2];
                    pixels[di + 3] = 255;
                }
            }
        }

        // 3. Markers: render opaque, then multiply onto the base at MarkerAlpha.
        if (annotations.Any(a => a.IsMarker))
        {
            var markerPixels = Render(sel, dc => AnnotationRenderer.DrawMarkersOpaque(dc, annotations));
            var alpha = AnnotationRenderer.MarkerAlpha;
            for (var i = 0; i < pixels.Length; i += 4)
            {
                var ma = markerPixels[i + 3] / 255.0;
                if (ma <= 0) continue;
                var k = ma * alpha;
                for (var c = 0; c < 3; c++)
                {
                    // Pbgra32 is premultiplied; un-premultiply the marker colour.
                    var m = markerPixels[i + c] / Math.Max(ma, 1e-6) / 255.0;
                    var b = pixels[i + c] / 255.0;
                    pixels[i + c] = (byte)Math.Clamp(Math.Round(255 * (b * (1 - k) + b * m * k)), 0, 255);
                }
            }
        }

        // 4. Everything else drawn on top.
        var baseBitmap = BitmapSource.Create(sel.Width, sel.Height, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        baseBitmap.Freeze();
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.NearestNeighbor);
        using (var dc = visual.RenderOpen())
        {
            dc.DrawImage(baseBitmap, new Rect(0, 0, sel.Width, sel.Height));
            dc.PushTransform(new TranslateTransform(-sel.X, -sel.Y));
            AnnotationRenderer.Draw(dc, annotations, new Rect(sel.X, sel.Y, sel.Width, sel.Height), includeMarkers: false);
            dc.Pop();
        }
        var target = new RenderTargetBitmap(sel.Width, sel.Height, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        target.Freeze();
        return target;
    }

    /// <summary>Renders drawing commands (in canvas coordinates) into a Pbgra32 byte buffer the size of <paramref name="sel"/>.</summary>
    private static byte[] Render(Int32Rect sel, Action<DrawingContext> draw)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.PushTransform(new TranslateTransform(-sel.X, -sel.Y));
            draw(dc);
            dc.Pop();
        }
        var target = new RenderTargetBitmap(sel.Width, sel.Height, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        var stride = sel.Width * 4;
        var pixels = new byte[stride * sel.Height];
        target.CopyPixels(pixels, stride, 0);
        return pixels;
    }

    public static Int32Rect ToInt32Rect(Rect r)
    {
        var x0 = (int)Math.Floor(r.Left);
        var y0 = (int)Math.Floor(r.Top);
        var x1 = (int)Math.Ceiling(r.Right);
        var y1 = (int)Math.Ceiling(r.Bottom);
        return new Int32Rect(x0, y0, Math.Max(0, x1 - x0), Math.Max(0, y1 - y0));
    }

    public static byte[] EncodePng(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }
}
