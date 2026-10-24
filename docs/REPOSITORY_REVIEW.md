# Repository review

Reviewed 2026-10-23 against the current working tree, including existing uncommitted changes. This is a source/build review, not a certification of runtime behavior or public distribution readiness. The older `PROJECT_REVIEW.md` describes the original baseline and is historical.

## Assessment

The existing Xcode layout is appropriate for a small native Mac app. Source, assets, scripts, tests, documentation and generated output have clear homes. A rewrite, extra package manager or directory migration would add little value now. The project already has a license, shared scheme, sandbox entitlements, universal packaging and regression coverage.

## Findings and remaining work

| Priority | Evidence | Impact and next step |
|---|---|---|
| P2 | `scripts/build.sh:10–29` independently defines version, bundle metadata and minimum OS; `project.pbxproj` repeats these settings. | A future change can produce different apps through Xcode and the scripts. Consolidate shared metadata or add a parity check. Until then, update both paths together as documented in CONTRIBUTING. |
| P2 | The shared scheme has an empty Test action; tests are an executable compiled by `scripts/test.sh`. | Xcode's Test action does not run the regression suite. The script is a valid current CI entry point, but an XCTest target would improve discovery, individual test reporting and debugging. Do this as a focused follow-up. |
| P2 | `scripts/build.sh:31` and `scripts/package.sh` use ad-hoc signing; the release workflow has no notarization step. | Public downloads lack a notarized distribution path. README correctly discloses this. Decide whether local-source distribution remains the goal before adding Developer ID credentials and notarization. |
| P3 | `MarkupModel.swift`, `MarkupCanvasView.swift` and `MarkupEditorController.swift` each approach 900 lines. | Changes require navigating several responsibilities. Extract individual annotation types and export/sharing coordination when touching those features; retain rendering regression coverage. No speculative framework migration is needed. |

The release workflow previously checked only the script build. It now also builds the Xcode project before publishing, matching CI. Both workflows now have time limits; superseded CI runs are cancelled. Added contributor instructions with a source map, explicit test entry point and release checklist, plus bug-report and pull-request templates.

## Verification and limits

- Regression suite passed with normal macOS graphics access. The sandboxed run failed creating a Core Image blur fixture, so it must not be reported as a passing sandbox run.
- Shell syntax checks and `git diff --check` passed.
- Full Xcode is not selected/installed in this environment; `xcodebuild -version` fails with the Command Line Tools developer directory. The added workflow build must be verified by GitHub CI.
- No release, tag, Homebrew update, app installation or external sharing was performed.
- Real Screen Recording authorization, hotkey capture, mixed displays, login registration, minimum supported macOS and Intel execution remain manual/device checks listed in IMPLEMENTATION_STATUS.

## GitHub settings outside the repository

Before accepting outside contributions, configure a ruleset on the default branch requiring pull requests and the passing CI build check. Repository files cannot prove those settings are enabled. Keep publishing credentials scoped to the release/tap operation and avoid committing signing material.
