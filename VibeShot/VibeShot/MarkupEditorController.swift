import Cocoa
import SwiftUI

/// Main markup editor window controller
final class MarkupEditorController: NSWindowController {
    private let baseImage: NSImage
    private var markupElements: [any MarkupElement] = []
    private var currentTool: MarkupTool = .arrow  // Start with arrow tool selected
    private var selectedElement: (any MarkupElement)?
    
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
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(
            self,
            name: NSColorPanel.colorDidChangeNotification,
            object: NSColorPanel.shared
        )
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
        // Complete any active text editing before switching tools
        canvasView.endTextEditingIfActive()
        
        currentTool = tool
        // Deselect all elements when switching tools
        for element in markupElements {
            element.isSelected = false
        }
        selectedElement = nil
        
        // Communicate the tool change to the canvas
        canvasView.setCurrentTool(tool)
        canvasView.needsDisplay = true
    }
    
    func toolbarDidSelectColor(_ color: NSColor) {
        // Store the new color for future elements
        MarkupColorManager.shared.currentColor = color
        
        // No need to refresh canvas - existing elements keep their colors
        // Only new elements will use the new color
    }
}

// MARK: - MarkupCanvasDelegate
extension MarkupEditorController: MarkupCanvasDelegate {
    func canvasDidStartDrawing(at point: CGPoint) {
        switch currentTool {
        case .selection:
            handleSelectionAt(point)
        case .arrow, .rectangle:
            // Will handle in canvasDidFinishDrawing
            break
        case .stepCounter:
            // Handle step counter immediately on click
            handleStepCounterStamp(at: point)
        case .text:
            // Handle text editing immediately on click
            handleTextInput(at: point)
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
            
            let arrow = ArrowElement(startPoint: startPoint, endPoint: endPoint, color: MarkupColorManager.shared.currentColor)
            markupElements.append(arrow)
            
            // Don't automatically select the new arrow - let user explicitly select if needed
            
            // Update the canvas view's elements
            canvasView.markupElements = markupElements
            canvasView.needsDisplay = true
        case .rectangle:
            // Calculate minimum rectangle size
            let width = abs(endPoint.x - startPoint.x)
            let height = abs(endPoint.y - startPoint.y)
            let minimumSize: CGFloat = 20.0
            
            // Skip creating rectangle if it's too small
            guard width >= minimumSize && height >= minimumSize else {
                return
            }
            
            let rectangle = RectangleElement(startPoint: startPoint, endPoint: endPoint, color: MarkupColorManager.shared.currentColor)
            markupElements.append(rectangle)
            
            // Update the canvas view's elements
            canvasView.markupElements = markupElements
            canvasView.needsDisplay = true
        case .stepCounter:
            // Already handled in canvasDidStartDrawing
            break
        case .text:
            // Already handled in canvasDidStartDrawing
            break
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
    
    func canvasDidUpdateElements(_ elements: [any MarkupElement]) {
        markupElements = elements
    }
    
    private func handleSelectionAt(_ point: CGPoint) {
        // First deselect all elements
        for element in markupElements {
            element.isSelected = false
        }
        selectedElement = nil
        
        // Find topmost element at point (reverse order for topmost)
        for (_, element) in markupElements.reversed().enumerated() {
            if element.contains(point: point) {
                selectedElement = element
                element.isSelected = true
                break
            }
        }
        
        canvasView.needsDisplay = true
    }
    
    private func handleStepCounterStamp(at point: CGPoint) {
        // Calculate the next step number based on existing step counter elements
        let existingStepNumbers = markupElements.compactMap { element in
            return (element as? StepCounterElement)?.stepNumber
        }
        
        // Find the highest existing number and add 1
        let nextStepNumber = (existingStepNumbers.max() ?? 0) + 1
        
        // Create the new step counter element
        let stepCounter = StepCounterElement(centerPoint: point, stepNumber: nextStepNumber, color: MarkupColorManager.shared.currentColor)
        markupElements.append(stepCounter)
        
        // Update the canvas view's elements
        canvasView.markupElements = markupElements
        canvasView.needsDisplay = true
    }
    
    private func handleTextInput(at point: CGPoint) {
        // Start text editing at the clicked location
        canvasView.startTextEditing(at: point)
        // Note: Synchronization will happen after text editing is complete
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
        
        // Draw base image first
        baseImage.draw(in: NSRect(origin: .zero, size: size))
        
        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else {
            composite.unlockFocus()
            return composite
        }
        
        // Transform the coordinate system to match the flipped canvas view
        // The canvas uses isFlipped = true (top-left origin), but NSImage uses bottom-left origin
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        
        // Draw markup elements with the transformed coordinate system
        for element in markupElements {
            element.draw(in: context)
        }
        
        composite.unlockFocus()
        return composite
    }
}

// MARK: - Custom Text View for Cmd+Enter handling
class MarkupTextView: NSTextView {
    weak var markupDelegate: MarkupTextViewDelegate?
    
    override func keyDown(with event: NSEvent) {
        // Handle Cmd+Enter specifically
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { // Enter key with Cmd
            markupDelegate?.textViewDidReceiveCommandEnter()
            return
        }
        
        // Handle Escape key to cancel editing
        if event.keyCode == 53 { // Escape key
            markupDelegate?.textViewDidReceiveEscape()
            return
        }
        
        // Let the parent handle all other keys
        super.keyDown(with: event)
    }
}

protocol MarkupTextViewDelegate: AnyObject {
    func textViewDidReceiveCommandEnter()
    func textViewDidReceiveEscape()
}

// MARK: - Canvas View
protocol MarkupCanvasDelegate: AnyObject {
    func canvasDidStartDrawing(at point: CGPoint)
    func canvasDidFinishDrawing(from startPoint: CGPoint, to endPoint: CGPoint)
    func canvasDidReceiveKeyDown(with event: NSEvent)
    func canvasDidUpdateElements(_ elements: [any MarkupElement])
}

final class MarkupCanvasView: NSView {
    weak var delegate: MarkupCanvasDelegate?
    
    private let baseImage: NSImage
    var markupElements: [any MarkupElement] = [] {
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
    
    // Text editing properties
    private var currentTextElement: TextElement?
    private var textView: MarkupTextView?
    private var scrollView: NSScrollView?
    
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
            case .rectangle:
                drawRectanglePreview(from: startPoint, to: endPoint, in: context)
            case .stepCounter:
                // No preview needed for step counter (instant click action)
                break
            case .text:
                // No preview needed for text (instant click action)
                break
            }
        }
    }
    
    private func drawPreviewArrow(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let color = MarkupColorManager.shared.currentColor.withAlphaComponent(0.7) // Semi-transparent preview
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
    
    private func drawRectanglePreview(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        let color = MarkupColorManager.shared.currentColor.withAlphaComponent(0.7) // Semi-transparent preview using same color as arrows
        let lineWidth: CGFloat = 6.0
        let cornerRadius: CGFloat = 8.0
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw rounded rectangle preview
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
        
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
    
    // MARK: - Text Editing
    func startTextEditing(at point: CGPoint) {
        
        // If we're in selection mode, don't start text editing - let selection handle it
        if currentTool == .selection {
            return
        }
        
        // Don't end existing text editing if we're clicking in the same area
        if let existingTextView = textView, existingTextView.frame.contains(point) {
            return
        }
        
        // End any existing text editing
        endTextEditing()
        
        // Check if we clicked on an existing text element
        for element in markupElements.reversed() {
            if let textElement = element as? TextElement, textElement.contains(point: point) {
                // Edit existing text element
                editTextElement(textElement)
                return
            }
        }
        
        // Create new text element
        let textElement = TextElement(position: point, text: "", color: MarkupColorManager.shared.currentColor)
        markupElements.append(textElement)
        needsDisplay = true
        
        editTextElement(textElement)
    }
    
    func endTextEditingIfActive() {
        // Check if text editing is currently active
        if textView != nil || currentTextElement != nil {
            endTextEditing()
        }
    }
    
    private func editTextElement(_ textElement: TextElement) {
        currentTextElement = textElement
        textElement.isSelected = true
        textElement.isBeingEdited = true  // Hide the element while editing
        
        // Create text view immediately to avoid timing issues
        createTextViewForEditing(textElement)
        
        needsDisplay = true
    }
    
    private func createTextViewForEditing(_ textElement: TextElement) {
        
        // Ensure we clean up any existing text view first
        textView?.removeFromSuperview()
        scrollView?.removeFromSuperview()
        
        // Create and configure text view for auto-sizing
        let newTextView = MarkupTextView()
        newTextView.string = textElement.text.isEmpty ? "Type here..." : textElement.text
        newTextView.isEditable = true
        newTextView.isSelectable = true
        newTextView.drawsBackground = false  // Make background transparent
        newTextView.textColor = MarkupColorManager.shared.currentColor
        newTextView.font = NSFont.systemFont(ofSize: 18.0, weight: .medium)
        newTextView.delegate = self
        
        // Set custom delegate for Cmd+Enter handling
        newTextView.markupDelegate = self
        
        // Configure for auto-sizing without scroll view
        newTextView.isVerticallyResizable = true
        newTextView.isHorizontallyResizable = false
        newTextView.textContainer?.widthTracksTextView = true
        newTextView.textContainer?.containerSize = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        newTextView.maxSize = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        newTextView.minSize = CGSize(width: 200, height: 30)
        
        // Remove text container padding to avoid double spacing
        newTextView.textContainerInset = NSSize(width: 4, height: 4)
        newTextView.textContainer?.lineFragmentPadding = 0
        
        // Position and size the text view
        let bounds = textElement.bounds
        let initialFrame = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: max(bounds.width, 200),
            height: max(bounds.height, 30)
        )
        newTextView.frame = initialFrame
        
        // Remove the border - we don't need it with transparent background
        newTextView.wantsLayer = false
        
        addSubview(newTextView)
        self.textView = newTextView
        self.scrollView = nil // Not using scroll view anymore
        
        // Focus and select the text view content
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(newTextView)
            if textElement.text.isEmpty {
                newTextView.selectAll(nil) // Select placeholder text
            } else {
                newTextView.selectAll(nil) // Select existing text
            }
        }
    }
    
    private func endTextEditing() {
        endTextEditing(shouldCancel: false)
    }
    
    private func endTextEditing(shouldCancel: Bool) {
        guard let textView = textView,
              let textElement = currentTextElement else { return }
        
        if shouldCancel {
            // Cancel editing - always remove the text element
            markupElements.removeAll { $0.id == textElement.id }
        } else {
            // Normal completion - update the text element with the final text
            let finalText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if finalText.isEmpty {
                // Remove empty text elements
                markupElements.removeAll { $0.id == textElement.id }
            } else {
                textElement.updateText(finalText)
                textElement.isBeingEdited = false  // Show the element again
            }
        }
        
        // Clean up
        textView.removeFromSuperview()
        scrollView?.removeFromSuperview()
        self.textView = nil
        self.scrollView = nil
        currentTextElement?.isSelected = false
        currentTextElement?.isBeingEdited = false
        currentTextElement = nil
        
        needsDisplay = true
        
        // Notify delegate of updated elements
        delegate?.canvasDidUpdateElements(markupElements)
        
        // Return focus to canvas
        window?.makeFirstResponder(self)
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

// MARK: - Text View Delegate
extension MarkupCanvasView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // Auto-resize the text view to fit content
        guard let textView = self.textView else { return }
        
        // Calculate the size needed for the current text
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }
        
        // Force layout to get accurate measurements
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        
        // Calculate new size with padding
        let padding: CGFloat = 8
        let newWidth = max(usedRect.width + padding * 2, 200)
        let newHeight = max(usedRect.height + padding * 2, 30)
        
        // Update text view frame
        var frame = textView.frame
        frame.size.width = newWidth
        frame.size.height = newHeight
        textView.frame = frame
        
        // Update text container size
        textContainer.containerSize = CGSize(width: newWidth - padding, height: CGFloat.greatestFiniteMagnitude)
    }
    
    func textDidEndEditing(_ notification: Notification) {
        // Only end editing if it's not due to a command we're handling
        let reasonCode = notification.userInfo?["NSTextMovement"] as? Int
        if reasonCode == NSTextMovement.return.rawValue {
            // This was triggered by Enter key, don't end editing
            return
        }
        endTextEditing()
    }
    
    func textDidBeginEditing(_ notification: Notification) {
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Regular Enter - insert new line (let NSTextView handle it)
            return false // Let NSTextView handle the newline insertion
        }
        
        return false // Let NSTextView handle other commands
    }
}

// MARK: - MarkupTextViewDelegate
extension MarkupCanvasView: MarkupTextViewDelegate {
    func textViewDidReceiveCommandEnter() {
        endTextEditing()
    }
    
    func textViewDidReceiveEscape() {
        // Escape key handling to cancel text editing and remove the text element
        endTextEditing(shouldCancel: true)
    }
}

// MARK: - Toolbar View
protocol MarkupToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: MarkupTool)
    func toolbarDidSelectColor(_ color: NSColor)
}

final class MarkupToolbarView: NSView {
    weak var delegate: MarkupToolbarDelegate?
    
    private var selectedTool: MarkupTool = .arrow  // Match the controller's default
    private var toolButtons: [MarkupTool: NSButton] = [:]
    private var colorButton: NSButton!
    
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
        
        // Add color picker button
        colorButton = createColorButton()
        stackView.addArrangedSubview(colorButton)
        
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
        updateColorButton()
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
    
    private func createColorButton() -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(colorButtonPressed(_:))
        button.toolTip = "Choose Color"
        
        // Set button size
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        // Style the button
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.controlColor.cgColor
        
        return button
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
        let currentColor = MarkupColorManager.shared.currentColor
        colorButton.layer?.backgroundColor = currentColor.cgColor
        
        // Add a subtle border to make the color visible even for light colors
        colorButton.layer?.borderColor = NSColor.controlColor.cgColor
    }
}
