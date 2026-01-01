import Cocoa

// MARK: - Toolbar View
protocol MarkupToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: MarkupTool)
    func toolbarDidSelectColor(_ color: NSColor)
}

// MARK: - Thickness Preview View

class ThicknessPreviewView: NSView {
    private let thickness: CGFloat
    
    init(thickness: CGFloat) {
        self.thickness = thickness
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        context.setStrokeColor(NSColor.labelColor.cgColor)
        context.setLineWidth(thickness)
        context.setLineCap(.round)
        
        let y = bounds.midY
        let startX = bounds.minX + 4
        let endX = bounds.maxX - 4
        
        context.move(to: CGPoint(x: startX, y: y))
        context.addLine(to: CGPoint(x: endX, y: y))
        context.strokePath()
    }
}

final class TitleBarToolbarView: NSView {
    weak var delegate: MarkupToolbarDelegate?
    
    private var selectedTool: MarkupTool = .arrow  // Match the controller's default
    private var toolButtons: [MarkupTool: NSButton] = [:]
    private var thicknessButton: NSButton!
    private var colorButton: NSButton!
    private var activeMenu: NSMenu?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        // CRITICAL: Disable autoresizing mask constraints FIRST
        translatesAutoresizingMaskIntoConstraints = false
        
        setupToolbar()
        setupAppearanceObserver()
        
        // Force layout after setup
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAppearanceObserver() {
        // Listen for system appearance changes using the app's notification
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    @objc private func appearanceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAppearance()
        }
    }
    
    private func setupToolbar() {
        wantsLayer = true
        updateToolbarBackground()
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.alignment = .centerY
        stackView.distribution = .fillProportionally
        
        // CRITICAL: Disable autoresizing mask constraints on stack view too
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add tool buttons
        for tool in MarkupTool.allCases {
            let button = createToolButton(for: tool)
            toolButtons[tool] = button
            stackView.addArrangedSubview(button)
        }
        
        // Add separator
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(separator)
        
        // Add line thickness picker button
        thicknessButton = createThicknessButton()
        stackView.addArrangedSubview(thicknessButton)
        
        // Add color picker button
        colorButton = createColorButton()
        stackView.addArrangedSubview(colorButton)
        
        // Add stack view to toolbar
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), // Add trailing padding to avoid rounded corner
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Select arrow tool by default instead of selection tool
        selectedTool = .arrow
        updateToolSelection()
        updateThicknessButton()
        updateColorButton()
    }
    
    override var intrinsicContentSize: NSSize {
        // Calculate the actual size needed for the toolbar
        // Each tool button (7): 40pt wide
        // Separator: 1pt wide
        // Thickness button: 40pt wide
        // Color button: 40pt wide
        // Spacing between items: 8pt each (8 spaces total: 7 tools + 1 separator + thickness + color = 9 items - 1 = 8 spaces)
        // Leading padding: 12pt
        // Trailing padding: 16pt (for rounded corner clearance)
        let totalWidth = (7 * 40) + 1 + 40 + 40 + (8 * 8) + 12 + 16
        let size = NSSize(width: CGFloat(totalWidth), height: 32)
        print("DEBUG: TitleBarToolbarView intrinsicContentSize calculated as: \(size)")
        return size
    }
    
    private func updateToolbarBackground() {
        // For title bar accessories, use transparent background to let the title bar handle the appearance
        // This ensures proper dark mode support as the title bar itself adapts to the system theme
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    private func updateAppearance() {
        updateToolbarBackground()
        updateToolSelection()
        updateThicknessButton()
        updateColorButton()
        
        // Update thickness and color button appearance
        updateThicknessButtonAppearance(thicknessButton)
        updateColorButtonAppearance(colorButton)
        
        // Update separator color - find the separator view in the stack view
        if let stackView = subviews.first as? NSStackView {
            for subview in stackView.arrangedSubviews {
                if subview.widthAnchor.constraint(equalToConstant: 1).isActive {
                    subview.layer?.backgroundColor = NSColor.separatorColor.cgColor
                    break
                }
            }
        }
    }
    
    private func createToolButton(for tool: MarkupTool) -> NSButton {
        let button = NSButton()
        
        // Set the icon with fallback
        if let image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.displayName) {
            button.image = image
        } else {
            // Fallback to text if system symbol fails
            button.title = tool.displayName
        }
        
        // Set tooltip with keyboard shortcut
        button.toolTip = tool.displayNameWithShortcut
        
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .texturedSquare  // Use textured square for title bar compatibility
        button.isBordered = false
        button.setButtonType(.toggle)
        button.target = self
        button.action = #selector(toolButtonPressed(_:))
        button.tag = MarkupTool.allCases.firstIndex(of: tool) ?? 0
        
        // Ensure button has proper sizing
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        // Style the button better with clear visual states
        button.imagePosition = .imageOnly
        button.isBordered = false  // Keep borderless for transparent title bar style
        
        // Add transparent background styling for title bar
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 4
        
        return button
    }
    
    @objc private func toolButtonPressed(_ sender: NSButton) {
        let toolIndex = sender.tag
        guard toolIndex < MarkupTool.allCases.count else { return }
        
        selectedTool = MarkupTool.allCases[toolIndex]
        updateToolSelection()
        delegate?.toolbarDidSelectTool(selectedTool)
    }
    
    private func updateToolSelection() {
        for (tool, button) in toolButtons {
            let isSelected = (tool == selectedTool)
            button.state = isSelected ? .on : .off
            
            // Use adaptive colors for better dark mode support
            if isSelected {
                button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                // Use white text on the accent color, which works in both light and dark mode
                button.contentTintColor = NSColor.white
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
                // Use labelColor which automatically adapts to light/dark mode
                button.contentTintColor = NSColor.labelColor
            }
        }
    }
    
    private func createThicknessButton() -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .texturedSquare  // Use textured square for title bar compatibility
        button.isBordered = false  // Remove border for transparent title bar style
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(thicknessButtonPressed(_:))
        button.toolTip = "Line Thickness"
        button.isEnabled = true  // Explicitly enable the button
        
        // Ensure AutoLayout works properly
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Set button size
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        // Style the button according to macOS HIG for title bar accessories
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.borderWidth = 0  // No border for title bar style
        updateThicknessButtonAppearance(button)
        
        return button
    }
    
    private func updateThicknessButtonAppearance(_ button: NSButton) {
        // Follow macOS HIG for title bar accessories - transparent background
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderColor = NSColor.clear.cgColor
        
        // Clear any existing subviews
        button.subviews.removeAll()
        
        // Add thickness preview line
        let currentThickness = MarkupLineThicknessManager.shared.currentThickness
        let lineView = ThicknessPreviewView(thickness: currentThickness)
        lineView.frame = NSRect(x: 8, y: (button.frame.height - 8) / 2, width: button.frame.width - 16, height: 8)
        button.addSubview(lineView)
    }
    
    private func createColorButton() -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .texturedSquare  // Use textured square for title bar compatibility
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(colorButtonPressed(_:))
        button.toolTip = "Choose Color"
        button.isEnabled = true  // Explicitly enable the button
        
        // Ensure AutoLayout works properly
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Set button size - make it smaller and more rectangular
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Style the button according to macOS HIG for title bar accessories
        button.wantsLayer = true
        button.layer?.borderWidth = 0  // No border for title bar style
        updateColorButtonAppearance(button)
        
        return button
    }
    
    private func updateColorButtonAppearance(_ button: NSButton) {
        // Follow macOS HIG for title bar accessories - transparent background
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 6  // Smaller corner radius for rounded rectangle shape
        
        // Set up hover effects
        button.layer?.masksToBounds = false
        
        // The color preview will be handled by updateColorButton method
    }
    
    @objc private func thicknessButtonPressed(_ sender: NSButton) {
        showThicknessMenu(from: sender)
    }
    
    private func showThicknessMenu(from button: NSButton) {
        let menu = NSMenu()
        activeMenu = menu
        
        for thickness in MarkupLineThicknessManager.shared.availableThicknesses {
            let item = NSMenuItem()
            
            // Create a custom view that shows the line thickness visually
            let menuItemView = createThicknessMenuItemView(thickness: thickness)
            item.view = menuItemView
            
            // Add checkmark for current thickness
            if thickness == MarkupLineThicknessManager.shared.currentThickness {
                item.state = .on
            }
            
            menu.addItem(item)
        }
        
        // Show menu below the button
        let buttonFrame = button.frame
        let menuLocation = NSPoint(x: buttonFrame.minX, y: buttonFrame.minY)
        menu.popUp(positioning: nil, at: menuLocation, in: button.superview)
        
        activeMenu = nil
    }
    
    private func createThicknessMenuItemView(thickness: CGFloat) -> NSView {
        let containerView = NSView()
        containerView.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        
        // Create a button that covers the entire menu item area
        let button = NSButton()
        button.frame = containerView.bounds
        button.title = ""
        button.bezelStyle = .texturedSquare  // Use textured square for title bar compatibility
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.target = self
        button.action = #selector(thicknessMenuItemSelected(_:))
        button.tag = Int(thickness * 10) // Store thickness as tag (e.g., 20 for 2.0pt)
        
        // Create a custom view that draws the line thickness
        let lineView = ThicknessPreviewView(thickness: thickness)
        lineView.frame = NSRect(x: 8, y: 6, width: 80, height: 12)
        
        // Add label with point size using adaptive text color
        let label = NSTextField(labelWithString: "\(Int(thickness))pt")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.labelColor  // Use labelColor for better dark mode support
        label.frame = NSRect(x: 92, y: 4, width: 25, height: 16)
        
        // Add visual elements to the button
        button.addSubview(lineView)
        button.addSubview(label)
        
        containerView.addSubview(button)
        
        return containerView
    }
    
    @objc private func thicknessMenuItemSelected(_ sender: NSButton) {
        let thickness = CGFloat(sender.tag) / 10.0 // Convert back from tag (e.g., 20 -> 2.0)
        MarkupLineThicknessManager.shared.currentThickness = thickness
        updateThicknessButton()
        
        // Close the active menu
        activeMenu?.cancelTracking()
    }
    
    @objc private func colorButtonPressed(_ sender: NSButton) {
        // Create and show color picker
        let colorPanel = NSColorPanel.shared
        colorPanel.color = MarkupColorManager.shared.currentColor
        colorPanel.isContinuous = true // Enable continuous updates for real-time color changes
        
        // Remove any existing observer first to avoid duplicates
        NotificationCenter.default.removeObserver(
            self,
            name: NSColorPanel.colorDidChangeNotification,
            object: colorPanel
        )
        
        // Set up a notification observer for color changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelColorDidChange(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: colorPanel
        )
        
        colorPanel.makeKeyAndOrderFront(nil)
    }
    
    @objc private func colorPanelColorDidChange(_ notification: Notification) {
        guard let colorPanel = notification.object as? NSColorPanel else { return }
        let newColor = colorPanel.color
        delegate?.toolbarDidSelectColor(newColor)
        updateColorButton()
        
        // Don't remove observer here - let it continue listening for more color changes
        // Observer will be removed when the view controller is deallocated or when setting up a new color panel session
    }
    
    private func updateColorButton() {
        // Clear any existing color preview subviews
        colorButton.subviews.removeAll()
        
        // Create a color preview view with rounded corners
        let colorPreview = NSView()
        let currentColor = MarkupColorManager.shared.currentColor
        colorPreview.wantsLayer = true
        colorPreview.layer?.backgroundColor = currentColor.cgColor
        colorPreview.layer?.cornerRadius = 4
        colorPreview.layer?.borderWidth = 1
        colorPreview.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        
        // Position the color preview in the center of the button
        colorPreview.frame = NSRect(x: 4, y: 4, width: colorButton.frame.width - 8, height: colorButton.frame.height - 8)
        colorButton.addSubview(colorPreview)
    }
    
    private func updateThicknessButton() {
        // Update thickness button appearance
        updateThicknessButtonAppearance(thicknessButton)
    }
    
    func selectTool(_ tool: MarkupTool) {
        selectedTool = tool
        updateToolSelection()
    }
    
    func updateColor(_ color: NSColor) {
        updateColorButton()
    }
    
    func updateThickness(_ thickness: CGFloat) {
        updateThicknessButton()
    }
}
