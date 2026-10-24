# VibeShotMac: project review and implementation plan

Reviewed 2026-10-23 at commit `19dad20`. Recommendation: **keep the Swift/AppKit app and improve it incrementally**. It already matches the goal: a free, local, small Mac utility that you use constantly. No rewrite is justified by the source inspected.

## What exists

Eight Swift files, approximately 3,714 lines, one app target, no third-party packages, no test target. SwiftUI supplies only the app entry and an empty Settings scene; the working interface is AppKit. Apple frameworks handle capture, drawing, preferences, hotkeys, and launch at login. No server or paid service appears in the source.

Flow: `AppDelegate` registers the status item and Control–Option–Shift–S → `QuickSCKitCapture` captures the display under the pointer → `CaptureOverlay` lets you select a region of that frozen image → the region goes to the clipboard and `MarkupEditorController` → `MarkupCanvasView` handles interaction while `MarkupModel` draws annotations. `TitleBarToolbarView` is a custom title-bar accessory.

Implemented tools: selection/move/resize, arrows, rectangles, numbered steps, text, blur, crop, and bounded undo/redo. Edited-image output is clipboard only. There is no save panel, print operation, sharing picker, or AirDrop action. The README overstates export support and macOS compatibility.

## Environment and free operation

Observed: Apple silicon (`arm64`), macOS 27.0.1; selected developer directory is CommandLineTools. `xcodebuild -version` fails because full Xcode is not selected, and no Xcode app was found in the normal Applications listings. Install/select free Xcode before relying on the project build, asset compilation, or Instruments.

The installed `/Applications/VibeShot.app` is **ad-hoc signed**, has no TeamIdentifier, and carries sandbox, user-selected **read-only**, and debug task-access entitlements. This is evidence about the installed binary, not proof it was built from the reviewed commit. The repo starts clean.

You do not need to renew membership to develop and run this Mac utility locally with ad-hoc signing. Preserve the bundle identifier (`com.stremick.VibeShot`) and a stable installation path; test Screen Recording authorization and launch-at-login after rebuilds because changing code identity can affect permission behavior. Keep the currently working installed app until a replacement passes checks.

For convenient public distribution, Developer ID and notarization remain separate concerns. Apple's account documentation says existing Developer ID apps continue working after membership expires; new certificates require membership once the old certificate expires. Do not assume an existing unexpired certificate is available here: none was inventoried. Notarization is a membership service. Rewriting in Rust does not change Gatekeeper, signing, sandbox, or capture permission requirements. [Apple: certificate and membership expiration](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [Apple: account capabilities](https://developer.apple.com/help/account/basics/about-your-developer-account/).

Save, printing, and system AirDrop sharing can use local AppKit APIs; they do not require adding a paid backend. Keep personal source builds as the primary free route, and label downloadable ad-hoc builds accurately. Avoid making recursive quarantine removal the default installation guidance.

## Findings, in priority order

| Priority | Evidence | Consequence and change |
|---|---|---|
| P1 | `AppDelegate.swift`, `applicationDidFinishLaunching`: `.accessory`; project sets `LSUIElement=YES`. No editor File/Edit/Tools menu is constructed. | Accessory apps have no normal application menu bar (also documented in the local Apple SDK header). Build real menus and switch to `.regular` while an editor is open, returning to `.accessory` after the last editor closes. This adds a Dock presence during editing; preserve menu-bar-only idle operation. |
| P1 | `MarkupEditorController.swift:581–585,707–734`; `MarkupModel.swift` element draw methods. | Composite output calls normal element drawing, which includes selected-element outlines. Add an explicit output render mode that excludes all selection UI. Commit active text before exporting. |
| P1 | `QuickSCKitCapture.swift:89–98`: output width/height come from screen points, without backing scale. Crop/composite paths use `NSImage.lockFocus()`. | Capture requests fewer pixels than the display has on Retina; subsequent drawing cannot recover them. Track pixels separately from logical editor points and use an explicit bitmap renderer for predictable output. |
| P1 | `MarkupEditorController.swift:662–688`; canvas is flipped. | Editor crop passes a top-origin rectangle directly to bottom-origin image extraction, unlike the explicit conversion in blur. Correct the conversion and test with distinct top/bottom colors. Keep the overlay's separate bottom-origin conversion intact. |
| P1 | Project: `ENABLE_APP_SANDBOX=YES`, `ENABLE_USER_SELECTED_FILES=readonly`; no export actions. | Saving needs user-selected read/write access when retaining the sandbox. Change that setting when adding `NSSavePanel`, and inspect the built entitlements rather than relying on the empty source entitlements file. |
| P2 | `AppDelegate.startRegionCapture`: guard only checks overlay existence before awaiting capture. | Repeated hotkeys can start overlapping tasks before the overlay exists. Add an explicit capture-in-progress state, reset on success/error/cancel. |
| P2 | `MarkupModel.swift:866–869,938–974`; canvas blur/move previews. | Snapshot duplication can regenerate blur; previews repeatedly extract, TIFF-encode/decode, create filters and create `CIContext`. Share a context, retain immutable source pixels, cache previews, and finalize exact pixels on mouse-up. Measure before larger changes. |
| P2 | `MarkupCanvasView.endTextEditing(shouldCancel:)`. | Escape removes even an existing text annotation. Restore its pre-edit value when cancelling; keep text edits undoable. |
| P2 | Editor window is not resizable, sizes itself to the image, and enforces 700-point minimum width. | Large captures can exceed the usable screen; small captures get an unnecessarily wide window. Add a resizable scroll/zoom viewport bounded by the screen's visible frame. |
| P3 | Editor's block-based appearance observer token is discarded; `deinit` removes `self`. | Store and remove the returned observer token. Remove layout debug prints, redundant state paths and unused helpers as touched. |

The custom thickness popup uses embedded buttons rather than ordinary actionable menu rows; the toolbar width calculation is hard-coded. Replace it with standard menu items plus small preview images, keyboard navigation, labels and selected states. A native `NSToolbar` with overflow is a better long-term fit than expanding title-bar width arithmetic.

These are source findings and risks; no timing measurements or interactive bug reproduction were performed. In particular, verify text orientation and crop behavior with image fixtures before changing shared drawing transforms.

## Continue versus rewrite

| Option | Fit for this project |
|---|---|
| Continue Swift/AppKit | Best fit. Existing native integrations and zero package dependencies; requested features map directly to AppKit. Refactor the renderer and command routing without discarding the editor. |
| Rust with native UI | Still needs macOS UI/framework bindings and the same signing/permission work. Significant replacement effort, with no demonstrated performance bottleneck that Rust solves. Consider a Rust core only if measured CPU-heavy work or cross-platform reuse later warrants it. |
| Tauri/Rust with web UI | Adds a web interface and a native bridge for capture/sharing/menu integration. Cross-platform potential is irrelevant to the current Mac-only need; increases moving parts. |
| Electron or browser app | More runtime/UI overhead or browser capture constraints. Poor fit for a minimal background Mac screenshot tool. |

Vibe coding remains reasonable. Use small changes with explicit acceptance checks; do not turn this into a framework migration or add packages for features AppKit already provides.

## Implementation sequence

### 1. Establish a reproducible free build

Install/select Xcode. Add a documented local ad-hoc build configuration with no personal development-team dependency, an explicit derived-data path, and preserved sandbox entitlements. A candidate invocation to validate is:

```sh
xcodebuild -project VibeShot/VibeShot.xcodeproj -scheme VibeShot \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

This command is proposed, not verified here. Verify the resulting signature and entitlements, then run capture/permissions/login checks before replacing the installed app. Fix the README's Xcode path (it omits the containing `VibeShot/` folder), claims of export formats, and advertised minimum OS. Target settings are macOS 15.0; project defaults say 15.5; README says 13.0. Keep 15.0 as the initial explicit minimum unless older support is actually wanted.

CI currently builds an ad-hoc Release ZIP; tag pushes publish a GitHub release and update a separate Homebrew tap using a secret. No notarization or tests are configured. Pin the Xcode version, share the scheme, set app version/build from release metadata (currently fixed at 1.0/1), and make architecture support explicit. The installed app is arm64-only; do not claim universal distribution without checking the release binary. Replace the VS Code task's machine-specific DerivedData path. Keep the tap token scoped to the tap repository.

**Done when:** clean checkout builds without a paid account, launches locally, captures and copies; permissions and login behavior are documented; release metadata matches its tag.

### 2. Fix output correctness, then add Save / Print / Share

Extract a small `CompositeRenderer` from `createCompositeImage()`. Give it a stable source bitmap, logical coordinates, explicit pixel dimensions and an output mode without selection/drag/crop guides. Preserve image color information where practical. Fix Retina sizing and crop conversion here. Do not maintain a separate renderer for each output destination.

- **Save… (⌘S):** finish text editing, show `NSSavePanel`, encode PNG using `NSBitmapImageRep` or ImageIO, write atomically, report errors and allow cancellation. Start with PNG only; add JPEG only if useful.
- **Print… (⌘P):** render the same composite into a dedicated print view and present `NSPrintOperation` with aspect-preserving fit-to-page and normal printer/PDF controls. Never print a snapshot of the editor chrome.
- **Share…:** anchor `NSSharingServicePicker` to a toolbar button. For consistent filename/format, share a temporary PNG URL and retain it through completion/cancellation; clean temporary files afterward and on a later launch if needed.
- **AirDrop…:** offer the system `NSSharingService` named `.sendViaAirDrop`, check `canPerform(withItems:)`, and show an unavailable state when appropriate. Keep the service/delegate alive through completion. Recipient selection stays in the system UI. [Apple: system sharing and AirDrop](https://developer.apple.com/documentation/appkit/nssharingservice?changes=_1).

**Done when:** Copy/PNG/Print/AirDrop contain the same annotations and committed text, no selection borders, correct crop, and expected native pixel dimensions at 1× and 2×. Save cancel/failure, print cancel/PDF, AirDrop cancel/unavailable/success are exercised. Validate receiving the PNG on another device.

### 3. Make editor commands discoverable

Create File (Save, Print, Share, Close), Edit (Undo, Redo, Copy, Delete), and Tools menus. Route actions through the active editor/responder chain with validation. Let `NSTextView` retain normal text copy/delete/undo while it has focus. Keep single-letter tools inactive during text input. Add visible Copy and Share toolbar controls; expose tool names, shortcuts and accessibility labels. Use standard thickness menu rows. Track editor-window lifetime explicitly; the app currently stores only one editor controller, so decide whether a new capture replaces the previous editor or is retained alongside it.

**Done when:** menus appear on editor activation from hotkey/status item, remain correct after switching applications and closing/reopening editors, and all menu/toolbar/keyboard routes produce the same action.

### 4. Improve speed and maintainability where measured

Use `SCScreenshotManager.captureImage(contentFilter:configuration:)` instead of starting/stopping a stream just to collect one frame. It is available from macOS 14 in the installed SDK, below the proposed 15.0 minimum. Preserve frozen-screen selection and display-coordinate handling. Add the capture-in-progress guard first. The current collector also mutates continuation state from a stream callback, a timeout task and a start-capture completion; a source type-check warns about its non-Sendable capture. Replace this shared mutable completion path or serialize it explicitly; do not silence the warning with unchecked Sendable conformance.

Reuse `CIContext`, eliminate TIFF round trips in blur, cache/throttle preview work, and finalize after dragging. Separate immutable editor state from transient selection/text/drag state as needed; retain the existing bounded history rather than introducing a document framework. Add zoom/scroll once output behavior is stable.

**Done when:** record before/after cold and warm hotkey-to-overlay latency, drag responsiveness and memory after repeated edits/crops. Use Instruments to locate remaining stalls. No language-level speed claim substitutes for these measurements.

## Verification scope

Review covered the Swift source files, project/build settings, empty plist/entitlements sources, CI/release workflows, VS Code task, README, local toolchain and installed-app signature. No source or release behavior was changed. A standalone `swiftc -typecheck` passed with one non-Sendable collector warning; this checks source against the selected SDK, not the Xcode target, resources, signing or deployment compatibility. Full Xcode build, UI checks, printing, AirDrop and performance profiling remain unverified in this environment. Add focused rendering/crop and text-cancel regression tests during implementation; use manual checks for native sharing, permissions, multi-display layouts (including negative origins), mixed Retina scales and launch at login.
