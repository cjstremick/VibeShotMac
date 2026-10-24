# Contributing

VibeShot is a native macOS 15+ app written in Swift and AppKit. Keep changes small and use Apple frameworks where practical. No third-party package manager is required.

## Local development

1. Install Apple's Command Line Tools, then run `./scripts/test.sh`.
2. Run `./scripts/run.sh` to build and open the app. Quit any running copy first.
3. For Xcode debugging, open `VibeShot/VibeShot.xcodeproj` and select the shared VibeShot scheme.

See [build instructions](docs/BUILD_AND_RUN.md) for permissions and installation. Avoid replacing your daily-use app until you have checked the development build.

## Source map

- `AppDelegate.swift`: app lifecycle, menu bar, hotkey, capture coordination.
- `QuickSCKitCapture.swift` and `CaptureOverlay.swift`: capture and region selection.
- `MarkupEditorController.swift`: editor commands, undo, export and toolbar integration.
- `MarkupCanvasView.swift`: canvas interaction and live text editing.
- `MarkupModel.swift`, `HighlighterElement.swift` and `AnnotationTextLayout.swift`: annotations and text layout.
- `CompositeRenderer.swift`: shared pixel output for clipboard, save, print and share.
- `Tests/RegressionTests.swift`: executable AppKit regression suite.

Source paths above are inside `VibeShot/VibeShot/`. The nested directory is a normal Xcode layout. Keep generated output in ignored `build/`; do not commit user-specific Xcode settings, signing certificates or credentials.

## Before opening a pull request

- Run `./scripts/test.sh` and `./scripts/build.sh`. Rendering tests need a working macOS graphics session; report environment failures rather than skipping assertions.
- With full Xcode installed, run the Xcode build command from CI. The regression suite runs through the script, not the scheme's empty Test action.
- For drawing changes, check 1×/2× output, undo/redo, live preview and exported pixels. For capture changes, check Screen Recording authorization and the real hotkey-to-editor flow.
- Describe the behavior changed and the checks performed, including checks you could not run. Never attach a private screenshot without redacting it.

## Releases

Maintainers should first merge a green CI build and complete the applicable [manual acceptance checks](docs/IMPLEMENTATION_STATUS.md). Keep `VERSION` in `scripts/build.sh` and both Xcode `MARKETING_VERSION` settings aligned. Push a `vMAJOR.MINOR.PATCH` tag only when ready to publish: the release workflow immediately creates public assets and may update the configured Homebrew tap.

The workflow builds a universal, ad-hoc-signed app. It does not perform Developer ID signing or notarization. Do not describe these downloads as notarized. No signing certificate or tap token is needed for ordinary contributions.
