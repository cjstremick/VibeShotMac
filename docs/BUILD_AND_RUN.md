# Prerequisites, build and run

## Requirements

- macOS 15.0+ (Apple silicon or Intel).
- Apple Command Line Tools, including Swift, a macOS SDK and signing utilities.
- Python 3 for assembling the app's Info.plist; included with the installed developer tools on the reviewed machine.
- No Homebrew, downloaded dependencies, Apple account or paid developer membership is needed for the local build.

Check the toolchain:

```sh
xcode-select -p
xcrun swiftc --version
xcrun --show-sdk-path
python3 --version
```

If tools are missing, run `xcode-select --install` and complete Apple's installer. Full Xcode can instead be installed from the Mac App Store if you want its debugger, asset tools and Instruments. If Xcode is installed but not selected, use its Settings → Locations → Command Line Tools selector. Any installation/login/license confirmation is a local user step.

## Normal local workflow

Run these from the repository root:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/run.sh
```

The build uses Swift 5 language mode, an optimized macOS 15 target, a repository-local module cache and output path, existing icons, and ad-hoc signing. `run.sh` builds and opens `build/VibeShot.app`; it refuses to start while another VibeShot process is running. Build alone never replaces `/Applications/VibeShot.app`.

The test executable uses AppKit and Core Image, so run tests in a normal logged-in macOS session with graphics services available. A restricted automation sandbox may prevent icon generation or GPU rendering; this is distinct from missing Xcode. On CI, run on a macOS runner. No screen capture, printer output or AirDrop transmission occurs in the regression suite. Tests create `build/render-check.png` for visual inspection.

Optional build metadata:

```sh
VERSION=1.1.0 BUILD_NUMBER=2 ./scripts/build.sh
ARCH=x86_64 ./scripts/build.sh
```

`ARCH` is `arm64` or `x86_64`; a cross-compiled app can be built but cannot necessarily run on the build machine. Release packaging builds both and combines the executable with `lipo`, then signs the final bundle. Local builds use the host architecture.

## Stable installation and permissions

After checking a new build:

1. Quit VibeShot from its menu-bar menu. Keep a backup of the currently working app.
2. Copy the newly built app to a stable location such as `/Applications/VibeShot.app`, replacing the old version only when ready.
3. Open it, trigger Capture Region and grant Screen Recording access if prompted. On newer macOS versions this may be labelled Screen & System Audio Recording. Retry capture; follow any macOS instruction to quit/reopen the app.
4. Verify capture and copy, then enable Launch at Login from the status menu if wanted.

Ad-hoc code identity changes can cause macOS to ask for capture permission again. Keep the bundle identifier and installation path stable. If capture is denied, check System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording). Do not reset the whole privacy database or disable Gatekeeper to troubleshoot one app.

Save uses a standard file chooser with sandbox user-selected read/write access. Print uses the native print dialog and sandbox printing entitlement. Share/AirDrop uses a temporary PNG retained until completion/cancellation. No screenshot is uploaded automatically. Temporary share folders older than a day are removed at a later launch.

## Optional Xcode workflow

Open the actual nested project:

```sh
open VibeShot/VibeShot.xcodeproj
```

Select the shared **VibeShot** scheme and My Mac. Signing defaults to ad-hoc, without a development team. Target and project both declare macOS 15.0. The source entitlements explicitly enable sandboxing, user-selected file read/write and printing. Xcode Debug builds may add debugging entitlements.

```sh
xcodebuild -project VibeShot/VibeShot.xcodeproj -scheme VibeShot \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/xcode build
```

The command-line script assembles a normal app bundle directly and therefore also works with Command Line Tools alone; it does not need Xcode's asset catalog compiler. Both paths compile the same source and use the same sandbox entitlements.

## Verification and distribution

```sh
codesign --verify --strict build/VibeShot.app
codesign -dv build/VibeShot.app
codesign -d --entitlements - build/VibeShot.app
```

Expect ad-hoc signing and no TeamIdentifier. A valid ad-hoc signature does not mean a public download is notarized. Developer ID/notarization is a separate optional public-distribution workflow; changing languages does not change it. Do not commit private keys, signing certificates or credentials. Tagged releases update the existing Homebrew tap only when its token is configured.
