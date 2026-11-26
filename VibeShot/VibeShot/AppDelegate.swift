import Cocoa
import ScreenCaptureKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, CaptureOverlayDelegate {
    private enum CaptureMode { case screenshot, record }

    private var statusItem: NSStatusItem!
    private let captureService = QuickSCKitCapture()
    private var overlayController: CaptureOverlayController?
    private var overlayDisplay: NSScreen?
    private var fullScreenCapture: NSImage?
    private var hotKeyRef: EventHotKeyRef?
    private var recordHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var editors: [MarkupEditorController] = []
    private var captureInProgress = false
    private var captureMode: CaptureMode = .screenshot
    private var recorder: ScreenRecorder?
    private var recordingHUD: RecordingHUDController?
    private var pointerOverlay: PointerActivityOverlay?
    private var countdown: CountdownOverlayController?
    private var settingsWindow: SettingsWindowController?
    private var stopRecordingItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        removeExpiredShareFiles()
        removeExpiredRecordings()
        setupStatusBar()
        setupApplicationMenu()
        registerGlobalHotKey()
    }
    
    private func removeExpiredShareFiles() {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("VibeShot-") {
            let name = file.lastPathComponent
            let identifier = String(name.dropFirst("VibeShot-".count))
            let isShareFile = UUID(uuidString: identifier) != nil
            let isRecording = name.hasPrefix("VibeShot-Recording-")
            guard isShareFile || isRecording,
                  let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created < Date().addingTimeInterval(-86400) else { continue }
            try? manager.removeItem(at: file)
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "target", accessibilityDescription: "VibeShot")
        }
        
        let menu = NSMenu()
        
        // About at the top (Apple standard)
        menu.addItem(withTitle: "About VibeShot", action: #selector(showAbout), keyEquivalent: "")

        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")

        menu.addItem(.separator())
        
        // Main app functions
        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(startRegionCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.option, .control, .shift]
        menu.addItem(captureItem)

        let recordItem = NSMenuItem(title: "Record Region", action: #selector(startRecordingRegion), keyEquivalent: "r")
        recordItem.keyEquivalentModifierMask = [.option, .control, .shift]
        menu.addItem(recordItem)

        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ".")
        stopItem.isHidden = true
        stopRecordingItem = stopItem
        menu.addItem(stopItem)
        
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
    @objc private func startRegionCapture() { beginCapture(mode: .screenshot) }

    @objc private func startRecordingRegion() { beginCapture(mode: .record) }

    private func beginCapture(mode: CaptureMode) {
        // Pressing the capture/record shortcut during the countdown cancels it.
        if let countdown {
            countdown.cancel()
            self.countdown = nil
            return
        }
        guard !captureInProgress, overlayController == nil, recorder == nil else { return }
        captureMode = mode
        let mouseLoc = NSEvent.mouseLocation
        guard let display = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main else {
            return
        }
        captureInProgress = true
        overlayDisplay = display
        
        Task { @MainActor in
            defer { self.captureInProgress = false }
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
        let mode = captureMode
        captureMode = .screenshot

        guard let rect = rect, let display = overlayDisplay, let fullImage = fullScreenCapture else {
            overlayController = nil
            overlayDisplay = nil
            fullScreenCapture = nil
            return
        }
        
        overlayController = nil
        overlayDisplay = nil

        // A recording reuses the frozen overlay only to choose the region; the
        // still image itself is discarded once the live stream starts.
        if mode == .record {
            fullScreenCapture = nil
            beginRecordingFlow(region: rect, display: display)
            return
        }
        
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
            editors.append(editor)
            editor.onClose = { [weak self, weak editor] in
                guard let self else { return }
                self.editors.removeAll { $0 === editor }
                if self.editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
            NSApp.setActivationPolicy(.regular)
            editor.show()
        }
        
        fullScreenCapture = nil
    }
    
    private func crop(image: NSImage, to rect: CGRect) -> NSImage? {
        let topRect = CGRect(x: rect.minX, y: image.size.height - rect.maxY,
                             width: rect.width, height: rect.height)
        return try? CompositeRenderer.crop(image, topOriginRect: topRect)
    }

    // MARK: Recording

    private func beginRecordingFlow(region: CGRect, display: NSScreen) {
        // Show the dimmed surround and red border immediately so the selected
        // area is visible during the countdown too. The Stop control stays
        // hidden until capture actually starts.
        let hud = RecordingHUDController(region: region, display: display)
        hud.delegate = self
        hud.show()
        recordingHUD = hud

        let seconds = RecordingSettings.shared.countdownSeconds
        guard seconds > 0 else {
            startRecording(region: region, display: display)
            return
        }
        let countdown = CountdownOverlayController(region: region, display: display, seconds: seconds) { [weak self] in
            self?.countdown = nil
            self?.startRecording(region: region, display: display)
        }
        self.countdown = countdown
        countdown.begin()
    }

    private func startRecording(region: CGRect, display: NSScreen) {
        // Reuse the HUD shown during the countdown; otherwise create it before
        // the stream starts so there are windows to exclude from the capture.
        let hud: RecordingHUDController
        if let existing = recordingHUD {
            hud = existing
        } else {
            hud = RecordingHUDController(region: region, display: display)
            hud.delegate = self
            hud.show()
            recordingHUD = hud
        }
        hud.setStopControlVisible(true)

        let showPointer = RecordingSettings.shared.showPointerActivity
        if showPointer {
            let overlay = PointerActivityOverlay(region: region, display: display)
            overlay.show()
            pointerOverlay = overlay
        }

        let recorder = ScreenRecorder()
        recorder.onUnexpectedStop = { [weak self] result in
            self?.finishRecording(result)
        }
        self.recorder = recorder
        Task { @MainActor in
            do {
                try await recorder.start(region: region, on: display,
                                         showsCursor: showPointer,
                                         excludingWindowNumbers: hud.windowNumbers)
                self.setRecordingUIActive(true)
            } catch {
                self.recorder = nil
                self.recordingHUD?.close()
                self.recordingHUD = nil
                self.pointerOverlay?.close()
                self.pointerOverlay = nil
                self.setRecordingUIActive(false)
                self.showTransientAlert(title: "Recording Failed", text: error.localizedDescription)
            }
        }
    }

    @objc private func stopRecording() {
        guard let recorder else { return }
        // Clear the reference immediately so a second Stop click is ignored while
        // the first one finalizes the file. ScreenRecorder keeps itself alive
        // through the stream's completion, so finalizing still runs.
        self.recorder = nil
        recordingHUD?.close()
        recordingHUD = nil
        pointerOverlay?.close()
        pointerOverlay = nil
        setRecordingUIActive(false)
        recorder.stop { [weak self] result in
            self?.finishRecording(result)
        }
    }

    private func finishRecording(_ result: Result<URL, Error>) {
        recorder = nil
        recordingHUD?.close()
        recordingHUD = nil
        pointerOverlay?.close()
        pointerOverlay = nil
        setRecordingUIActive(false)
        switch result {
        case .success(let url):
            deliverRecording(url)
        case .failure(let error):
            showTransientAlert(title: "Recording Failed", text: error.localizedDescription)
        }
    }

    private func deliverRecording(_ temporaryURL: URL) {
        switch RecordingSettings.shared.destination {
        case .ask:
            presentRecordingSavePanel(for: temporaryURL)
        case .clipboard:
            copyRecordingToClipboard(temporaryURL)
        case .folder:
            guard let folder = RecordingSettings.shared.folderURL() else {
                presentRecordingSavePanel(for: temporaryURL)
                return
            }
            saveRecording(temporaryURL, toFolder: folder)
        }
    }

    private func saveRecording(_ temporaryURL: URL, toFolder folder: URL) {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let destination = RecordingStorage.uniqueDestination(in: folder,
                                                             name: RecordingSettings.recordingFileName())
        do {
            try copyRecording(from: temporaryURL, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            NSLog("[Recording] Save to folder failed: \(error)")
            recoverRecording(temporaryURL, error: error)
        }
    }

    private func presentRecordingSavePanel(for temporaryURL: URL) {
        // A menu-bar app has no window to sheet onto, so run the panel modally
        // and activate first; this is what actually brings it to the front.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = RecordingSettings.recordingFileName()
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return
        }
        do {
            try copyRecording(from: temporaryURL, to: url)
        } catch {
            NSLog("[Recording] Save panel write failed: \(error)")
            recoverRecording(temporaryURL, error: error)
        }
    }

    private func copyRecordingToClipboard(_ temporaryURL: URL) {
        do {
            try FileManager.default.createDirectory(at: RecordingStorage.directory,
                                                     withIntermediateDirectories: true)
            let destination = RecordingStorage.uniqueDestination(in: RecordingStorage.directory,
                                                                 name: RecordingSettings.recordingFileName())
            try copyRecording(from: temporaryURL, to: destination)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([destination as NSURL])
            NSSound(named: NSSound.Name("Glass"))?.play()
            statusItem.button?.toolTip = "Recording copied to clipboard"
        } catch {
            NSLog("[Recording] Clipboard copy failed: \(error)")
            presentRecordingSavePanel(for: temporaryURL)
        }
    }

    /// Copies the finished recording to `destination`, replacing any existing
    /// file and honoring security-scoped access for user-selected folders.
    private func copyRecording(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
            try? fileManager.removeItem(at: source)
        } catch {
            // Cross-volume or unusual providers: fall back to a move.
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    /// Last resort when a chosen destination cannot be written: keep the file in
    /// the app's own Recordings folder and reveal it so nothing is lost.
    private func recoverRecording(_ temporaryURL: URL, error: Error) {
        let fileManager = FileManager.default
        let directory = RecordingStorage.directory
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = RecordingStorage.uniqueDestination(in: directory,
                                                                 name: RecordingSettings.recordingFileName())
            try fileManager.copyItem(at: temporaryURL, to: destination)
            try? fileManager.removeItem(at: temporaryURL)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            showTransientAlert(
                title: "Recording Saved to the VibeShot Folder",
                text: "The chosen destination could not be written.\n\nThe recording was kept here:\n\(destination.path)\n\n\(error.localizedDescription)")
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([temporaryURL])
            showTransientAlert(
                title: "Recording Could Not Be Saved",
                text: "The file is still here:\n\(temporaryURL.path)\n\n\(error.localizedDescription)")
        }
    }

    private func removeExpiredRecordings() {
        let manager = FileManager.default
        let directory = RecordingStorage.directory
        guard let files = try? manager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < Date().addingTimeInterval(-7 * 86400) else { continue }
            try? manager.removeItem(at: file)
        }
    }

    private func setRecordingUIActive(_ active: Bool) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: active ? "record.circle.fill" : "target",
                                   accessibilityDescription: active ? "Recording" : "VibeShot")
            button.contentTintColor = active ? .systemRed : nil
            button.toolTip = active ? "Recording" : nil
        }
        stopRecordingItem?.isHidden = !active
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About VibeShot"
        
        // Add the app icon to the alert
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        alert.informativeText = """
VibeShot \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
A simple screenshot, recording and markup app made 100% with vibe coding.

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

    func applicationWillTerminate(_ notification: Notification) { unregisterHotKey() }

    func setupApplicationMenu() {
        let main = NSMenu()
        func section(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            menu.addItem(item)
        }
        let app = section("VibeShot")
        add(app, "About VibeShot", #selector(showAbout), target: self)
        add(app, "Settings…", #selector(showSettings), ",", target: self)
        app.addItem(.separator())
        add(app, "Hide VibeShot", #selector(NSApplication.hide(_:)), "h")
        add(app, "Quit VibeShot", #selector(quit), "q", target: self)
        let file = section("File")
        add(file, "Capture Region", #selector(startRegionCapture), target: self)
        add(file, "Record Region", #selector(startRecordingRegion), target: self)
        file.addItem(.separator())
        add(file, "Save…", #selector(MarkupEditorController.saveScreenshot(_:)), "s")
        add(file, "Print…", #selector(MarkupEditorController.printScreenshot(_:)), "p")
        add(file, "Share…", #selector(MarkupEditorController.shareScreenshot(_:)))
        add(file, "AirDrop…", #selector(MarkupEditorController.airDropScreenshot(_:)))
        file.addItem(.separator())
        add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        let edit = section("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "Z")
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Delete", #selector(NSText.delete(_:)))
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let tools = section("Tools")
        EditorMenus.populateTools(tools)
        NSApp.mainMenu = main
    }
    
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
        // Control + Option + Shift, shared by capture (S) and record (R).
        let modifiers: UInt32 = UInt32(optionKey | controlKey | shiftKey)

        var eventTypeSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if let userData = userData {
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                let action: Selector?
                switch hotKeyID.id {
                case 1: action = #selector(AppDelegate.startRegionCapture)
                case 2: action = #selector(AppDelegate.startRecordingRegion)
                default: action = nil
                }
                if let action {
                    appDelegate.performSelector(onMainThread: action, with: nil, waitUntilDone: false)
                }
            }
            return noErr
        }

        // Install handler once
        if eventHandlerRef == nil {
            let status = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventTypeSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
            if status != noErr { NSLog("[HotKey] Failed to install handler status=\(status)") }
        }

        let signature = OSType(UInt32(truncatingIfNeeded: 0x56534254)) // 'VSBT'
        let captureStatus = RegisterEventHotKey(UInt32(kVK_ANSI_S), modifiers,
            EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &hotKeyRef)
        if captureStatus != noErr { NSLog("[HotKey] Failed to register capture hotkey status=\(captureStatus)") }

        let recordStatus = RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers,
            EventHotKeyID(signature: signature, id: 2), GetApplicationEventTarget(), 0, &recordHotKeyRef)
        if recordStatus != noErr { NSLog("[HotKey] Failed to register record hotkey status=\(recordStatus)") }
    }
    
    private func unregisterHotKey() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk); hotKeyRef = nil }
        if let hk = recordHotKeyRef { UnregisterEventHotKey(hk); recordHotKeyRef = nil }
        if let handler = eventHandlerRef { RemoveEventHandler(handler); eventHandlerRef = nil }
    }
}

extension AppDelegate: RecordingHUDDelegate {
    func recordingHUDDidRequestStop(_ hud: RecordingHUDController) {
        stopRecording()
    }
}
