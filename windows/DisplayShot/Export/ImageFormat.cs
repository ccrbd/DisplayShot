namespace DisplayShot.Export;

public enum ImageFormat { Jpeg, Png, Tiff }

public static class ImageFormatExtensions
{
    public static IReadOnlyList<ImageFormat> All { get; } = Enum.GetValues<ImageFormat>();

    public static string Title(this ImageFormat f) => f switch
    {
        ImageFormat.Jpeg => "JPEG",
        ImageFormat.Png => "PNG",
        ImageFormat.Tiff => "TIFF",
        _ => f.ToString(),
    };

    public static string Extension(this ImageFormat f) => f switch
    {
        ImageFormat.Jpeg => "jpg",
        ImageFormat.Png => "png",
        ImageFormat.Tiff => "tiff",
        _ => "png",
    };

    public static ImageFormat? FromPath(string path) => System.IO.Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" => ImageFormat.Jpeg,
        ".png" => ImageFormat.Png,
        ".tif" or ".tiff" => ImageFormat.Tiff,
        _ => null,
    };

    /// <summary>SaveFileDialog filter string with one entry per format, in <see cref="All"/> order.</summary>
    public static string DialogFilter =>
        string.Join("|", All.Select(f => $"{f.Title()} image (*.{f.Extension()})|*.{f.Extension()}"));
}
