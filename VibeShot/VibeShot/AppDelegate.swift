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
    private var markupEditor: MarkupEditorController? // Add strong reference
    
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
        
        // Capture item
        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(startRegionCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.option, .control, .shift]
        menu.addItem(captureItem)
        
        menu.addItem(.separator())
        menu.addItem(withTitle: "About VibeShot", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "")
        
        menu.addItem(.separator())
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
                
                // Open markup editor and keep strong reference to prevent deallocation
                let editor = MarkupEditorController(baseImage: result.image)
                self.markupEditor = editor // Keep strong reference
                editor.show()
                
                NSLog("[RegionCapture] SUCCESS rect=\(NSStringFromRect(rect)) elapsedMs=\(Int(elapsed))")
            } catch {
                showTransientAlert(title: "Capture Failed", text: error.localizedDescription)
                NSLog("[RegionCapture] FAILURE: \(error)")
            }
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About VibeShot"
        alert.informativeText = """
VibeShot v1.0
A lightweight, fast screenshot & markup utility

Copyright © 2025. All rights reserved.

Attribution Placeholder:
• ScreenCaptureKit framework
• SwiftUI framework
• Additional dependencies TBD
"""
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func showDiagnostics() {
        let preflight = CGPreflightScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Diagnostics"
        alert.informativeText = """
Bundle: \(Bundle.main.bundleIdentifier ?? "N/A")
Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown")
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
}
