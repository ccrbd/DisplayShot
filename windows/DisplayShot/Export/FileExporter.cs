using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace DisplayShot.Export;

public static class FileExporter
{
    public static string DefaultFilename(DateTime? now = null)
    {
        var t = now ?? DateTime.Now;
        return $"DisplayShot {t:yyyy-MM-dd} at {t:HH.mm.ss}.png";
    }

    /// <summary>Writes a PNG into <paramref name="directory"/> with a timestamped, collision-free name.</summary>
    public static string SaveSilently(BitmapSource image, string directory)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, DefaultFilename());
        var n = 2;
        while (File.Exists(path))
        {
            path = Path.Combine(directory, DefaultFilename().Replace(".png", $" ({n}).png"));
            n++;
        }
        File.WriteAllBytes(path, ImageComposer.EncodePng(image));
        return path;
    }

    /// <summary>Shows a save dialog. Returns the path, or null if cancelled.</summary>
    public static string? SaveWithDialog(BitmapSource image, string initialDirectory, Window? owner)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "PNG image (*.png)|*.png",
            DefaultExt = ".png",
            AddExtension = true,
            FileName = DefaultFilename(),
            InitialDirectory = Directory.Exists(initialDirectory) ? initialDirectory : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Title = "Save screenshot",
        };
        var ok = owner is null ? dialog.ShowDialog() : dialog.ShowDialog(owner);
        if (ok != true) return null;
        File.WriteAllBytes(dialog.FileName, ImageComposer.EncodePng(image));
        return dialog.FileName;
    }
}
