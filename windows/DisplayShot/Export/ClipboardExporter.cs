using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;

namespace DisplayShot.Export;

public static class ClipboardExporter
{
    /// <summary>Puts PNG + bitmap formats on the clipboard. Retries because other apps
    /// (clipboard managers, browsers) briefly hold the clipboard open.</summary>
    public static void Copy(BitmapSource image)
    {
        var png = ImageComposer.EncodePng(image);
        Exception? last = null;
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                var data = new DataObject();
                data.SetData("PNG", new MemoryStream(png), autoConvert: false);
                data.SetImage(image);
                Clipboard.SetDataObject(data, copy: true);
                return;
            }
            catch (COMException ex)
            {
                last = ex;
                Thread.Sleep(50);
            }
            catch (ExternalException ex)
            {
                last = ex;
                Thread.Sleep(50);
            }
        }
        throw new InvalidOperationException("The clipboard is busy. Please try again.", last);
    }
}
