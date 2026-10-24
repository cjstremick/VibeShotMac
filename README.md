# VibeShotMac

A small, free, native macOS screenshot and markup utility. Everything runs locally. No account, server, subscription or third-party packages are required.

Capture a region with **Control–Option–Shift–S** or the menu-bar target icon. Annotate it with arrows, plain lines, text, numbered steps, highlights or blur; crop, undo and redo. Copy the result, save a PNG, print it, or use the system Share/AirDrop interface.

The app stays in the menu bar while idle. An editor brings up the Dock icon and normal File/Edit/Tools menus. Multiple captures can remain open. The editor supports scrolling and trackpad pinch zoom; smaller windows use the toolbar's overflow menu.

## Build and run

Requires macOS **15 or later** and Apple's free Command Line Tools. Full Xcode and Apple Developer Program membership are optional.

```sh
# Once, if Apple's developer tools are not installed:
xcode-select --install

# From the repository root:
./scripts/test.sh
./scripts/run.sh
```

The app is built at `build/VibeShot.app` and ad-hoc signed for local use. `run.sh` asks you to quit another running VibeShot first so the two copies do not compete for the hotkey. Grant Screen Recording permission to VibeShot when macOS asks, then retry capture. Do not turn on Launch at Login for a temporary build path.

For prerequisites, stable installation, Xcode, permissions and troubleshooting, see [Build and run](docs/BUILD_AND_RUN.md). For verification details and remaining manual checks, see [Implementation status](docs/IMPLEMENTATION_STATUS.md). The original assessment is in [Project review](docs/PROJECT_REVIEW.md).

## Editing shortcuts

| Action | Shortcut |
|---|---|
| Copy screenshot (text selection while editing text) | ⌘C |
| Save PNG / Print / Close | ⌘S / ⌘P / ⌘W |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Selection / Arrow / Line / Rectangle | S / A / L / R |
| Highlighter | H |
| Numbered step / Text / Blur / Crop | C / T / B / K |
| Finish text / Cancel text editing | ⌘Return / Escape |
| Delete selected annotation | Delete |

Text wraps at the screenshot edge and keeps the same layout after you accept it. Choose Highlighter (H) and drag over text or an area. It starts in translucent yellow; use the color picker for another color and Selection (S) to move or resize the highlight.

Tool letters apply while the canvas has focus, not while typing. Escape restores existing text or discards a new text annotation. Crop applies when you finish dragging.

## Development and releases

Swift + AppKit, with a minimal SwiftUI app entry point. ScreenCaptureKit handles capture; Core Graphics and Core Image handle pixel output and blur. No external packages.

- `VibeShot/VibeShot/`: app source and assets.
- `Tests/RegressionTests.swift`: local rendering and editor regression checks.
- `scripts/`: repeatable build, run and test commands.
- `VibeShot/VibeShot.xcodeproj`: optional Xcode project.
- `.github/workflows/`: CI and tagged-release packaging.

`./scripts/build.sh` builds for the current Mac architecture. A release workflow packages both Apple silicon and Intel slices. Downloadable ad-hoc builds are **not notarized** and may be blocked by Gatekeeper; building locally is the recommended free route. Homebrew packaging does not remove macOS security requirements.

Built with AI assistance. Contributions and small, verifiable changes are welcome. See [Contributing](CONTRIBUTING.md), the [repository review](docs/REPOSITORY_REVIEW.md), and [LICENSE](LICENSE).
