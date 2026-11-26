# Implementation status

2026-10-23. First implementation following the project review. Changes are local and uncommitted; nothing was published and the installed `/Applications/VibeShot.app` was not replaced.

## Implemented

- **Free build:** repeatable build/run/test/package scripts using the existing Apple Command Line Tools. No new tool installation was necessary. Full Xcode remains optional for debugging/profiling. Removed the personal development-team dependency; local builds use ad-hoc signing and explicit sandbox entitlements.
- **Native menus:** File, Edit and Tools menus; normal application activation while editors are open and menu-bar-only operation after the last closes. Multiple editor controllers are retained independently. Menu actions use the responder chain so text editing retains standard copy/cut/paste and undo behavior.
- **Exports:** PNG Save, native Print, system Share and direct AirDrop actions. Visible Copy/Save/Print/Share toolbar buttons, with native toolbar overflow. Share files live until completion or cancellation; interrupted-session files are pruned after a day. No external transfer happens automatically.
- **Pixel correctness:** explicit bitmap renderer shared by all output actions; native Retina dimensions; selection indicators excluded without mutating editor state. Output is 8-bit sRGB PNG. Crop uses explicit top-origin pixel coordinates and preserves source scale.
- **Capture:** single-image ScreenCaptureKit API replaces the first-frame stream collector and its shared mutable continuation state. A capture-in-progress guard prevents overlapping hotkey requests. Frozen-display region selection remains intact.
- **Editing:** Escape restores existing text and discards new text. Export commits active text first. Resizable editor, scrollbars, pinch zoom and centered small screenshots replace oversized fixed windows.
- **Blur:** shared Core Image context, no TIFF round trip, cached snapshot copies and strongly retained source images. Moves finalize the blur exactly, including moves smaller than the preview regeneration threshold. Crop refreshes blur after repositioning.
- **Cleanup:** removed the unused block appearance observer instead of leaking its token, removed layout debug output, standard thickness menu rows and explicit accessibility labels.
- **Build/release hygiene:** shared Xcode scheme, consistent macOS 15 minimum, portable VS Code tasks, version/build metadata in release packaging, universal arm64/x86_64 bundles, and CI regression checks. Tap credentials no longer appear in the clone URL. Release/tap publishing still requires a tag push and was not executed.

## Verified locally

1. Regression suite passes under the installed Swift 6.4 toolchain in Swift 5 language mode, targeting macOS 15. It checks 1×/2× crop coordinates, output dimensions and orientation, selection-free output for every element type, blur sampling/pixels, text cancel/commit, centered scrolling, toolbar construction and controller responder routing.
2. Rendered fixture inspected visually: upright text and step numbers, correct top/bottom colors.
3. Synthetic editor tested through the native UI: File menu, Save sheet, actual PNG output (240×200 from a 120×100-point fixture), Print preview (one page) and cancellation, Share choices including AirDrop and cancellation, and thickness menu selection. Save, Print preview and Share were also checked with the app's sandbox entitlements enabled. No physical printing or external sharing occurred.
4. Universal development bundle built and ad-hoc signature verified; both `arm64` and `x86_64` slices present. Intel execution was not tested on this Apple silicon machine.
5. Shell syntax, workflow YAML, project plist and entitlements validated. CI is configured to check the optional Xcode build as well, but that build cannot run locally without full Xcode. [The pinned runner currently provides Xcode 16.4](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-Readme.md).

Restricted automation initially prevented icon generation and Core Image rendering. Both succeeded when run with normal macOS graphics access. This was an execution-environment limitation, not a reason to install full Xcode.

## Remaining acceptance checks

These need the real app and local OS/device state; they are not claimed as tested:

- Fresh and existing Screen Recording authorization; full hotkey → frozen overlay → crop → editor flow.
- Mixed 1×/2× displays, negative display origins and display changes.
- Menu/Dock behavior after multiple real captures, application switches and closing the last editor.
- Launch at Login from a stable installation path, including disabling it afterward.
- Successful receipt on another device using AirDrop, unavailable/cancelled AirDrop, physical printing and PDF output.
- Timing and Instruments measurements of cold/warm capture and long blur-drag sessions. The code eliminates repeated setup/conversions, but no performance percentage is claimed.
- Optional Xcode project build, remote CI execution and runtime checks on macOS 15 / Intel hardware.

Use the development bundle before replacing the daily-use copy. Once the acceptance checks pass, install at the stable path described in [Build and run](BUILD_AND_RUN.md). No paid membership is needed for this local workflow.

## Follow-up: text, lines and magnifier (1.2.0)

The text editor and accepted annotation now use the same TextKit layout and fixed width. New text wraps at the screenshot edge; accepting or reopening preserves line breaks, whitespace, font and color. Regression checks compare glyph positions and actual rendered pixels before/after acceptance, including long words, multiple lines and trailing newlines.

Added Line (L), sharing the arrow's endpoint selection/resize logic without an arrowhead. Added Magnifier (M): an automatically placed enlarged inset connected to a selected region of original screenshot pixels. The inset moves independently, resizes proportionally, survives crop/undo/redo and appears in all output actions. New tools are available in the toolbar, Tools menu and overflow menu. Toolbar sizing now follows the tool count.

See [Feature ideas](FEATURE_IDEAS.md) for the requested shortlist of other screenshot/markup features.

## Follow-up: highlighter replaces magnifier (1.3.0)

Removed the magnifier tool, model, previews and tests. Added Highlighter (H): drag a rectangular translucent marker over screenshot content, then move or resize it using Selection (S). It starts yellow and remembers its own color for the editor session, without changing arrow/text colors. Multiply compositing keeps dark text readable; highlights sit beneath other annotations. The same rendering is used by live preview and clipboard/save/print/share. Tests cover marker tint, text readability, selection-free output, snapshots, resize and undo/redo; existing text and line checks remain.

## Follow-up: small-capture sizing and silent MP4 recording (1.4.0)

- **Editor sizing:** the window now opens wide enough for the full markup toolbar plus the Copy/Save/Print/Share items, so small captures no longer hide tools in the toolbar overflow. The image stays centered in the scroll view. Toolbar width and window sizing share one metrics type (`MarkupToolbarMetrics`).
- **Recording (video only):** Control–Option–Shift–R or **Record Region** starts a ScreenCaptureKit H.264 `.mp4` recording of the selected region. A red border, a subtle dim outside the region, a small REC badge and a Stop button just outside the region show what is being captured; VibeShot excludes its own windows so this chrome never appears in the video. **Stop** (on-screen, menu-bar, or Stop Recording) finalizes the file and opens a modal Save panel. No audio track is written, so no microphone entitlement or extra permission is needed. GIF export and audio are deferred.
- **Recording save fix:** the recorder is now retained through stream finalization; previously it could deallocate before the stop completion ran, which skipped the Save dialog entirely. Destination writes use security-scoped access, a copy-first path with a move fallback, and a recovery folder (Application Support/VibeShot/Recordings) that is revealed if a chosen location cannot be written, so a finished recording is never discarded.
- **Countdown region mask:** the dimmed surround and red border now appear as soon as a region is selected, so the captured area is visible through the countdown. The Stop control is revealed only when capture actually starts. The countdown number and halo are centered inside the capture region and scale down for small selections.
- **Recording settings:** a new Settings window (⌘,) chooses the post-recording action — ask, save to a folder (stored as a security-scoped bookmark), or copy the video to the clipboard as a file reference — and sets a 0/3/5/10-second countdown. The countdown is a click-through full-screen animation shown after region selection and before capture begins. An optional "Pointer & clicks" setting adds the real pointer shape (`showsCursor`) plus click ripples and scroll arrows, drawn on a caption overlay that is captured while the recording HUD itself is excluded.
- **Recording reliability:** encoded dimensions are rounded to even values and capped at 4K for H.264 compatibility; only fully rendered ScreenCaptureKit frames (`SCFrameStatus.complete`) are appended to the writer; and stream, append and finalize errors are logged with domain, code and underlying error instead of the generic "operation could not be completed". A synthetic encoder check now runs in the regression suite.
- **Stable local signing:** `scripts/build.sh` and `scripts/package.sh` use a stable identity named `VibeShot Dev` when one exists (or `CODE_SIGN_IDENTITY`), instead of changing ad-hoc identity every build. This keeps macOS Screen Recording approval across rebuilds; documented in BUILD_AND_RUN.
- **Performance:** blur drag previews reuse the previous frame and only regenerate the Gaussian blur after roughly 8 points of movement; moving a blur element reuses its cached pixels until release.
- **Undo hygiene:** cancelling a new text annotation no longer leaves an empty undo step, and a failed crop no longer pushes an undo snapshot.

Verified locally: the regression suite passes, including new toolbar-width, text-undo and idle-recorder checks; the full app target builds and signs with the existing sandbox entitlements. Not verified here: a real screen recording (needs Screen Recording authorization and a live display), Save-panel output, and playback of the resulting file.
