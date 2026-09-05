# DisplayShot behaviour specification

Both the macOS and Windows apps implement this spec identically. Coordinates are in the platform's
capture space: points × backing scale on macOS (one overlay per display), physical pixels on Windows
(one overlay across the virtual screen).

## Lifecycle

1. A global hotkey triggers a capture.
2. The app grabs every display into a frozen image, then shows a borderless full-screen overlay that
   paints the frozen image dimmed (black at 45%). The overlay itself never appears in the shot.
3. The user selects, annotates, and exports. The overlay closes on copy, save, or cancel.
4. The app keeps running in the menu bar / tray.

## State machine

```
Idle ──drag──▶ Selecting ──release──▶ Selected ──pick tool──▶ ToolActive ──drag──▶ Drawing ──▶ ToolActive
  ▲  full-screen key ────────────────▲   click outside the box with no tool → new selection
Selected/ToolActive: handles resize · body drag moves · arrows nudge · undo/redo · copy · save
```

## Esc cascade

One level per press, so the overlay never closes mid-action:

1. Drawing a shape → cancel that shape, stay on the tool.
2. Text box open → discard the text.
3. Colour strip open → close it.
4. A tool is active → deselect the tool.
5. A selection exists → clear the selection and its annotations.
6. Nothing selected → close the overlay.

## Selection

- Click-drag draws the box; the full-screen key snaps to the display under the cursor.
- Eight handles (four corners, four edges) resize; the box flips correctly when dragged through
  itself. Dragging the body moves it. Everything is clamped to the display.
- Holding Shift constrains a drag/resize to a square.
- Arrow keys nudge by 1 px (10 px with Shift). Alt+arrows grow/shrink the right/bottom edges.
- A live `W × H` label sits by the selection.

## Tools

Pen (freehand), Line, Arrow (filled head), Rectangle, Marker (highlighter), Text (inline), Redact.

- The mouse wheel changes the active tool's width (font size for Text, block size for Redact). Each
  tool remembers its own width; widths persist across sessions.
- Line and Arrow snap to 0/45/90° while Shift is held; Rectangle becomes a square.
- Marker strokes are composited as one layer at 35% with a multiply blend, so overlapping strokes
  never double-darken and text underneath stays legible.
- Text commits on click-away or Ctrl/Cmd+Return; an empty text box is discarded.
- Redact shows a live pixelated/blurred preview while dragging. Its block grid is anchored to the
  image origin, so moving or resizing a region never makes blocks shimmer. Holding Shift switches a
  region to blur instead of pixelate. Redaction destroys pixels in the exported image.

## Colours

Ten presets, selectable by clicking a swatch or pressing `1`–`9`, plus a custom colour picker. The
last colour is remembered.

## Export

- **Copy**: compose the cropped, annotated image at native pixel scale, put PNG + bitmap on the
  clipboard, verify the write, then close and show a confirmation toast.
- **Save**: same composition; show a save dialog with a timestamped name (`DisplayShot YYYY-MM-DD at
  HH.MM.SS.png`) and a remembered folder, or write silently to the configured folder when "save
  without asking" is on.
- A short sound plays on success (toggleable).

## What DisplayShot never does

Cloud upload or sharing, printing, reverse image search, scrolling capture, video.
