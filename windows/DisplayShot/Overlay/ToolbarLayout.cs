using System.Windows;

namespace DisplayShot.Overlay;

/// <summary>Pure placement math for the palette, action bar and dimension label.
/// Nothing is ever placed outside <c>screen</c>; nothing overlaps.</summary>
public static class ToolbarLayout
{
    public const double Gap = 8;

    public readonly record struct Result(Rect Palette, Rect ActionBar, Rect Label);

    public static Result Place(Rect selection, Rect screen, Size paletteSize, Size barSize, Size labelSize)
    {
        // Palette: right of the selection → left of it → inside its top-right corner.
        var py = SelectionModel.Clamp(selection.Top, screen.Top, Math.Max(screen.Top, screen.Bottom - paletteSize.Height));
        Rect palette;
        if (selection.Right + Gap + paletteSize.Width <= screen.Right)
            palette = new Rect(new Point(selection.Right + Gap, py), paletteSize);
        else if (selection.Left - Gap - paletteSize.Width >= screen.Left)
            palette = new Rect(new Point(selection.Left - Gap - paletteSize.Width, py), paletteSize);
        else
            palette = new Rect(new Point(selection.Right - Gap - paletteSize.Width, selection.Top + Gap), paletteSize);
        palette = SelectionModel.Fit(palette, screen);

        // Action bar: below → above → beside the palette → inside.
        var bx = SelectionModel.Clamp(selection.Right - barSize.Width, screen.Left, Math.Max(screen.Left, screen.Right - barSize.Width));
        double w = barSize.Width, h = barSize.Height;
        var barCandidates = new[]
        {
            new Point(bx, selection.Bottom + Gap),
            new Point(bx, selection.Top - Gap - h),
            new Point(palette.Left - Gap - w, selection.Bottom + Gap),
            new Point(palette.Left - Gap - w, selection.Top - Gap - h),
            new Point(palette.Right + Gap, selection.Bottom + Gap),
            new Point(palette.Right + Gap, selection.Top - Gap - h),
            new Point(selection.Right - Gap - w, selection.Bottom - Gap - h),
            new Point(selection.Left + Gap, selection.Bottom - Gap - h),
            new Point(palette.Right + Gap, palette.Bottom - h),
            new Point(palette.Left - Gap - w, palette.Bottom - h),
        }.Select(p => new Rect(p, barSize)).ToArray();
        var bar = SelectionModel.Fit(barCandidates[6], screen);
        var free = barCandidates.FirstOrDefault(c => screen.Contains(c) && !c.IntersectsWith(palette), Rect.Empty);
        if (!free.IsEmpty) bar = free;
        else
        {
            var fitted = barCandidates.Select(c => SelectionModel.Fit(c, screen)).FirstOrDefault(c => !c.IntersectsWith(palette), Rect.Empty);
            if (!fitted.IsEmpty) bar = fitted;
        }

        // Label: first candidate on-screen that overlaps nothing.
        var g = Gap / 2;
        var labelCandidates = new[]
        {
            new Point(selection.Left, selection.Top - g - labelSize.Height),
            new Point(selection.Left + 4, selection.Top + 4),
            new Point(selection.Left, selection.Bottom + g),
            new Point(selection.Left - g - labelSize.Width, selection.Top),
            new Point(selection.Right + g, selection.Top),
            new Point(palette.Left - g - labelSize.Width, selection.Top),
            new Point(palette.Right + g, selection.Top),
            new Point(bar.Left, bar.Bottom + g),
            new Point(bar.Left, bar.Top - g - labelSize.Height),
        }.Select(p => new Rect(p, labelSize)).ToArray();
        var label = SelectionModel.Fit(labelCandidates[1], screen);
        var freeLabel = labelCandidates.FirstOrDefault(c => screen.Contains(c) && !c.IntersectsWith(bar) && !c.IntersectsWith(palette), Rect.Empty);
        if (!freeLabel.IsEmpty) label = freeLabel;

        return new Result(palette, bar, label);
    }
}
