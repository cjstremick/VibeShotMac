import Cocoa
import ScreenCaptureKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, CaptureOverlayDelegate {
    private var statusItem: NSStatusItem!
    private let captureService = QuickSCKitCapture()
    private var overlayController: CaptureOverlayController?
    private var overlayDisplay: NSScreen?
    private var fullScreenCapture: NSImage?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var markupEditor: MarkupEditorController? // Add strong reference
    private var launchAtLoginItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        registerGlobalHotKey()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "target", accessibilityDescription: "VibeShot")
        }
        
        let menu = NSMenu()
        
        // About at the top (Apple standard)
        menu.addItem(withTitle: "About VibeShot", action: #selector(showAbout), keyEquivalent: "")
        
        menu.addItem(.separator())
        
        // Main app functions
        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(startRegionCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.option, .control, .shift]
        menu.addItem(captureItem)
        
        menu.addItem(.separator())
        
        // Launch at Login option
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = isLaunchAtLoginEnabled ? .on : .off
        launchAtLoginItem = launchItem
        menu.addItem(launchItem)
        
        menu.addItem(.separator())
        
        // Quit at the bottom (Apple standard)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }
    
    // MARK: Region Capture Flow
    @objc private func startRegionCapture() {
        guard overlayController == nil else { return }
        let mouseLoc = NSEvent.mouseLocation
        guard let display = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main else {
            return
        }
        overlayDisplay = display
        
        Task { @MainActor in
            do {
                // Capture full screen first (Freeze Frame)
                let result = try await captureService.capture(rect: display.frame, on: display)
                self.fullScreenCapture = result.image
                
                // Show overlay with the captured image
                let controller = CaptureOverlayController(display: display, image: result.image)
                controller.delegate = self
                self.overlayController = controller
                controller.begin()
            } catch QuickSCKitCapture.CaptureError.permissionPending {
                // System dialog was just shown - silently abort, user will retry after granting
                overlayDisplay = nil
            } catch QuickSCKitCapture.CaptureError.permissionDenied {
                // User needs to grant permission or previously denied
                showTransientAlert(
                    title: "Screen Recording Permission Required",
                    text: "VibeShot needs screen recording permission to capture screenshots.\n\nPlease go to System Settings → Privacy & Security → Screen Recording and enable VibeShot, then try again."
                )
                overlayDisplay = nil
            } catch {
                showTransientAlert(title: "Capture Failed", text: error.localizedDescription)
                NSLog("[RegionCapture] FAILURE: \(error)")
                overlayDisplay = nil
            }
        }
    }
    
    func overlayDidFinish(rect: CGRect?) {
        guard let rect = rect, let display = overlayDisplay, let fullImage = fullScreenCapture else {
            overlayController = nil
            overlayDisplay = nil
            fullScreenCapture = nil
            return
        }
        
        overlayController = nil
        overlayDisplay = nil
        
        // Calculate rect relative to display origin
        let localRect = CGRect(
            x: rect.origin.x - display.frame.origin.x,
            y: rect.origin.y - display.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        if let croppedImage = crop(image: fullImage, to: localRect) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([croppedImage])
            
            // Open markup editor and keep strong reference to prevent deallocation
            let editor = MarkupEditorController(baseImage: croppedImage)
            self.markupEditor = editor // Keep strong reference
            editor.show()
        }
        
        fullScreenCapture = nil
    }
    
    private func crop(image: NSImage, to rect: CGRect) -> NSImage? {
        let newImage = NSImage(size: rect.size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: rect.size), from: rect, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About VibeShot"
        
        // Add the app icon to the alert
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        alert.informativeText = """
VibeShot v1.0
A simple screenshot capture and markup app made 100% with vibe coding.

Copyright Cj Stremick
"""
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showTransientAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quit() { NSApp.terminate(nil) }
    
    // MARK: - Launch at Login
    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if isLaunchAtLoginEnabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
                launchAtLoginItem?.state = isLaunchAtLoginEnabled ? .on : .off
            } catch {
                showTransientAlert(title: "Launch at Login", text: "Failed to update login item: \(error.localizedDescription)")
            }
        } else {
            showTransientAlert(title: "Launch at Login", text: "This feature requires macOS 13 or later.")
        }
    }
    
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
}
