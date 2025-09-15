import Cocoa
import ScreenCaptureKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, CaptureOverlayDelegate {
    private var statusItem: NSStatusItem!
    private let captureService = QuickSCKitCapture()
    private var overlayController: CaptureOverlayController?
    private var overlayDisplay: NSScreen?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // LSUIElement should already enforce no Dock icon
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "target", accessibilityDescription: "VibeShot")
        }
        let menu = NSMenu()
    // Capture item (shortcut will appear to the right automatically)
    let captureItem = NSMenuItem(title: "Capture Region", action: #selector(startRegionCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.option, .control, .shift]
        menu.addItem(captureItem)
        menu.addItem(withTitle: "Test Capture (Center 400x300)", action: #selector(testCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        registerGlobalHotKey()
    }

    // MARK: Region Capture Flow
    @objc private func startRegionCapture() {
        guard overlayController == nil else { return } // already active
        let mouseLoc = NSEvent.mouseLocation
        // Determine display under mouse
        guard let display = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main else {
            return
        }
        overlayDisplay = display
        let controller = CaptureOverlayController(display: display)
        controller.delegate = self
        overlayController = controller
        controller.begin()
    }

    func overlayDidFinish(rect: CGRect?) {
        guard let rect = rect, let display = overlayDisplay else {
            overlayController = nil; overlayDisplay = nil; return
        }
        overlayController = nil
        overlayDisplay = nil
        Task { @MainActor in
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let result = try await captureService.capture(rect: rect, on: display)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([result.image])
                let variance = approximateVariance(of: result.image)
                showPreviewWindow(image: result.image,
                                  info: "\(Int(result.image.size.width))×\(Int(result.image.size.height))\n~\(Int(elapsed)) ms\nVar: \(String(format: "%.3f", variance))")
                NSLog("[RegionCapture] SUCCESS rect=\(NSStringFromRect(rect)) elapsedMs=\(Int(elapsed)) variance=\(variance)")
            } catch {
                showTransientAlert(title: "Capture Failed", text: error.localizedDescription)
                NSLog("[RegionCapture] FAILURE: \(error)")
            }
        }
    }
    
    @objc private func testCapture() {
        Task { @MainActor in
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let result = try await captureService.captureCentralRectOnActiveDisplay()
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([result.image])

                let variance = approximateVariance(of: result.image)
                showPreviewWindow(image: result.image,
                                  info: "400×300\n~\(Int(elapsed)) ms\nVar: \(String(format: "%.3f", variance))")
                NSLog("[QuickCapture] SUCCESS size=\(result.image.size) elapsedMs=\(Int(elapsed)) variance=\(variance)")
            } catch {
                showTransientAlert(title: "Capture Failed", text: error.localizedDescription)
                NSLog("[QuickCapture] FAILURE: \(error)")
            }
        }
    }
    
    @objc private func showDiagnostics() {
        let preflight = CGPreflightScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Diagnostics"
        alert.informativeText = """
Bundle: \(Bundle.main.bundleIdentifier ?? "N/A")
ScreenRecordingPreflight: \(preflight)
SCKitAvailable: \(screenCaptureKitAvailable ? "yes" : "no")
"""
        alert.runModal()
    }
    
    private var screenCaptureKitAvailable: Bool {
        if #available(macOS 13.0, *) { return true } else { return false }
    }
    
    private func showTransientAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - HotKey
    private func registerGlobalHotKey() {
        // Option + Control + Shift + S
        let keyCode: UInt32 = UInt32(kVK_ANSI_S)
        let modifiers: UInt32 = UInt32(optionKey | controlKey | shiftKey)

        var eventTypeSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1, let userData = userData {
                let unmanaged = Unmanaged<AppDelegate>.fromOpaque(userData)
                let appDelegate = unmanaged.takeUnretainedValue()
                appDelegate.performSelector(onMainThread: #selector(AppDelegate.startRegionCapture), with: nil, waitUntilDone: false)
            }
            return noErr
        }

        // Install handler once
        if eventHandlerRef == nil {
            let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventTypeSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
            if status != noErr { NSLog("[HotKey] Failed to install handler status=\(status)") }
        }

        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x56534254)), id: 1) // 'VSBT'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("[HotKey] Failed to register hotkey status=\(status)") }
    }

    private func unregisterHotKey() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk); hotKeyRef = nil }
        if let handler = eventHandlerRef { RemoveEventHandler(handler); eventHandlerRef = nil }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKey()
    }
}

// MARK: - Preview + Diagnostics Helpers
private var previewWindow: NSWindow?

private extension AppDelegate {
    func showPreviewWindow(image: NSImage, info: String) {
        let contentSize = NSSize(width: 260, height: 260)
        if previewWindow == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                             styleMask: [.titled, .closable, .utilityWindow],
                             backing: .buffered,
                             defer: false)
            w.title = "Last Capture"
            w.isReleasedWhenClosed = false
            previewWindow = w
        }

        let scaled = thumbnail(of: image, max: 220)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))

        let imageView = NSImageView(frame: NSRect(x: 20, y: 60, width: 220, height: 160))
        imageView.image = scaled
        imageView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(imageView)

        let label = NSTextField(labelWithString: info)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 20, width: 220, height: 30)
        container.addSubview(label)

        previewWindow?.contentView = container
        previewWindow?.center()
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func thumbnail(of image: NSImage, max: CGFloat) -> NSImage {
        let ratio = min(max / image.size.width, max / image.size.height)
        let target = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    func approximateVariance(of image: NSImage) -> Double {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var samples: [Double] = []
        for y in 0..<3 {
            for x in 0..<3 {
                let px = Int(Double(rep.pixelsWide - 1) * (Double(x) / 2.0))
                let py = Int(Double(rep.pixelsHigh - 1) * (Double(y) / 2.0))
                guard let color = rep.colorAt(x: px, y: py) else { continue }
                let r = Double(color.redComponent)
                let g = Double(color.greenComponent)
                let b = Double(color.blueComponent)
                samples.append((r + g + b) / 3.0)
            }
        }
        guard !samples.isEmpty else { return 0 }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(samples.count)
        return variance
    }
}
