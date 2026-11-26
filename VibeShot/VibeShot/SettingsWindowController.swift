import AppKit

/// AppKit preferences window. SwiftUI only supplies the app entry point, so the
/// settings live in AppKit like the rest of the interface.
final class SettingsWindowController: NSWindowController {
    private let settings: RecordingSettings

    private let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let folderLabel = NSTextField(labelWithString: "")
    private let chooseFolderButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let revealFolderButton = NSButton(title: "Show", target: nil, action: nil)
    private let countdownPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pointerCheckbox = NSButton(checkboxWithTitle: "Show pointer, clicks and scrolling",
                                           target: nil, action: nil)

    private let countdownValues = [0, 3, 5, 10]

    init(settings: RecordingSettings = .shared) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "VibeShot Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Interface

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Recording")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        destinationPopup.addItems(withTitles: RecordingDestination.allCases.map(\.title))
        destinationPopup.target = self
        destinationPopup.action = #selector(destinationChanged)
        destinationPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        countdownPopup.addItems(withTitles: countdownValues.map { $0 == 0 ? "Off" : "\($0) seconds" })
        countdownPopup.target = self
        countdownPopup.action = #selector(countdownChanged)
        countdownPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        folderLabel.font = NSFont.systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder)
        chooseFolderButton.bezelStyle = .rounded

        revealFolderButton.target = self
        revealFolderButton.action = #selector(revealRecordingsFolder)
        revealFolderButton.bezelStyle = .rounded

        let folderRow = NSStackView(views: [folderLabel, chooseFolderButton, revealFolderButton])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = 8

        let countdownHint = NSTextField(labelWithString:
            "The countdown appears after you select a region, giving you time to arrange windows.")
        countdownHint.font = NSFont.systemFont(ofSize: 11)
        countdownHint.textColor = .secondaryLabelColor
        countdownHint.lineBreakMode = .byWordWrapping
        countdownHint.maximumNumberOfLines = 2

        let clipboardHint = NSTextField(labelWithString:
            "“Copy to clipboard” copies a file reference, so paste it into Finder, Mail, Messages or any app that accepts files.")
        clipboardHint.font = NSFont.systemFont(ofSize: 11)
        clipboardHint.textColor = .secondaryLabelColor
        clipboardHint.lineBreakMode = .byWordWrapping
        clipboardHint.maximumNumberOfLines = 3

        pointerCheckbox.target = self
        pointerCheckbox.action = #selector(pointerActivityChanged)

        let pointerHint = NSTextField(labelWithString:
            "Includes the real pointer shape plus click ripples and scroll arrows. macOS may ask for Accessibility/Input Monitoring permission the first time.")
        pointerHint.font = NSFont.systemFont(ofSize: 11)
        pointerHint.textColor = .secondaryLabelColor
        pointerHint.lineBreakMode = .byWordWrapping
        pointerHint.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            title,
            makeRow("When a recording finishes:", destinationPopup),
            folderRow,
            makeRow("Countdown before recording:", countdownPopup),
            countdownHint,
            clipboardHint,
            makeRow("Pointer & clicks:", pointerCheckbox),
            pointerHint
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            folderRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            countdownHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            clipboardHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pointerHint.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeRow(_ labelText: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: labelText)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func refresh() {
        destinationPopup.selectItem(at: RecordingDestination.allCases.firstIndex(of: settings.destination) ?? 0)
        countdownPopup.selectItem(at: countdownValues.firstIndex(of: settings.countdownSeconds) ?? 0)
        pointerCheckbox.state = settings.showPointerActivity ? .on : .off

        let folder = settings.folderURL()
        folderLabel.stringValue = folder?.path ?? "No folder chosen"
        let enabled = settings.destination == .folder
        chooseFolderButton.isEnabled = enabled
        revealFolderButton.isEnabled = true
        if let folder {
            folderLabel.toolTip = folder.path
        } else {
            folderLabel.toolTip = nil
        }
    }

    // MARK: - Actions

    @objc private func destinationChanged() {
        let index = destinationPopup.indexOfSelectedItem
        guard RecordingDestination.allCases.indices.contains(index) else { return }
        settings.destination = RecordingDestination.allCases[index]
        refresh()
    }

    @objc private func countdownChanged() {
        let index = countdownPopup.indexOfSelectedItem
        guard countdownValues.indices.contains(index) else { return }
        settings.countdownSeconds = countdownValues[index]
    }

    @objc private func pointerActivityChanged() {
        settings.showPointerActivity = pointerCheckbox.state == .on
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.setFolder(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the folder choice"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    @objc private func revealRecordingsFolder() {
        let directory = RecordingStorage.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}
