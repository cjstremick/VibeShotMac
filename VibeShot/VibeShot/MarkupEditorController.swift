import Cocoa
import SwiftUI

/// Main markup editor window controller
final class MarkupEditorController: NSWindowController {
    private let baseImage: NSImage
    private var markupElements: [MarkupElement] = []
    private var currentTool: MarkupTool = .arrow  // Start with arrow tool selected
    private var selectedElement: MarkupElement?
    
    private var canvasView: MarkupCanvasView!
    private var toolbarView: MarkupToolbarView!
    
    init(baseImage: NSImage) {
        self.baseImage = baseImage
        
        // Create views first
        self.canvasView = MarkupCanvasView(baseImage: baseImage)
        self.toolbarView = MarkupToolbarView()
        
        // Create window sized to fit image exactly, plus toolbar
        let imageSize = baseImage.size
        let toolbarHeight: CGFloat = 44
        let windowSize = NSSize(width: imageSize.width, height: imageSize.height + toolbarHeight)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        // Set delegates immediately after creation
        canvasView.delegate = self
        toolbarView.delegate = self
        
        setupWindow()
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "VibeShot Editor"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Don't set first responder here - it will be set after layout is complete
    }
    
    private func setupLayout() {
        guard let window = window else { return }
        
        let containerView = NSView()
        
        // Add toolbar at top
        containerView.addSubview(toolbarView)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Add canvas below toolbar
        containerView.addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        window.contentView = containerView
        
        // Ensure delegate is properly set after layout
        canvasView.delegate = self
        toolbarView.delegate = self
        
        print("🔗 Delegates set - Canvas delegate: \(canvasView.delegate != nil), Toolbar delegate: \(toolbarView.delegate != nil)")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Set first responder after the window is shown to avoid layout recursion
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.canvasView)
        }
    }
}

// MARK: - MarkupToolbarDelegate
extension MarkupEditorController: MarkupToolbarDelegate {
    func toolbarDidSelectTool(_ tool: MarkupTool) {
        currentTool = tool
        selectedElement?.isSelected = false
        selectedElement = nil
        
        // Communicate the tool change to the canvas
        canvasView.setCurrentTool(tool)
        canvasView.needsDisplay = true
    }
}

// MARK: - MarkupCanvasDelegate
extension MarkupEditorController: MarkupCanvasDelegate {
    func canvasDidStartDrawing(at point: CGPoint) {
        switch currentTool {
        case .selection:
            handleSelectionAt(point)
        case .arrow:
            // Will handle in canvasDidFinishDrawing
            break
        }
    }
    
    func canvasDidFinishDrawing(from startPoint: CGPoint, to endPoint: CGPoint) {
        switch currentTool {
        case .selection:
            break // Already handled in start
        case .arrow:
            // Calculate the distance of the arrow
            let distance = sqrt(pow(endPoint.x - startPoint.x, 2) + pow(endPoint.y - startPoint.y, 2))
            
            // Skip creating arrow if it's too short (likely accidental click or very short drag)
            let minimumArrowLength: CGFloat = 30.0  // About the size of the arrowhead
            guard distance >= minimumArrowLength else {
                return
            }
            
            let arrow = ArrowElement(startPoint: startPoint, endPoint: endPoint)
            markupElements.append(arrow)
            
            // Don't automatically select the new arrow - let user explicitly select if needed
            
            // Update the canvas view's elements
            canvasView.markupElements = markupElements
            canvasView.needsDisplay = true
        }
    }
    
    func canvasDidReceiveKeyDown(with event: NSEvent) {
        if event.keyCode == 51 { // Delete key
            deleteSelectedElement()
        } else if event.keyCode == 8 && event.modifierFlags.contains(.command) { // Cmd+C
            copyCompositeToClipboard()
        } else if event.keyCode == 13 && event.modifierFlags.contains(.command) { // Cmd+W
            window?.close()
        }
    }
    
    private func handleSelectionAt(_ point: CGPoint) {
        selectedElement?.isSelected = false
        selectedElement = nil
        
        // Find topmost element at point (reverse order for topmost)
        for element in markupElements.reversed() {
            if element.contains(point: point) {
                selectedElement = element
                element.isSelected = true
                break
            }
        }
        
        canvasView.needsDisplay = true
    }
    
    private func deleteSelectedElement() {
        // Delete all selected elements (supports multiple selection from rectangle selection)
        let selectedElements = markupElements.filter { $0.isSelected }
        
        if !selectedElements.isEmpty {
            markupElements.removeAll { element in
                selectedElements.contains { $0.id == element.id }
            }
            selectedElement = nil
            canvasView.markupElements = markupElements
            canvasView.needsDisplay = true
        }
    }
    
    private func copyCompositeToClipboard() {
        let composite = createCompositeImage()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([composite])
    }
    
    private func createCompositeImage() -> NSImage {
        let size = baseImage.size
        let composite = NSImage(size: size)
        
        composite.lockFocus()
        
        // Draw base image first in the normal coordinate system
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        // Get the current graphics context and flip it only for markup elements
        guard let context = NSGraphicsContext.current?.cgContext else {
            composite.unlockFocus()
            return composite
        }
        
        // Save the current state before transformation
        context.saveGState()
        
        // Flip the coordinate system to match the canvas view (top-left origin) for markup elements only
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Draw markup elements with flipped coordinates
        for element in markupElements {
            element.draw(in: context)
        }
        
        // Restore the original coordinate system
        context.restoreGState()
        
        composite.unlockFocus()
        return composite
    }
}

// MARK: - Canvas View
protocol MarkupCanvasDelegate: AnyObject {
    func canvasDidStartDrawing(at point: CGPoint)
    func canvasDidFinishDrawing(from startPoint: CGPoint, to endPoint: CGPoint)
    func canvasDidReceiveKeyDown(with event: NSEvent)
}

final class MarkupCanvasView: NSView {
    weak var delegate: MarkupCanvasDelegate?
    
    private let baseImage: NSImage
    var markupElements: [MarkupElement] = [] {
        didSet {
            needsDisplay = true
        }
    }
    
    private var dragStartPoint: CGPoint?
    private var currentDragPoint: CGPoint?
    private var isDrawing = false
    private var currentTool: MarkupTool = .arrow
    
    // Selection-specific properties
    private var selectionRect: CGRect?
    
    init(baseImage: NSImage) {
        self.baseImage = baseImage
        super.init(frame: NSRect(origin: .zero, size: baseImage.size))
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setCurrentTool(_ tool: MarkupTool) {
        currentTool = tool
        needsDisplay = true
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Enable mouse tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove old tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        // Add new tracking area with current bounds
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override var isFlipped: Bool {
        return true  // Use top-left origin coordinate system
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        
        // Draw base image
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        baseImage.draw(in: imageRect)
        
        // Draw all markup elements
        for element in markupElements {
            element.draw(in: context)
        }
        
        // Draw preview based on current tool
        if isDrawing, let startPoint = dragStartPoint, let endPoint = currentDragPoint {
            switch currentTool {
            case .arrow:
                drawPreviewArrow(from: startPoint, to: endPoint, in: context)
            case .selection:
                drawSelectionRect(from: startPoint, to: endPoint, in: context)
            }
        }
    }
    
    private func drawPreviewArrow(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let color = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 0.7) // Semi-transparent preview
        let lineWidth: CGFloat = 6.0
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate arrow geometry - increased arrowhead size to match final arrows
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = lineWidth * 5.0  // Doubled from 2.5 to 5.0
        
        // Calculate where the line should end (closer to the arrowhead tip for better connection)
        let lineEndPoint = CGPoint(
            x: endPoint.x - arrowLength * 0.6 * cos(angle),  // Reduced from full length to 60%
            y: endPoint.y - arrowLength * 0.6 * sin(angle)
        )
        
        // Draw the line (shortened to not extend past arrowhead)
        context.move(to: startPoint)
        context.addLine(to: lineEndPoint)
        context.strokePath()
        
        // Draw arrowhead
        let arrowAngle: CGFloat = .pi / 6 // 30 degrees
        
        let arrowPoint1 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        )
        
        let arrowPoint2 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        )
        
        context.setFillColor(color.cgColor)
        context.move(to: endPoint)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
        
        context.restoreGState()
    }
    
    private func drawSelectionRect(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        // Draw selection rectangle
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        
        context.fill(rect)
        context.stroke(rect)
        
        context.restoreGState()
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStartPoint = point
        currentDragPoint = point
        isDrawing = true
        selectionRect = nil
        delegate?.canvasDidStartDrawing(at: point)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        currentDragPoint = convert(event.locationInWindow, from: nil)
        
        // Update selection rect for selection tool
        if currentTool == .selection, let startPoint = dragStartPoint, let endPoint = currentDragPoint {
            selectionRect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
        }
        
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDrawing, let startPoint = dragStartPoint else {
            return
        }
        
        let endPoint = convert(event.locationInWindow, from: nil)
        isDrawing = false
        dragStartPoint = nil
        currentDragPoint = nil
        
        // Handle selection rectangle if we were dragging
        if currentTool == .selection && selectionRect != nil {
            handleRectangleSelection()
        }
        
        selectionRect = nil
        delegate?.canvasDidFinishDrawing(from: startPoint, to: endPoint)
        needsDisplay = true
    }
    
    private func handleRectangleSelection() {
        guard let rect = selectionRect else { return }
        
        // Clear previous selections
        for element in markupElements {
            element.isSelected = false
        }
        
        // Select elements that intersect with the selection rectangle
        for element in markupElements {
            if element.bounds.intersects(rect) {
                element.isSelected = true
            }
        }
        
        needsDisplay = true
    }
    
    // MARK: - Keyboard Events
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point)
    }
    
    override func keyDown(with event: NSEvent) {
        delegate?.canvasDidReceiveKeyDown(with: event)
    }
}

// MARK: - Toolbar View
protocol MarkupToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: MarkupTool)
}

final class MarkupToolbarView: NSView {
    weak var delegate: MarkupToolbarDelegate?
    
    private var selectedTool: MarkupTool = .arrow  // Match the controller's default
    private var toolButtons: [MarkupTool: NSButton] = [:]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupToolbar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupToolbar() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.alignment = .centerY
        stackView.distribution = .fillProportionally
        
        // Add tool buttons only - no copy button
        for tool in MarkupTool.allCases {
            let button = createToolButton(for: tool)
            toolButtons[tool] = button
            stackView.addArrangedSubview(button)
        }
        
        // Add stack view to toolbar
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Select arrow tool by default instead of selection tool
        selectedTool = .arrow
        updateToolSelection()
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
        
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.setButtonType(.toggle)
        button.target = self
        button.action = #selector(toolButtonPressed(_:))
        button.tag = MarkupTool.allCases.firstIndex(of: tool) ?? 0
        
        // Set tooltip for better UX
        button.toolTip = tool.displayName
        
        // Ensure button has proper sizing
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        // Style the button better with clear visual states
        button.imagePosition = .imageOnly
        button.isBordered = true
        
        // Add custom styling for better visual feedback
        button.wantsLayer = true
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
            
            // Custom visual styling for selected state
            if isSelected {
                button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                button.contentTintColor = NSColor.white
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
                button.contentTintColor = NSColor.controlTextColor
            }
        }
    }
}
