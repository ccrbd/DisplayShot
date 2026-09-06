# DisplayShot behaviour specification

Both the macOS and Windows apps implement this spec identically. Coordinates are in the platform's
capture space: points × backing scale on macOS (one overlay per display), physical pixels on Windows
(one overlay across the virtual screen).

## Lifecycle

1. A global hotkey triggers a capture.
2. The app grabs every display into a frozen image, then shows a borderless full-screen overlay that
   paints the frozen image dimmed (black at 45%). The overlay itself never appears in the shot.
3. Before a selection exists, a translucent hint ("Drag to select an area · full-screen key · Esc")
   sits a quarter of the way down the display so it does not cover what people usually capture.
4. The user selects, annotates, and exports. The overlay closes on copy, save, or cancel.
5. The app keeps running in the menu bar / tray.

## State machine

```
Idle ──drag──▶ Selecting ──release──▶ Selected ──pick tool──▶ ToolActive ──drag──▶ Drawing ──▶ ToolActive
  ▲  full-screen key ────────────────▲   click outside the box with no tool → new selection
Selected/ToolActive: handles resize · body drag moves · arrows nudge · undo/redo · copy · save
```

## Esc

Esc cancels whatever is mid-edit, one level per press: a shape being drawn, an open text box, an
emoji pick, the colour strip. When nothing is mid-edit — including when a selection exists — Esc
closes the overlay immediately (the user has decided not to take the shot).

## Selection

- Click-drag draws the box; the full-screen key snaps to the display under the cursor.
- Eight handles (four corners, four edges) resize; the box flips correctly when dragged through
  itself. Dragging the body moves it. Everything is clamped to the display.
- Holding Shift constrains a drag/resize to a square.
- Arrow keys nudge by 1 px (10 px with Shift). Alt+arrows grow/shrink the right/bottom edges.
- The selection border is a white dotted line over a dark underlay. A live `W × H` label sits by it.
- Cursor: crosshair before a selection exists and inside it while a drawing tool is active; the
  default arrow outside the selection and over the toolbars; resize/move cursors on handles/body.

## Tools

Pen (freehand), Line, Arrow (filled head), Rectangle, Marker (highlighter), Text (inline), Emoji, Redact, Eraser.

- The mouse wheel changes the active tool's width (font size for Text/Emoji, block size for Redact).
  While it changes, a circle (block for Redact) of the real size in the tool colour is shown
  centred on the cursor next to the number. Each tool remembers its own width; widths persist.
- Line and Arrow snap to 0/45/90° while Shift is held; Rectangle becomes a square.
- Marker strokes are composited as one layer at 35% with a multiply blend, so overlapping strokes
  never double-darken and text underneath stays legible.
- Text commits on click-away or Ctrl/Cmd+Return; an empty text box is discarded.
- Emoji: the tool button shows the current emoji. Left-click activates it; right-click opens a
  grid of 40 common emojis plus "more" (system picker on macOS; typed/pasted or Win+. on Windows),
  which closes after a pick. Clicking inside the selection stamps the current emoji; dragging an
  existing one moves it; the wheel resizes the last one (and future stamps); `[` / `]` or
  Option/Alt+wheel rotate it in 15° steps.
- Eraser: a dashed circle follows the cursor; click or drag to remove every annotation the circle
  touches (strokes by their outline, shapes by their border, text/emoji/redaction by their box).
  One eraser stroke undoes as a single step.
- Redact has three modes — mosaic (default), blur, blackout — chosen by right-clicking the redact
  tool; the choice persists. Redact shows a live preview while dragging. Its block grid is anchored to the
  image origin, so moving or resizing a region never makes blocks shimmer. Holding Shift switches a
  region to blur instead of pixelate. Redaction destroys pixels in the exported image.

## Colours

Ten presets, selectable by clicking a swatch or pressing `1`–`9`, plus a custom colour picker. The
last colour is remembered.

## Export

- **Copy**: compose the cropped, annotated image at native pixel scale, put PNG + bitmap on the
  clipboard, verify the write, then close and show a confirmation toast.
- **Save**: same composition; show a save dialog with a format chooser (JPEG default, PNG, TIFF),
  a timestamped name (`DisplayShot YYYY-MM-DD at HH.MM.SS.jpg`) and a remembered folder; the chosen
  format is remembered. "Save without asking" writes silently in the preferred format.
- A short sound plays on success (toggleable).

## What DisplayShot never does

Cloud upload or sharing, printing, reverse image search, scrolling capture, video.
