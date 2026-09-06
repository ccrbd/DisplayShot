using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using DisplayShot.Annotations;
using DisplayShot.Capture;
using DisplayShot.Configuration;
using DisplayShot.Export;

namespace DisplayShot.Overlay;

/// <summary>Owns one capture: the frozen image, the single overlay window, the selection, the
/// annotation list and every interaction rule (mouse, keyboard, wheel, Esc cascade, export).</summary>
public sealed class OverlaySession
{
    private enum Phase { Idle, Selecting, Selected, Resizing, Moving, Drawing, MovingEmoji, Erasing }

    public VirtualScreenCapture Capture { get; }
    public AnnotationStore Store { get; } = new();
    public Redactor Redactor { get; } = new();
    public SelectionModel? Selection { get; private set; }
    public Annotation? InProgress { get; private set; }
    public Point LabelOrigin { get; private set; }

    public event EventHandler? Finished;

    private readonly Settings _settings;
    private readonly Rect _bounds;
    private OverlayWindow? _window;
    private Canvas? _host;
    private OverlayCanvas? _canvas;
    private Phase _phase = Phase.Idle;
    private ToolKind? _tool;
    private Color _color;
    private int? _colorIndex;
    private readonly Dictionary<ToolKind, double> _widths = new();

    private Point _dragOrigin;
    private Point _grabOffset;
    private Point _lastPoint;
    private Handle _activeHandle;
    private bool _finished;
    private RedactMode _redactMode;
    private string _currentEmoji;
    private Guid? _lastEmojiId;
    private Guid _movingEmojiId;
    private Border? _emojiStrip;
    private TextBox? _emojiReceiver;
    private bool IsEmojiPicking => _emojiReceiver is not null;
    private bool _emojiPickerVisible;
    private Button? _emojiToolButton;

    /// <summary>Eraser circle to draw under the cursor, when the eraser is active over the selection.</summary>
    public (Point Center, double Radius)? EraserFootprint =>
        _tool == ToolKind.Eraser && ShowsChrome && Selection is { } s && s.Rect.Contains(_lastPoint)
            ? (_lastPoint, WidthFor(ToolKind.Eraser) / 2)
            : null;

    // Chrome
    private Border? _palette;
    private Border? _actionBar;
    private Border? _colorStrip;
    private Border? _widthBadge;
    private TextBox? _textBox;
    private Point _textOrigin;
    private bool _colorStripVisible;
    private readonly List<(ToolKind Tool, Border Highlight)> _toolHighlights = new();
    private DispatcherTimer? _badgeTimer;

    public OverlaySession(VirtualScreenCapture capture, Settings settings)
    {
        Capture = capture;
        _settings = settings;
        _bounds = new Rect(0, 0, capture.Bounds.Width, capture.Bounds.Height);
        foreach (var tool in ToolKindExtensions.All) _widths[tool] = settings.WidthFor(tool);
        _colorIndex = settings.LastColorIndex >= 0 && settings.LastColorIndex < OverlayChrome.Palette.Length ? settings.LastColorIndex : 0;
        _color = OverlayChrome.Palette[_colorIndex ?? 0];
        _redactMode = settings.RedactMode;
        _currentEmoji = string.IsNullOrEmpty(settings.LastEmoji) ? "👍" : settings.LastEmoji;
    }

    public bool ShowsChrome => Selection is not null && _phase is Phase.Selected or Phase.Drawing;
    public bool ShowsHandles => Selection is not null && _phase != Phase.Selecting;
    private bool IsTextEditing => _textBox is not null;
    private double WidthFor(ToolKind tool) => _widths.TryGetValue(tool, out var w) ? w : tool.DefaultWidth();
    private double MonitorScaleAt(Point p) => Capture.MonitorAt(p).DpiScale;

    // MARK: Lifecycle

    public void Start()
    {
        _window = new OverlayWindow();
        _host = _window.Host;
        _canvas = new OverlayCanvas(this)
        {
            Width = _bounds.Width,
            Height = _bounds.Height,
        };
        _host.Children.Add(_canvas);

        _window.PositionOverVirtualScreen(Capture.Bounds.X, Capture.Bounds.Y, Capture.Bounds.Width, Capture.Bounds.Height);
        _window.MouseDown += OnMouseDown;
        _window.MouseMove += OnMouseMove;
        _window.MouseUp += OnMouseUp;
        _window.MouseWheel += OnMouseWheel;
        _window.KeyDown += OnKeyDown;
        _window.PreviewKeyDown += OnPreviewKeyDown;
        _window.Show();
        _window.Activate();
        Invalidate();
    }

    private void Dismiss()
    {
        if (_finished) return;
        _finished = true;
        RemoveTextBox();
        RemoveEmojiReceiver();
        _window?.Close();
        _window = null;
        Finished?.Invoke(this, EventArgs.Empty);
    }

    public void Cancel() => Dismiss();

    private void Invalidate()
    {
        _canvas?.InvalidateVisual();
        RefreshChrome();
    }

    private Point CanvasPoint(MouseEventArgs e) => e.GetPosition(_canvas);
    private Point CanvasPoint(RoutedEventArgs _) => _lastPoint;

    // MARK: Mouse

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        var p = CanvasPoint(e);
        _lastPoint = p;
        if (IsTextEditing) { CommitText(); return; }
        if (IsEmojiPicking) RemoveEmojiReceiver();
        _colorStripVisible = false;
        _emojiPickerVisible = false;

        if (Selection is { } sel)
        {
            switch (sel.HitTest(p))
            {
                case SelectionHit.HandleHit hh:
                    _phase = Phase.Resizing;
                    _activeHandle = hh.Handle;
                    break;
                case SelectionHit.Inside:
                    if (_tool is { } tool)
                    {
                        if (tool == ToolKind.Text) BeginText(p);
                        else if (tool == ToolKind.Eraser) { Store.BeginGroup(); _phase = Phase.Erasing; EraseAt(p); }
                        else if (tool == ToolKind.Emoji)
                        {
                            if (EmojiHit(p) is { } hit)
                            {
                                _lastEmojiId = hit.Id;
                                _movingEmojiId = hit.Id;
                                _grabOffset = new Point(p.X - hit.Center.X, p.Y - hit.Center.Y);
                                _phase = Phase.MovingEmoji;
                            }
                            else StampEmoji(p);
                        }
                        else StartDrawing(tool, ClampToSelection(p));
                    }
                    else
                    {
                        _phase = Phase.Moving;
                        _grabOffset = new Point(p.X - sel.Rect.X, p.Y - sel.Rect.Y);
                    }
                    break;
                default:
                    BeginSelection(p);
                    break;
            }
        }
        else
        {
            BeginSelection(p);
        }
        _window?.CaptureMouse();
        Invalidate();
    }

    private void BeginSelection(Point p)
    {
        Store.Clear();
        Redactor.ClearCache();
        Selection = null;
        InProgress = null;
        _dragOrigin = p;
        _phase = Phase.Selecting;
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        var p = CanvasPoint(e);
        _lastPoint = p;
        ApplyDrag(p, e.KeyboardShiftDown());
        UpdateCursor(p);
        if (_phase is Phase.Selecting or Phase.Resizing or Phase.Moving or Phase.Drawing or Phase.MovingEmoji or Phase.Erasing || _tool == ToolKind.Eraser) Invalidate();
    }

    private void ApplyDrag(Point p, bool shift)
    {
        switch (_phase)
        {
            case Phase.Selecting:
                Selection = new SelectionModel(SelectionModel.RectFromDrag(_dragOrigin, p, shift, _bounds), _bounds);
                break;
            case Phase.Resizing when Selection is { } sel:
                _activeHandle = sel.Resize(_activeHandle, p, shift);
                break;
            case Phase.Moving when Selection is { } sel:
                sel.MoveTo(new Point(p.X - _grabOffset.X, p.Y - _grabOffset.Y));
                break;
            case Phase.Drawing when InProgress is { } ip && Selection is { } s:
                var updated = DrawingTools.Update(ip, _dragOrigin, ClampToSelection(p), shift);
                if (updated is RedactAnnotation ru) updated = ru with { Mode = shift ? RedactMode.Blur : _redactMode };
                InProgress = updated;
                break;
            case Phase.Erasing:
                EraseAt(p);
                break;
            case Phase.MovingEmoji when Store.Item(_movingEmojiId) is EmojiAnnotation e:
                Store.Replace(e.Id, e with { Center = ClampToSelection(new Point(p.X - _grabOffset.X, p.Y - _grabOffset.Y)) });
                break;
        }
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        _window?.ReleaseMouseCapture();
        switch (_phase)
        {
            case Phase.Selecting:
                if (Selection is { } sel && sel.Rect.Width >= 3 && sel.Rect.Height >= 3) _phase = Phase.Selected;
                else { Selection = null; _phase = Phase.Idle; }
                break;
            case Phase.Resizing:
            case Phase.Moving:
            case Phase.MovingEmoji:
                _phase = Phase.Selected;
                break;
            case Phase.Erasing:
                Store.EndGroup();
                _phase = Phase.Selected;
                break;
            case Phase.Drawing:
                if (InProgress is { IsMeaningful: true } ip) Store.Add(ip);
                InProgress = null;
                _phase = Phase.Selected;
                break;
        }
        Invalidate();
    }

    private void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (_tool is not { } tool || Selection is null) return;
        var steps = e.Delta / 120;
        if (steps == 0) steps = e.Delta > 0 ? 1 : -1;
        if (tool == ToolKind.Emoji && Keyboard.Modifiers.HasFlag(ModifierKeys.Alt))
        {
            RotateLastEmoji(steps * 15);
            ShowWidthBadge("rotate", 0, _color, BadgeShape.None);
            return;
        }
        var (min, max) = tool.WidthRange();
        var w = SelectionModel.Clamp(WidthFor(tool) + steps, min, max);
        _widths[tool] = w;
        _settings.SetWidth(tool, w);
        _settings.Save();
        if (InProgress is { } ip) InProgress = ip.WithWidth(w);
        if (tool == ToolKind.Emoji) UpdateLastEmoji(em => em with { Size = w });
        if (IsTextEditing && tool == ToolKind.Text) ApplyTextStyle();
        var unit = tool is ToolKind.Text or ToolKind.Emoji ? "pt" : tool == ToolKind.Redact ? "block" : "px";
        var shape = tool is ToolKind.Text or ToolKind.Emoji ? BadgeShape.None : tool == ToolKind.Redact ? BadgeShape.Square : BadgeShape.Circle;
        var badgeColor = tool == ToolKind.Marker ? Color.FromArgb(128, _color.R, _color.G, _color.B)
            : tool is ToolKind.Eraser or ToolKind.Redact ? Color.FromRgb(0xD9, 0xD9, 0xD9) : _color;
        ShowWidthBadge($"{(int)w} {unit}", w, badgeColor, shape);
        Invalidate();
    }

    private Point ClampToSelection(Point p)
    {
        if (Selection is not { } sel) return p;
        return SelectionModel.ClampPoint(p, sel.Rect);
    }

    // MARK: Tools

    private void StartDrawing(ToolKind tool, Point p)
    {
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        var a = DrawingTools.Begin(tool, p, _color, WidthFor(tool), shift);
        if (a is null) return;
        if (a is RedactAnnotation ra) a = ra with { Mode = shift ? RedactMode.Blur : _redactMode };
        _dragOrigin = p;
        InProgress = a;
        _phase = Phase.Drawing;
    }

    private void SetRedactMode(RedactMode mode)
    {
        _redactMode = mode;
        _settings.RedactMode = mode;
        _settings.Save();
        if (_tool != ToolKind.Redact) _tool = ToolKind.Redact;
        Invalidate();
    }

    // MARK: Eraser

    private void EraseAt(Point p)
    {
        if (Selection is not { } sel) return;
        var q = SelectionModel.ClampPoint(p, sel.Rect);
        var r = WidthFor(ToolKind.Eraser) / 2;
        foreach (var a in Store.Items.Where(a => AnnotationHitTester.Hits(a, q, r)).ToList())
            Store.Remove(a.Id);
    }

    // MARK: Emoji tool

    private void ToggleEmojiPicker()
    {
        if (_tool != ToolKind.Emoji) _tool = ToolKind.Emoji;
        _emojiPickerVisible = !_emojiPickerVisible;
        _colorStripVisible = false;
        Invalidate();
    }

    private void SetEmoji(string emoji)
    {
        _currentEmoji = emoji;
        _settings.LastEmoji = emoji;
        _settings.Save();
        _emojiPickerVisible = false;
        if (_tool != ToolKind.Emoji) _tool = ToolKind.Emoji;
        Invalidate();
    }

    private void StampEmoji(Point p)
    {
        var a = new EmojiAnnotation(p, _currentEmoji, WidthFor(ToolKind.Emoji), 0, _color);
        Store.Add(a);
        _lastEmojiId = a.Id;
    }

    private EmojiAnnotation? EmojiHit(Point p)
    {
        for (var i = Store.Items.Count - 1; i >= 0; i--)
            if (Store.Items[i] is EmojiAnnotation e && e.Bounds.Contains(p)) return e;
        return null;
    }

    private void UpdateLastEmoji(Func<EmojiAnnotation, EmojiAnnotation> change)
    {
        if (_lastEmojiId is { } id && Store.Item(id) is EmojiAnnotation e) Store.Replace(id, change(e));
    }

    private void RotateLastEmoji(double degrees)
    {
        UpdateLastEmoji(e => e with { Rotation = e.Rotation + degrees });
        Invalidate();
    }

    /// <summary>"More…": an inline box that receives one emoji (press Win+. to open Windows' picker).</summary>
    private void BeginEmojiPick()
    {
        RemoveEmojiReceiver();
        if (_host is null) return;
        _emojiPickerVisible = false;
        _emojiReceiver = new TextBox
        {
            Width = 120,
            FontFamily = new FontFamily("Segoe UI Emoji"),
            FontSize = 16,
            Background = new SolidColorBrush(Color.FromArgb(240, 26, 26, 26)),
            Foreground = Brushes.White,
            CaretBrush = Brushes.White,
            BorderBrush = new SolidColorBrush(Color.FromArgb(166, 255, 255, 255)),
            Padding = new Thickness(4),
            ToolTip = "Type or paste an emoji (Win+. opens the emoji panel). Esc cancels.",
        };
        var anchor = _emojiStrip is { Visibility: Visibility.Visible } strip
            ? new Point(Canvas.GetLeft(strip), Canvas.GetTop(strip) + strip.ActualHeight + 6)
            : _lastPoint;
        Canvas.SetLeft(_emojiReceiver, anchor.X);
        Canvas.SetTop(_emojiReceiver, anchor.Y);
        _emojiReceiver.TextChanged += (_, _) =>
        {
            var text = _emojiReceiver?.Text ?? string.Empty;
            if (text.Length == 0) return;
            var first = System.Globalization.StringInfo.GetNextTextElement(text);
            RemoveEmojiReceiver();
            SetEmoji(first);
        };
        _emojiReceiver.PreviewKeyDown += (_, args) =>
        {
            if (args.Key == Key.Escape) { args.Handled = true; RemoveEmojiReceiver(); Invalidate(); }
        };
        _host.Children.Add(_emojiReceiver);
        _emojiReceiver.Focus();
    }

    private void RemoveEmojiReceiver()
    {
        if (_emojiReceiver is null) return;
        _host?.Children.Remove(_emojiReceiver);
        _emojiReceiver = null;
    }

    private void SelectTool(ToolKind? tool)
    {
        if (IsTextEditing) CommitText();
        if (IsEmojiPicking) RemoveEmojiReceiver();
        if (_phase == Phase.Drawing) { InProgress = null; _phase = Phase.Selected; }
        _tool = _tool == tool ? null : tool;
        Invalidate();
    }

    private void SetColor(int index)
    {
        if (index < 0 || index >= OverlayChrome.Palette.Length) return;
        _colorIndex = index;
        _color = OverlayChrome.Palette[index];
        _settings.LastColorIndex = index;
        _settings.Save();
        _colorStripVisible = false;
        if (IsTextEditing) ApplyTextStyle();
        Invalidate();
    }

    private void Undo() { if (!IsTextEditing) { Store.Undo(); Invalidate(); } }
    private void Redo() { if (!IsTextEditing) { Store.Redo(); Invalidate(); } }

    // MARK: Text

    private void BeginText(Point p)
    {
        RemoveTextBox();
        _textOrigin = p;
        var scale = MonitorScaleAt(p);
        _textBox = new TextBox
        {
            Background = Brushes.Transparent,
            BorderBrush = new SolidColorBrush(Color.FromArgb(166, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            Foreground = new SolidColorBrush(_color),
            CaretBrush = new SolidColorBrush(_color),
            FontFamily = new FontFamily("Segoe UI"),
            FontWeight = FontWeights.SemiBold,
            FontSize = WidthFor(ToolKind.Text),
            MinWidth = 40,
            AcceptsReturn = true,
            Padding = new Thickness(1),
            SnapsToDevicePixels = true,
        };
        Canvas.SetLeft(_textBox, p.X);
        Canvas.SetTop(_textBox, p.Y);
        _textBox.PreviewKeyDown += TextBoxKeyDown;
        _host!.Children.Add(_textBox);
        _textBox.Focus();
        Invalidate();
    }

    private void ApplyTextStyle()
    {
        if (_textBox is null) return;
        _textBox.Foreground = new SolidColorBrush(_color);
        _textBox.CaretBrush = new SolidColorBrush(_color);
        _textBox.FontSize = WidthFor(ToolKind.Text);
    }

    private void TextBoxKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape) { e.Handled = true; CancelText(); }
        else if (e.Key == Key.Return && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { e.Handled = true; CommitText(); }
    }

    private void CommitText()
    {
        if (_textBox is null) return;
        var text = _textBox.Text.Trim('\r', '\n');
        var origin = new Point(Canvas.GetLeft(_textBox), Canvas.GetTop(_textBox));
        RemoveTextBox();
        if (!string.IsNullOrWhiteSpace(text))
            Store.Add(new TextAnnotation(origin, text, _color, WidthFor(ToolKind.Text)));
        Invalidate();
    }

    private void CancelText()
    {
        RemoveTextBox();
        Invalidate();
    }

    private void RemoveTextBox()
    {
        if (_textBox is null) return;
        _textBox.PreviewKeyDown -= TextBoxKeyDown;
        _host?.Children.Remove(_textBox);
        _textBox = null;
    }

    // MARK: Keyboard

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (IsTextEditing || IsEmojiPicking) return; // those boxes handle their own keys
        if (e.Key == Key.Escape) { e.Handled = true; Escape(); return; }
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        if (ctrl)
        {
            switch (e.Key)
            {
                case Key.A: e.Handled = true; SelectAll(); return;
                case Key.C: e.Handled = true; CopyToClipboard(); return;
                case Key.S: e.Handled = true; Save(); return;
                case Key.Z: e.Handled = true; if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) Redo(); else Undo(); return;
            }
        }
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (IsTextEditing || IsEmojiPicking) return;
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        var alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);

        if (e.Key is Key.Enter or Key.Return && !ctrl) { e.Handled = true; CopyToClipboard(); return; }

        if (e.Key is Key.Left or Key.Right or Key.Up or Key.Down)
        {
            if (Selection is not { } sel) { e.Handled = true; return; }
            var step = shift ? 10 : 1;
            double dx = 0, dy = 0;
            switch (e.Key)
            {
                case Key.Left: dx = -step; break;
                case Key.Right: dx = step; break;
                case Key.Up: dy = -step; break;
                case Key.Down: dy = step; break;
            }
            if (alt) sel.Grow(dx, dy); else sel.Nudge(dx, dy);
            e.Handled = true;
            Invalidate();
            return;
        }

        if (ctrl) return; // handled in preview

        if (Selection is null) return;
        var ch = char.ToUpperInvariant(KeyToChar(e.Key));
        var tool = ToolKindExtensions.All.FirstOrDefault(t => t.Key() == ch, (ToolKind)(-1));
        if ((int)tool != -1) { e.Handled = true; SelectTool(tool); return; }
        if (ch == 'V') { e.Handled = true; SelectTool(null); return; }
        if (_tool == ToolKind.Emoji && e.Key is Key.OemOpenBrackets or Key.OemCloseBrackets)
        {
            e.Handled = true;
            RotateLastEmoji(e.Key == Key.OemOpenBrackets ? -15 : 15);
            return;
        }
        if (ch is >= '1' and <= '9')
        {
            var idx = ch - '1';
            if (idx < OverlayChrome.Palette.Length) { e.Handled = true; SetColor(idx); }
        }
    }

    private static char KeyToChar(Key key) => key switch
    {
        >= Key.A and <= Key.Z => (char)('A' + (key - Key.A)),
        >= Key.D0 and <= Key.D9 => (char)('0' + (key - Key.D0)),
        >= Key.NumPad0 and <= Key.NumPad9 => (char)('0' + (key - Key.NumPad0)),
        _ => '\0',
    };

    /// <summary>Esc cancels whatever is mid-edit (shape, text, emoji pick, colour strip); otherwise it closes the overlay.</summary>
    private void Escape()
    {
        if (IsTextEditing) { CancelText(); return; }
        if (IsEmojiPicking) { RemoveEmojiReceiver(); Invalidate(); return; }
        if (_phase == Phase.Drawing) { InProgress = null; _phase = Phase.Selected; Invalidate(); return; }
        if (_colorStripVisible) { _colorStripVisible = false; Invalidate(); return; }
        if (_emojiPickerVisible) { _emojiPickerVisible = false; Invalidate(); return; }
        Dismiss();
    }

    private void SelectAll()
    {
        Store.Clear();
        Redactor.ClearCache();
        // Full screen = the monitor under the cursor.
        var monitor = Capture.MonitorAt(_lastPoint);
        Selection = new SelectionModel(Capture.CanvasRect(monitor), _bounds);
        InProgress = null;
        _phase = Phase.Selected;
        Invalidate();
    }

    // MARK: Export

    private BitmapSource? ComposeImage()
    {
        if (IsTextEditing) CommitText();
        if (Selection is not { } sel) return null;
        return ImageComposer.Compose(Capture.Image, sel.Rect, Store.Items, Redactor);
    }

    private void Finish(string message)
    {
        if (_settings.PlaySound) System.Media.SystemSounds.Asterisk.Play();
        var monitor = Selection is { } s ? Capture.MonitorAt(new Point(s.Rect.X + s.Rect.Width / 2, s.Rect.Y + s.Rect.Height / 2)) : Capture.Monitors[0];
        var toast = new Toast(message, Capture, monitor);
        Dismiss();
        toast.ShowNear();
    }

    private void CopyToClipboard()
    {
        var image = ComposeImage();
        if (image is null) return;
        try { ClipboardExporter.Copy(image); }
        catch (Exception ex) { ShowError(ex.Message); return; }
        Finish($"Copied to clipboard · {image.PixelWidth} × {image.PixelHeight} px");
    }

    private void Save()
    {
        var image = ComposeImage();
        if (image is null) return;
        if (_settings.SaveWithoutAsking)
        {
            try
            {
                var path = FileExporter.SaveSilently(image, _settings.SaveDirectory, _settings.SaveFormat);
                Finish($"Saved to {System.IO.Path.GetFileName(path)}");
            }
            catch (Exception ex) { ShowError(ex.Message); }
            return;
        }
        _window!.Hide();
        try
        {
            var result = FileExporter.SaveWithDialog(image, _settings.SaveDirectory, _settings.SaveFormat, null);
            if (result is null) { _window.Show(); _window.Activate(); return; }
            var (path, format) = result.Value;
            _settings.SaveFormat = format;
            _settings.SaveDirectory = System.IO.Path.GetDirectoryName(path) ?? _settings.SaveDirectory;
            _settings.Save();
            Finish($"Saved to {System.IO.Path.GetFileName(path)}");
        }
        catch (Exception ex)
        {
            _window.Show();
            ShowError(ex.Message);
        }
    }

    private void ShowError(string message)
    {
        if (_host is null) return;
        var badge = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B)),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(14, 8, 14, 8),
            Child = new TextBlock { Text = message, Foreground = Brushes.White, FontSize = 13 },
        };
        var primary = Capture.CanvasRect(Capture.Monitors.FirstOrDefault(m => m.IsPrimary) ?? Capture.Monitors[0]);
        Canvas.SetLeft(badge, primary.X + primary.Width / 2 - 150);
        Canvas.SetTop(badge, primary.Y + 60);
        _host.Children.Add(badge);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.5) };
        timer.Tick += (_, _) => { timer.Stop(); _host.Children.Remove(badge); };
        timer.Start();
    }

    // MARK: Chrome

    private void RefreshChrome()
    {
        if (_host is null) return;
        EnsureChrome();
        var show = ShowsChrome && Selection is { } model;
        _palette!.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        _actionBar!.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        _colorStrip!.Visibility = show && _colorStripVisible ? Visibility.Visible : Visibility.Collapsed;
        _emojiStrip!.Visibility = show && _emojiPickerVisible ? Visibility.Visible : Visibility.Collapsed;
        if (!show) return;

        var sel = Selection!.Rect;
        var layout = ToolbarLayout.Place(sel, _bounds,
            new Size(_palette.DesiredSizeOr(38), _palette.DesiredSizeHeight(278)),
            new Size(_actionBar.DesiredSizeOr(150), _actionBar.DesiredSizeHeight(38)),
            new Size(70, 22));
        Place(_palette, layout.Palette);
        Place(_actionBar, layout.ActionBar);
        LabelOrigin = layout.Label.TopLeft;

        var stripW = _colorStrip.DesiredSizeOr(280);
        var stripX = layout.Palette.Left - ToolbarLayout.Gap - stripW;
        if (stripX < 0) stripX = layout.Palette.Right + ToolbarLayout.Gap;
        Place(_colorStrip, new Rect(stripX, layout.Palette.Top, stripW, ButtonHeight));

        var emojiW = _emojiStrip.DesiredSizeOr(300);
        var emojiH = _emojiStrip.DesiredSizeHeight(140);
        var emojiX = layout.Palette.Left - ToolbarLayout.Gap - emojiW;
        if (emojiX < 0) emojiX = layout.Palette.Right + ToolbarLayout.Gap;
        var emojiY = SelectionModel.Clamp(layout.Palette.Top, 0, Math.Max(0, _bounds.Height - emojiH));
        Place(_emojiStrip, new Rect(emojiX, emojiY, emojiW, emojiH));
        if (_emojiToolButton?.Content is TextBlock emojiLabel)
        {
            emojiLabel.Text = _currentEmoji;
            _emojiToolButton.ToolTip = $"Emoji {_currentEmoji} (E) — right-click to choose another";
        }

        foreach (var (tool, highlight) in _toolHighlights)
        {
            highlight.Background = _tool == tool ? OverlayChrome.Highlight : Brushes.Transparent;
            if (tool == ToolKind.Redact && highlight.Child is Button rb)
                rb.ToolTip = $"Redact: {_redactMode.Title()} (X) — right-click to change";
        }
        if (_emojiStrip.Child is WrapPanel emojiPanel)
            foreach (var child in emojiPanel.Children.OfType<Button>())
                child.Background = child.Tag as string == _currentEmoji ? OverlayChrome.Highlight : Brushes.Transparent;
        if (_colorButton is not null) _colorButton.Fill = new SolidColorBrush(_color);
        if (_undoButton is not null) _undoButton.Opacity = Store.CanUndo ? 1 : 0.35;
    }

    private const double ButtonHeight = 38;

    private Ellipse? _colorButton;
    private UIElement? _undoButton;

    private void EnsureChrome()
    {
        if (_palette is not null) return;

        // Tool palette (vertical): tools, colour swatch, undo.
        var toolStack = new StackPanel { Orientation = Orientation.Vertical };
        foreach (var tool in ToolKindExtensions.All)
        {
            var button = OverlayChrome.ToolButton(tool);
            if (tool == ToolKind.Emoji)
            {
                if (button.Content is TextBlock tb) { tb.Text = _currentEmoji; tb.FontFamily = new FontFamily("Segoe UI Emoji"); tb.FontSize = 15; }
                button.MouseRightButtonUp += (_, args) => { args.Handled = true; ToggleEmojiPicker(); };
                _emojiToolButton = button;
            }
            var highlight = new Border { CornerRadius = new CornerRadius(6), Child = button, Margin = new Thickness(0, 1, 0, 1) };
            button.Click += (_, _) => SelectTool(tool);
            if (tool == ToolKind.Redact)
            {
                var menu = new ContextMenu();
                foreach (var mode in Enum.GetValues<RedactMode>())
                {
                    var item = new MenuItem { Header = mode.Title(), IsCheckable = true, IsChecked = mode == _redactMode };
                    var chosen = mode;
                    item.Click += (_, _) => SetRedactMode(chosen);
                    menu.Items.Add(item);
                }
                menu.Opened += (_, _) =>
                {
                    var i = 0;
                    foreach (var mi in menu.Items.OfType<MenuItem>()) mi.IsChecked = Enum.GetValues<RedactMode>()[i++] == _redactMode;
                };
                button.ContextMenu = menu;
            }
            toolStack.Children.Add(highlight);
            _toolHighlights.Add((tool, highlight));
        }
        _colorButton = OverlayChrome.Swatch(_color, 20);
        var colorHolder = new Button { Content = _colorButton, Width = OverlayChrome.ButtonSize, Height = OverlayChrome.ButtonSize, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Focusable = false, ToolTip = "Colour (1–9)", Cursor = Cursors.Arrow };
        colorHolder.Click += (_, _) => { _colorStripVisible = !_colorStripVisible; Invalidate(); };
        toolStack.Children.Add(colorHolder);
        var undo = OverlayChrome.LabelButton("↶", "Undo (Ctrl+Z)", 16);
        _undoButton = undo;
        undo.Click += (_, _) => Undo();
        toolStack.Children.Add(undo);
        _palette = OverlayChrome.Panel(toolStack);

        // Action bar (horizontal): Copy, Save, Cancel.
        var actionStack = new StackPanel { Orientation = Orientation.Horizontal };
        var copy = OverlayChrome.LabelButton("Copy", "Copy to clipboard (Ctrl+C / Enter)", 12, 44);
        copy.Click += (_, _) => CopyToClipboard();
        var save = OverlayChrome.LabelButton("Save", "Save as PNG (Ctrl+S)", 12, 44);
        save.Click += (_, _) => Save();
        var cancel = OverlayChrome.LabelButton("✕", "Cancel (Esc)", 13);
        cancel.Click += (_, _) => Cancel();
        actionStack.Children.Add(copy);
        actionStack.Children.Add(save);
        actionStack.Children.Add(cancel);
        _actionBar = OverlayChrome.Panel(actionStack);

        // Colour strip.
        var stripStack = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < OverlayChrome.Palette.Length; i++)
        {
            var index = i;
            var swatch = OverlayChrome.Swatch(OverlayChrome.Palette[i], 20);
            var button = new Button { Content = swatch, Width = 24, Height = 24, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Focusable = false, Margin = new Thickness(2, 0, 2, 0), Cursor = Cursors.Arrow, ToolTip = i < 9 ? $"Colour {i + 1}" : "Colour" };
            button.Click += (_, _) => SetColor(index);
            stripStack.Children.Add(button);
        }
        _colorStrip = OverlayChrome.Panel(stripStack);

        // Emoji strip: common emojis plus "+" for any other (typed/pasted, or via Win+.).
        var emojiStack = new WrapPanel { Orientation = Orientation.Horizontal, Width = OverlayChrome.EmojiColumns * 26 };
        foreach (var emoji in OverlayChrome.EmojiPresets)
        {
            var b = OverlayChrome.LabelButton(emoji, $"Stamp {emoji}", 15, 26);
            if (b.Content is TextBlock tb) tb.FontFamily = new FontFamily("Segoe UI Emoji");
            b.Tag = emoji;
            var chosen = emoji;
            b.Click += (_, _) => SetEmoji(chosen);
            emojiStack.Children.Add(b);
        }
        var more = OverlayChrome.LabelButton("+", "More emoji… (type or paste one; Win+. opens the picker)", 15, 26);
        more.Click += (_, _) => BeginEmojiPick();
        emojiStack.Children.Add(more);
        _emojiStrip = OverlayChrome.Panel(emojiStack);

        _host!.Children.Add(_palette);
        _host.Children.Add(_actionBar);
        _host.Children.Add(_colorStrip);
        _host.Children.Add(_emojiStrip);
        _emojiStrip.Visibility = Visibility.Collapsed;
        _palette.Visibility = Visibility.Collapsed;
        _actionBar.Visibility = Visibility.Collapsed;
        _colorStrip.Visibility = Visibility.Collapsed;
    }

    private static void Place(FrameworkElement element, Rect rect)
    {
        Canvas.SetLeft(element, rect.X);
        Canvas.SetTop(element, rect.Y);
    }

    private enum BadgeShape { Circle, Square, None }

    /// <summary>Shows the real stroke size as a circle/block in the tool colour, centred on the cursor, plus the number.</summary>
    private void ShowWidthBadge(string text, double width, Color color, BadgeShape shape)
    {
        if (_host is null) return;
        if (_widthBadge is null)
        {
            _widthBadge = new Border { Background = Brushes.Transparent };
            _host.Children.Add(_widthBadge);
        }
        var d = shape == BadgeShape.None ? 0 : Math.Min(Math.Max(width, 2), 200);
        var box = Math.Max(d + 4, 24);
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var preview = new Grid { Width = box, Height = box };
        if (shape != BadgeShape.None)
        {
            System.Windows.Shapes.Shape s = shape == BadgeShape.Circle
                ? new System.Windows.Shapes.Ellipse()
                : new System.Windows.Shapes.Rectangle();
            s.Width = d; s.Height = d;
            s.Fill = new SolidColorBrush(color);
            s.Stroke = Brushes.White; s.StrokeThickness = 1;
            s.HorizontalAlignment = HorizontalAlignment.Center; s.VerticalAlignment = VerticalAlignment.Center;
            preview.Children.Add(s);
        }
        row.Children.Add(preview);
        row.Children.Add(new Border
        {
            Background = OverlayChrome.Chrome,
            CornerRadius = new CornerRadius(11),
            Padding = new Thickness(8, 3, 8, 3),
            Margin = new Thickness(6, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock { Text = text, Foreground = Brushes.White, FontSize = 12, FontWeight = FontWeights.SemiBold },
        });
        _widthBadge.Child = row;
        Canvas.SetLeft(_widthBadge, _lastPoint.X - box / 2);
        Canvas.SetTop(_widthBadge, _lastPoint.Y - box / 2);
        _widthBadge.Visibility = Visibility.Visible;
        _badgeTimer?.Stop();
        _badgeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
        _badgeTimer.Tick += (_, _) => { _badgeTimer!.Stop(); if (_widthBadge is not null) _widthBadge.Visibility = Visibility.Collapsed; };
        _badgeTimer.Start();
    }

    private void UpdateCursor(Point p)
    {
        if (_window is null) return;
        if (IsTextEditing || IsEmojiPicking || IsOverChrome(p)) { _window.Cursor = Cursors.Arrow; return; }
        if (Selection is not { } sel) { _window.Cursor = Cursors.Cross; return; }
        Cursor cursor = _phase switch
        {
            Phase.Moving or Phase.MovingEmoji => Cursors.SizeAll,
            Phase.Erasing => Cursors.Cross,
            Phase.Resizing => HandleCursor(_activeHandle),
            _ => sel.HitTest(p) switch
            {
                SelectionHit.HandleHit hh => HandleCursor(hh.Handle),
                SelectionHit.Inside => _tool is null ? Cursors.SizeAll
                    : _tool == ToolKind.Text ? Cursors.IBeam
                    : _tool == ToolKind.Emoji && EmojiHit(p) is not null ? Cursors.SizeAll
                    : Cursors.Cross,
                _ => Cursors.Arrow,
            },
        };
        _window.Cursor = cursor;
    }

    private bool IsOverChrome(Point p)
    {
        foreach (var el in new FrameworkElement?[] { _palette, _actionBar, _colorStrip, _emojiStrip, _textBox, _emojiReceiver })
        {
            if (el is null || el.Visibility != Visibility.Visible) continue;
            var r = new Rect(Canvas.GetLeft(el), Canvas.GetTop(el), el.ActualWidth, el.ActualHeight);
            if (r.Contains(p)) return true;
        }
        return false;
    }

    private static Cursor HandleCursor(Handle h) => h switch
    {
        Handle.Left or Handle.Right => Cursors.SizeWE,
        Handle.Top or Handle.Bottom => Cursors.SizeNS,
        Handle.TopLeft or Handle.BottomRight => Cursors.SizeNWSE,
        Handle.TopRight or Handle.BottomLeft => Cursors.SizeNESW,
        _ => Cursors.Cross,
    };
}

internal static class ChromeSizeExtensions
{
    public static bool KeyboardShiftDown(this MouseEventArgs _) => Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);

    public static double DesiredSizeOr(this FrameworkElement e, double fallback)
    {
        e.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return e.DesiredSize.Width > 0 ? e.DesiredSize.Width : fallback;
    }

    public static double DesiredSizeHeight(this FrameworkElement e, double fallback)
    {
        e.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return e.DesiredSize.Height > 0 ? e.DesiredSize.Height : fallback;
    }
}
