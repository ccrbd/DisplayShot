# Architecture

Two native apps, one repository, one shared behaviour spec ([SPEC.md](SPEC.md)). No shared runtime,
so each app is a few MB and launches instantly.

## Shared design

- **Capture first, then overlay.** The screen is grabbed into an image before the overlay appears,
  so the overlay is never in the shot and the screen appears frozen.
- **One renderer for screen and export.** The annotation renderer draws the annotation list into a
  graphics context. The live overlay calls it at screen scale; the exporter calls it over the cropped
  source at native pixel scale. What you see is what gets copied.
- **Redaction burns into the output.** Pixelate/blur run on the source pixels before annotations are
  drawn, so the exported PNG is flat and nothing is recoverable. The pixelation grid is anchored to
  the image origin so regions never shimmer when moved.
- **Pure, tested core.** Selection math, toolbar placement, the annotation store, drawing-tool
  geometry, and the redaction pixel functions are pure and covered by tests. UI is a thin shell.

## macOS (`macos/`)

Swift + AppKit, built with SwiftPM — no Xcode, no asset catalogs. AppKit (not SwiftUI) drives the
overlay for precise mouse/keyboard control and zero-latency drawing.

- `DisplayShotKit` — the whole app as a library: status-item app delegate, Carbon global hotkey,
  ScreenCaptureKit capture, the overlay (`OverlaySession` coordinator + one `OverlayView`/window per
  display), annotations, Core Image redaction, and export.
- `DisplayShot` — a thin executable that launches the kit.
- `DisplayShotChecks` — a self-contained test runner (`swift run DisplayShotChecks`) so tests run
  with the Command Line Tools alone, without XCTest.

One overlay window per `NSScreen`: an `NSWindow` has a single backing scale, so per-display windows
keep each display pixel-perfect. Selection stays on the display where the drag began.

The app bundle is assembled by `scripts/build-app.sh` and ad-hoc signed. Screen Recording permission
is keyed to the code signature, so it re-prompts after each rebuild during development.

## Windows (`windows/`)

C# + .NET 8 WPF, no NuGet dependencies (WinForms is used only for the tray `NotifyIcon`).

- One overlay window spans the whole virtual screen. Monitors are captured into one virtual-screen
  bitmap; the canvas cancels WPF's DPI transform so one unit is one physical pixel across mixed-DPI
  monitors, which makes cross-monitor selections work with a single window and state object.
- `AnnotationRenderer` draws with `DrawingContext`; `ImageComposer` uses `RenderTargetBitmap` plus a
  manual multiply pass for the marker so exports match the screen.
- Settings are JSON in `%APPDATA%\DisplayShot`; "start with Windows" uses the per-user Run key.

## IP hygiene

No third-party product names or URLs appear anywhere in the repository. `scripts/check-ip.sh` (run in
CI) fails the build if any do.
