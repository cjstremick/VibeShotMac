VibeShot – macOS Screenshot & Markup Tool (Specification Baseline)
================================================================

Purpose
-------
Create a lightweight, fast, keyboard‑driven macOS screenshot region capture + markup utility. Focus on low latency from hotkey press to editable image, with persistent user preferences and clean layering for future features.

Authoritative Identifiers
-------------------------
Bundle Identifier: `com.stremick.VibeShot`
Minimum macOS: Sequoia (15.0) only (we can relax later if needed; do not add legacy compatibility shims now).
Architectures: Apple Silicon (arm64) primary; Intel support optional (nice‑to‑have, not required in first pass).

Non‑Negotiable Technical Constraints
------------------------------------
1. No deprecated capture APIs (do NOT use `CGWindowListCreateImage`). ScreenCaptureKit is the primary capture path.
2. If ScreenCaptureKit cannot service a multi‑display spanning selection initially, we may (a) restrict first iteration to single‑display or (b) stitch via per‑display ScreenCaptureKit streams in a follow‑up. Avoid falling back to deprecated APIs for “quick wins.”
3. Status bar (menu bar) only application (`LSUIElement = 1`). No Dock icon, no default main window.
4. Persist user preferences using `UserDefaults` (or a lightweight wrapper) – no external database.
5. All markup elements remain vector / model objects until an explicit composite export or clipboard copy.
6. Code signing: Must use a stable Apple Development identity from the very first run to ensure TCC permission persistence.

Scope – First Iteration (MVP)
-----------------------------
Functional Flow:
1. User triggers capture via menu item or global hotkey.
2. A custom overlay (multi‑display aware) darkens the screen(s) and allows drag region selection (single continuous rectangle). Selection UI shows: live dimensions, guide lines, subtle handles.
3. On mouse up: capture region via ScreenCaptureKit (single display; if selection crosses displays, show a polite alert explaining limitation for iteration 1 and allow retry constrained to one display).
4. Captured region placed immediately on clipboard (PNG) and an editor window opens with markup tools.
5. User edits; Cmd+C in editor copies composited image (base + overlays) to clipboard.
6. Closing editor leaves last composite (or base capture if no edits) unchanged on the clipboard.

Out‑of‑Scope (Explicitly Deferred)
----------------------------------
• Undo/redo stack.
• Multi‑monitor spanning capture via ScreenCaptureKit stitching.
• Fancy export formats (PDF, SVG).
• iCloud/Document persistence.
• Localization.
• Sandbox / App Store distribution.
• Adjustable hotkey UI (hardcoded in code this iteration, but persisted value slot reserved).

User Preferences (Persisted)
---------------------------
• Last stroke color (default: `#D81B60`).
• Last line width (default: 4.0 pt).
• Last font family (placeholder until text tools land).
• Last font size.
• Reserved key for future user‑defined hotkey.

Initial Tool Set
----------------
Implemented (Iteration 1):
• Arrow
• Rectangle

Stubbed with TODO markers (API surfaces defined but minimal UI integration):
• Numbered Stamp (auto‑renumber contiguous on deletion)
• Ellipse
• Text Bubble (will use stored font prefs when implemented)
• Blur (Gaussian placeholder over a selected subrect of the base image at time of composite)

Editor Interaction Rules
------------------------
• Creating an element selects it.
• Selecting another deselects previous.
• Delete key removes selected element (renumber stamps afterward).
• Cmd+C: composite current state to clipboard (raster) without closing.
• Base capture never mutated; overlays stored separately.

Capture Overlay Requirements
----------------------------
• Semi‑transparent dim layer with punched hole for selection.
• Pixel dimensions label near selection (auto reposition to stay on screen).
• Guide lines extending across displays aligned to edges of selection.
• Corner + edge handles (visual only in Iteration 1; resizing deferred).
• ESC cancels (no editor window, nothing copied beyond preexisting clipboard state).
• First mouse drag must initiate selection (no “double attempt” behavior tolerated).

Hotkey
------
• Custom combination (e.g. Control+Option+Command+S) – avoid collisions with native screenshot shortcuts.
• Hardcoded constant + placeholder storage; no UI yet.

Architecture Layers
-------------------
1. Status Bar Layer: NSStatusItem, menu, hotkey registration.
2. Capture Coordination: Permission preflight, overlay lifecycle, ScreenCaptureKit invocation.
3. Overlay UI: Multi‑display windows, selection drawing.
4. Markup Model: Elements, selection, renumbering logic, persistence of style defaults.
5. Rendering: SwiftUI editor + NSViewRepresentable canvas.
6. Utilities: Clipboard service, preferences facade, diagnostics logger.

Diagnostics & Stability Requirements
-----------------------------------
• Provide a diagnostics panel (menu item) showing: bundle id, build version, Screen Recording preflight state, ScreenCaptureKit availability.
• Log structured capture events: preflight result, selected rect, display match, frame acquisition timing.
• On ScreenCaptureKit permission denial (e.g. -3801): show actionable alert (do not silently fall back to empty/wallpaper imagery).

Security / Permissions
----------------------
• Request Screen Recording once; rely on stable signature thereafter.
• Do NOT implement any brittle heuristics (e.g. “is this wallpaper?”). Trust preflight + explicit error domains.

Quality Bar (Definition of Done – MVP)
--------------------------------------
• Build warnings: zero (except possibly SwiftUI preview noise).
• No deprecated API usage.
• A single capture + edit cycle < 1.2s on an Apple Silicon Mac (subjective manual test).
• Multiple sequential captures (≥5) without permission loss or needing relaunch.

Deliverables (Iteration 1)
-------------------------
• Xcode project (native template) configured with:
  – Bundle: `com.stremick.VibeShot`
  – Deployment Target: macOS 15.0
  – Automatic signing (Apple Development)
• Working status bar app (Capture / About / Diagnostics / Quit).
• Functional hotkey invoking overlay.
• Single‑display region capture via ScreenCaptureKit (reject / alert on spanning case for now).
• Clipboard copy (base capture) + editor auto‑open.
• Arrow & Rectangle tools (vector, selectable, movable, deletable, styled).
• Persistence of stroke color + line width.
• CMD+C composites base + overlays to clipboard.
• Stubs (types + enum cases + TODOs) for Numbered Stamp, Ellipse, Text Bubble, Blur.
• About window with placeholder attribution list.
• Diagnostics panel.

Finalized Decisions (User Confirmed)
-----------------------------------
1. Capture limited to single display: active display determined by mouse location at hotkey invocation.
2. Multi-display prevention: selection rectangle is clamped to that display (no spanning; no stitching; cursor may roam, rectangle does not cross boundary).
3. Default hotkey: Option + Control + Shift + S.
4. Line width range: 1–16 pt, default 4 pt.
5. Cmd+W: closes editor silently (clipboard unchanged).
6. Copy semantics: Cmd+C always copies composited (with current markups); no separate “raw” copy command needed.
7. Retina scale logging deferred (may add to diagnostics later only if needed for pixel-perfect tools).

This specification is authoritative; proceed to scaffold the clean Xcode project using these finalized rules.