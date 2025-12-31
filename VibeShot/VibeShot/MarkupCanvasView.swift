import Cocoa

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
    func canvasDidFinishCrop(rect: CGRect)
    func canvasDidReceiveKeyDown(with event: NSEvent)
    func canvasDidUpdateElements(_ elements: [any MarkupElement])
    func canvasDidSelectElement(_ element: any MarkupElement)
    var selectedElement: (any MarkupElement)? { get }
}

final class MarkupCanvasView: NSView {
    weak var delegate: MarkupCanvasDelegate?
    
    var image: NSImage {
        didSet {
            frame.size = image.size
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var markupElements: [any MarkupElement] = [] {
        didSet {
            needsDisplay = true
        }
    }
    
    override var intrinsicContentSize: NSSize {
        return image.size
    }
    
    private var dragStartPoint: CGPoint?
    private var currentDragPoint: CGPoint?
    private var isDrawing = false
    private var currentTool: MarkupTool = .arrow
    
    // Selection-specific properties
    private var selectionRect: CGRect?
    
    // Crop-specific properties
    var cropSelectionRect: CGRect?
    
    // Text editing properties
    private var currentTextElement: TextElement?
    var textView: MarkupTextView?
    private var scrollView: NSScrollView?
    
    init(baseImage: NSImage) {
        self.image = baseImage
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
    
    /// Clamps a point to stay within the image bounds
    private func clampToImageBounds(_ point: CGPoint) -> CGPoint {
        let imageRect = NSRect(origin: .zero, size: image.size)
        return CGPoint(
            x: max(0, min(point.x, imageRect.maxX)),
            y: max(0, min(point.y, imageRect.maxY))
        )
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
        let imageRect = NSRect(origin: .zero, size: image.size)
        image.draw(in: imageRect)
        
        // Draw all markup elements
        for element in markupElements {
            // Skip drawing the element being moved to avoid showing it in original position
            if isDrawing && currentTool == .move && delegate?.selectedElement === element {
                continue
            }
            element.draw(in: context)
        }
        
        // Draw preview based on current tool
        if isDrawing, let startPoint = dragStartPoint, let endPoint = currentDragPoint {
            switch currentTool {
            case .arrow:
                drawPreviewArrow(from: startPoint, to: endPoint, in: context)
            case .selection:
                drawSelectionRect(from: startPoint, to: endPoint, in: context)
            case .move:
                // For move tool, show element being dragged at new position
                drawMovePreview(from: startPoint, to: endPoint, in: context)
            case .rectangle:
                drawRectanglePreview(from: startPoint, to: endPoint, in: context)
            case .stepCounter:
                // No preview needed for step counter (instant click action)
                break
            case .text:
                // No preview needed for text (instant click action)
                break
            case .blur:
                drawBlurPreview(from: startPoint, to: endPoint, in: context)
            case .crop:
                // Crop preview is handled separately because it persists after drag
                break
            }
        }
        
        // Draw crop overlay if active
        if let cropRect = cropSelectionRect {
            drawCropOverlay(rect: cropRect, in: context)
        }
    }
    
    private func drawCropOverlay(rect: CGRect, in context: CGContext) {
        context.saveGState()
        
        // Use clipping to create a "hole" in the overlay
        // This ensures the underlying image is fully visible in the crop area
        // while the outside area is dimmed
        
        // 1. Add the full bounds rectangle
        context.addRect(bounds)
        
        // 2. Add the crop rectangle (the hole)
        context.addRect(rect)
        
        // 3. Clip using Even-Odd rule (EOClip)
        // This clips to the region that is inside the bounds but OUTSIDE the crop rect
        context.clip(using: .evenOdd)
        
        // 4. Fill the clipped region (the outside area) with semi-transparent black
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fill(bounds)
        
        // Reset clipping for border and handles
        context.restoreGState()
        context.saveGState()
        
        // Draw border around crop rect
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [5, 5])
        context.stroke(rect)
        
        // Draw handles
        let handleSize: CGFloat = 10.0
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        
        context.setFillColor(NSColor.white.cgColor)
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize/2,
                y: corner.y - handleSize/2,
                width: handleSize,
                height: handleSize
            )
            context.fill(handleRect)
        }
        
        context.restoreGState()
    }
    
    private func drawPreviewArrow(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let color = MarkupColorManager.shared.currentColor.withAlphaComponent(0.7) // Semi-transparent preview
        let lineWidth = MarkupLineThicknessManager.shared.currentThickness
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate arrow geometry - increased arrowhead size to match final arrows
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = lineWidth * 5.0  // Scale arrowhead with line thickness
        
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
        let lineWidth = MarkupLineThicknessManager.shared.currentThickness
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
    
    private func drawBlurPreview(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        context.saveGState()
        
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        // Draw a semi-transparent overlay to indicate blur area
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        
        context.fill(rect)
        context.stroke(rect)
        
        context.restoreGState()
    }
    
    private func drawMovePreview(from startPoint: CGPoint, to endPoint: CGPoint, in context: CGContext) {
        // Only show move preview if there's a selected element
        guard let selectedElement = delegate?.selectedElement else { return }
        
        // Calculate the movement delta
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        
        // Save the current state
        context.saveGState()
        
        // Draw at full opacity since this is the only version of the element shown
        context.setAlpha(1.0)
        
        // Translate to show the element at its new position
        context.translateBy(x: deltaX, y: deltaY)
        
        // Draw the element at the new position
        selectedElement.draw(in: context)
        
        context.restoreGState()
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let rawPoint = convert(event.locationInWindow, from: nil)
        let point = clampToImageBounds(rawPoint)
        dragStartPoint = point
        currentDragPoint = point
        isDrawing = true
        selectionRect = nil
        
        delegate?.canvasDidStartDrawing(at: point)
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let rawPoint = convert(event.locationInWindow, from: nil)
        currentDragPoint = clampToImageBounds(rawPoint)
        
        // Update selection rect for selection tool
        if currentTool == .selection, let startPoint = dragStartPoint, let endPoint = currentDragPoint {
            selectionRect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
        }
        
        // Update crop rect for crop tool
        if currentTool == .crop, let startPoint = dragStartPoint, let endPoint = currentDragPoint {
            cropSelectionRect = CGRect(
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
        
        let rawEndPoint = convert(event.locationInWindow, from: nil)
        let endPoint = clampToImageBounds(rawEndPoint)
        isDrawing = false
        dragStartPoint = nil
        currentDragPoint = nil
        
        // Handle selection rectangle if we were dragging
        if currentTool == .selection && selectionRect != nil {
            handleRectangleSelection()
        }
        
        // Handle crop immediately on mouse up
        if currentTool == .crop, let cropRect = cropSelectionRect {
            // Only crop if the rect has some size
            if cropRect.width > 5 && cropRect.height > 5 {
                delegate?.canvasDidFinishCrop(rect: cropRect)
            }
            // Clear the selection rect (controller will handle the actual crop)
            cropSelectionRect = nil
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
        var selectedElements: [any MarkupElement] = []
        for element in markupElements {
            if element.bounds.intersects(rect) {
                element.isSelected = true
                selectedElements.append(element)
            }
        }
        
        // Update the delegate with the selected element (if any)
        if let firstSelected = selectedElements.first {
            delegate?.canvasDidSelectElement(firstSelected)
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
