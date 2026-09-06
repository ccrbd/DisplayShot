<p align="center">
  <img src="assets/icon.svg" width="120" alt="DisplayShot icon">
</p>

<h1 align="center">DisplayShot</h1>

<p align="center">A fast, native screenshot tool for macOS and Windows.<br>
Press a shortcut, select a region, annotate, and copy or save. That's it.</p>

---

DisplayShot is a lightweight capture tool built for one job: grab part of the screen, mark it up if
needed, and get it onto your clipboard or disk in a second. No accounts, no cloud, no clutter.

## Features

- **Global hotkey** freezes the screen behind a dimmed overlay, instantly.
- **Selection** by click-and-drag, `⌘A` / `Ctrl+A` to snap to the full screen, eight resize handles,
  and drag to reposition. A live `W × H` readout follows the box.
- **Annotation tools**: pen, line, arrow, rectangle, highlighter, inline text, and emoji stamps
  (resize with the wheel, rotate with `[` / `]`, drag to move).
- **Redaction**: mosaic (default), blur, or blackout to hide passwords, tokens and emails.
  Right-click the redact tool to switch. The pixels are destroyed in the exported image, so
  nothing is recoverable.
- **Colour palette** with keys `1`–`9`, plus a custom colour picker.
- **Mouse wheel** changes the current tool's stroke width on the fly.
- **Undo / redo** annotations one step at a time.
- **Copy** to the clipboard or **save** as JPEG, PNG or TIFF (chooser in the save dialog), then
  the overlay closes.

Deliberately left out: cloud upload, printing, and reverse image search.

## Shortcuts

The overlay is fully keyboard-driven. macOS uses `⌘`; Windows uses `Ctrl` (and `Alt` where macOS
uses `⌥`).

| Action | macOS | Windows |
|---|---|---|
| Open capture overlay | `⌘⇧1` (default) | `PrtScn` (default) |
| Select full screen | `⌘A` | `Ctrl+A` |
| Copy and close | `⌘C` or `Return` | `Ctrl+C` or `Enter` |
| Save (JPEG/PNG/TIFF) and close | `⌘S` | `Ctrl+S` |
| Undo / redo | `⌘Z` / `⌘⇧Z` | `Ctrl+Z` / `Ctrl+Shift+Z` |
| Cancel / close | `Esc` | `Esc` |
| Pen / Line / Arrow | `P` / `L` / `A` | `P` / `L` / `A` |
| Rectangle / Marker | `R` / `M` | `R` / `M` |
| Text / Emoji / Redact | `T` / `E` / `X` | `T` / `E` / `X` |
| Rotate last emoji | `[` / `]` or `⌥`+wheel | `[` / `]` or `Alt`+wheel |
| Move tool (no drawing) | `V` | `V` |
| Pick colour | `1`–`9` | `1`–`9` |
| Nudge selection 1 px / 10 px | arrows / `⇧`+arrows | arrows / `Shift`+arrows |
| Resize selection edge | `⌥`+arrows | `Alt`+arrows |
| Stroke width | mouse wheel | mouse wheel |
| Constrain (square / 45° / blur) | hold `⇧` while dragging | hold `Shift` while dragging |

`Esc` cancels whatever you are in the middle of (a shape being drawn, a text box, an emoji pick,
the colour strip); otherwise it closes the overlay immediately.

On Windows, emoji stamps render as monochrome glyphs in the current colour (WPF has no colour-font
support); on macOS they are full-colour.

## Install

Prebuilt binaries are attached to each [release](https://github.com/ccrbd/DisplayShot/releases).

- **macOS** (Apple Silicon, macOS 14+): unzip and move `DisplayShot.app` to `/Applications`. On first
  launch macOS asks for **Screen Recording** permission (System Settings → Privacy & Security →
  Screen Recording) — this is required to capture the screen. The build is ad-hoc signed, so the
  first open needs right-click → **Open**.
- **Windows** (Windows 10/11, x64): run `DisplayShot.exe`. It lives in the notification area. On
  Windows 11, `PrtScn` may be owned by the Snipping Tool; DisplayShot falls back to `Ctrl+Shift+1`
  and you can pick any shortcut in **Settings**. Requires the [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0).

Both apps run in the menu bar / tray with no dock or taskbar entry.

## Build from source

### macOS (no Xcode required — Command Line Tools are enough)

```bash
cd macos
swift build -c release          # compile
swift run DisplayShotChecks     # run the test suite
./scripts/build-app.sh          # produce dist/DisplayShot.app
```

`ARCHS="arm64 x86_64" ./scripts/build-app.sh` builds a universal binary. Icons are regenerated with
`./assets/make-icons.sh`.

### Windows

```powershell
cd windows
dotnet build -c Release
dotnet test  -c Release
dotnet publish DisplayShot/DisplayShot.csproj -c Release -r win-x64 -p:PublishSingleFile=true -o publish
```

## Project layout

```
macos/     Swift + AppKit app (SwiftPM). DisplayShotKit library + thin executable + test runner.
windows/   C# + .NET 8 WPF app, no third-party packages.
assets/    Original icon (SVG) and the scripts that render every icon size.
docs/      SPEC.md (shared behaviour) and ARCHITECTURE.md.
```

Both apps share one behaviour spec ([docs/SPEC.md](docs/SPEC.md)) and one visual design, but are
separate native codebases so each stays small and launches instantly.

## License

[MIT](LICENSE) © 2026 ccrbd.
