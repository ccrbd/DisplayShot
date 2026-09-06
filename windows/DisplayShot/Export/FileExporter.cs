using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace DisplayShot.Export;

public static class FileExporter
{
    public static string DefaultFilename(DateTime? now = null, ImageFormat format = ImageFormat.Png)
    {
        var t = now ?? DateTime.Now;
        return $"DisplayShot {t:yyyy-MM-dd} at {t:HH.mm.ss}.{format.Extension()}";
    }

    /// <summary>Writes the image into <paramref name="directory"/> with a timestamped, collision-free name.</summary>
    public static string SaveSilently(BitmapSource image, string directory, ImageFormat format)
    {
        Directory.CreateDirectory(directory);
        var name = DefaultFilename(format: format);
        var path = Path.Combine(directory, name);
        var n = 2;
        while (File.Exists(path))
        {
            path = Path.Combine(directory, name.Replace($".{format.Extension()}", $" ({n}).{format.Extension()}"));
            n++;
        }
        File.WriteAllBytes(path, ImageComposer.Encode(image, format));
        return path;
    }

    /// <summary>Shows a save dialog with a format chooser. Returns the path and format, or null if cancelled.</summary>
    public static (string Path, ImageFormat Format)? SaveWithDialog(BitmapSource image, string initialDirectory, ImageFormat format, Window? owner)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = ImageFormatExtensions.DialogFilter,
            FilterIndex = ImageFormatExtensions.All.ToList().IndexOf(format) + 1,
            AddExtension = true,
            FileName = Path.GetFileNameWithoutExtension(DefaultFilename(format: format)),
            InitialDirectory = Directory.Exists(initialDirectory) ? initialDirectory : Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Title = "Save screenshot",
        };
        var ok = owner is null ? dialog.ShowDialog() : dialog.ShowDialog(owner);
        if (ok != true) return null;
        var chosen = ImageFormatExtensions.FromPath(dialog.FileName)
                     ?? ImageFormatExtensions.All[Math.Clamp(dialog.FilterIndex - 1, 0, ImageFormatExtensions.All.Count - 1)];
        var path = ImageFormatExtensions.FromPath(dialog.FileName) is null ? dialog.FileName + "." + chosen.Extension() : dialog.FileName;
        File.WriteAllBytes(path, ImageComposer.Encode(image, chosen));
        return (path, chosen);
    }
}
