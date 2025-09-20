import Cocoa
import SwiftUI

/// Main markup editor window controller
final class MarkupEditorController: NSWindowController {
    private let baseImage: NSImage
    private var markupElements: [any MarkupElement] = []
    private var currentTool: MarkupTool = .arrow  // Start with arrow tool selected
    internal var selectedElement: (any MarkupElement)?
    
    // Move tool properties
    private var moveStartPoint: CGPoint?
    private var elementStartPosition: CGPoint?
    
    private var canvasView: MarkupCanvasView!
    private var titleBarToolbar: TitleBarToolbarView!
    
    // Minimum window width to ensure title bar toolbar doesn't get clipped
    private static let minimumWindowWidth: CGFloat = 700
    
    init(baseImage: NSImage) {
        print("DEBUG: MarkupEditorController init called")
        self.baseImage = baseImage
        
        // Create views first
        self.canvasView = MarkupCanvasView(baseImage: baseImage)
        self.titleBarToolbar = TitleBarToolbarView()
        
        // Create window with minimum width consideration
        let imageSize = baseImage.size
        
        // Ensure window is at least the minimum width for title bar toolbar
        let windowWidth = max(imageSize.width, Self.minimumWindowWidth)
        let windowSize = NSSize(width: windowWidth, height: imageSize.height)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        // Set delegates immediately after creation
        canvasView.delegate = self
        titleBarToolbar.delegate = self
        
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
        
        // Clean up distributed notification center observers
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    private func setupWindow() {
        print("DEBUG: setupWindow called")
        guard let window = window else { return }
        
        window.title = "VibeShot Editor"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Configure title bar toolbar
        configureTitleBarToolbar()
        
        // Don't set first responder here - it will be set after layout is complete
    }
    
    private func setupLayout() {
        guard let window = window else { return }
        
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        // Create canvas container for centering (toolbar is now in title bar)
        let canvasContainer = NSView()
        canvasContainer.wantsLayer = true
        
        containerView.addSubview(canvasContainer)
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Canvas container fills the entire window (no traditional toolbar)
        NSLayoutConstraint.activate([
            canvasContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            canvasContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvasContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Add canvas to the container
        canvasContainer.addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        
        let imageSize = baseImage.size
        
        if imageSize.width < Self.minimumWindowWidth {
            // Center the canvas when image is narrower than minimum width
            NSLayoutConstraint.activate([
                canvasView.centerXAnchor.constraint(equalTo: canvasContainer.centerXAnchor),
                canvasView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
                canvasView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
                canvasView.widthAnchor.constraint(equalToConstant: imageSize.width)
            ])
        } else {
            // Fill the container when image is wider than minimum width
            NSLayoutConstraint.activate([
                canvasView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
                canvasView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
                canvasView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
                canvasView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor)
            ])
        }
        
        window.contentView = containerView
        
        // Ensure delegate is properly set after layout
        canvasView.delegate = self
        
        // Set up appearance change observers for the container background
        setupContainerAppearanceObserver(for: containerView, canvasContainer: canvasContainer)
    }
    
    private func setupContainerAppearanceObserver(for containerView: NSView, canvasContainer: NSView) {
        // Listen for system appearance changes to update background colors
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak containerView, weak canvasContainer] _ in
            containerView?.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            canvasContainer?.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
    
    private func configureTitleBarToolbar() {
        guard let window = window else { 
            print("DEBUG: Window is nil in configureTitleBarToolbar")
            return 
        }
        
        print("DEBUG: Creating title bar toolbar")
        print("DEBUG: Toolbar frame: \(titleBarToolbar.frame)")
        print("DEBUG: Toolbar intrinsic size: \(titleBarToolbar.intrinsicContentSize)")
        
        // Enable layer for proper rendering
        titleBarToolbar.wantsLayer = true
        
        // CRITICAL: Ensure the toolbar has the correct frame based on intrinsic content size
        let intrinsicSize = titleBarToolbar.intrinsicContentSize
        titleBarToolbar.frame = NSRect(origin: .zero, size: intrinsicSize)
        
        // Create title bar accessory view controller
        let accessoryViewController = NSTitlebarAccessoryViewController()
        accessoryViewController.view = titleBarToolbar
        accessoryViewController.layoutAttribute = .trailing
        
        // Add the accessory view controller to the window
        window.addTitlebarAccessoryViewController(accessoryViewController)
        
        print("DEBUG: Title bar accessory view controller added")
        print("DEBUG: Window titlebar accessories count: \(window.titlebarAccessoryViewControllers.count)")
        print("DEBUG: Final toolbar frame: \(titleBarToolbar.frame)")
        
        // Initialize title bar toolbar state
        titleBarToolbar.updateColor(MarkupColorManager.shared.currentColor)
        titleBarToolbar.updateThickness(MarkupLineThicknessManager.shared.currentThickness)
        titleBarToolbar.selectTool(currentTool)
        
        print("DEBUG: Title bar toolbar configuration complete")
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
        
        // Update title bar toolbar selection
        titleBarToolbar.selectTool(tool)
        
        // Communicate the tool change to the canvas
        canvasView.setCurrentTool(tool)
        canvasView.needsDisplay = true
    }
    
    func toolbarDidSelectColor(_ color: NSColor) {
        // Store the new color for future elements
        MarkupColorManager.shared.currentColor = color
        
        // Update title bar toolbar
        titleBarToolbar.updateColor(color)
        
        // No need to refresh canvas - existing elements keep their colors
        // Only new elements will use the new color
    }
    
    func thicknessButtonClicked(_ sender: NSButton) {
        // This will be implemented to show thickness selection
        // For now, we'll handle it like the old toolbar
    }
    
    func colorButtonClicked(_ sender: NSButton) {
        // This will be implemented to show color selection
        // For now, we'll handle it like the old toolbar
    }
}

// MARK: - MarkupCanvasDelegate
extension MarkupEditorController: MarkupCanvasDelegate {
    func canvasDidStartDrawing(at point: CGPoint) {
        switch currentTool {
        case .selection:
            handleSelectionAt(point)
        case .move:
            handleMoveStart(at: point)
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
        case .move:
            handleMoveFinish(from: startPoint, to: endPoint)
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
        // Check if we're currently in text editing mode
        if canvasView.textView != nil {
            // Don't handle keyboard shortcuts while editing text
            return
        }
        
        // Handle command+key combinations first (before tool shortcuts)
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 8 { // Cmd+C
                copyCompositeToClipboard()
                return
            } else if event.keyCode == 13 { // Cmd+W
                window?.close()
                return
            }
        }
        
        // Handle other non-command keyboard shortcuts
        if event.keyCode == 51 { // Delete key
            deleteSelectedElement()
            return
        }
        
        // Handle keyboard shortcuts for tool switching (only when no modifier keys are pressed)
        if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
                if let keyCharacter = event.charactersIgnoringModifiers?.lowercased() {
                for tool in MarkupTool.allCases {
                    if keyCharacter == tool.keyboardShortcut {
                        currentTool = tool                        // Clear selections when switching to move tool for clean slate
                        if tool == .move {
                            for element in markupElements {
                                element.isSelected = false
                            }
                            selectedElement = nil
                            canvasView.needsDisplay = true
                        }
                        
                        titleBarToolbar.selectTool(tool)
                        canvasView.setCurrentTool(tool)
                        return
                    }
                }
            }
        }
    }
    
    func canvasDidUpdateElements(_ elements: [any MarkupElement]) {
        markupElements = elements
    }
    
    func canvasDidSelectElement(_ element: any MarkupElement) {
        selectedElement = element
        canvasView.needsDisplay = true
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
    
    private func handleMoveStart(at point: CGPoint) {
        moveStartPoint = point
        
        // First, deselect all elements
        for element in markupElements {
            element.isSelected = false
        }
        selectedElement = nil
        
        // Find element at point to select and move
        for (_, element) in markupElements.reversed().enumerated() {
            if element.contains(point: point) {
                selectedElement = element
                element.isSelected = true
                elementStartPosition = element.bounds.origin
                canvasView.needsDisplay = true
                return
            }
        }
        
        canvasView.needsDisplay = true
    }
    
    private func handleMoveFinish(from startPoint: CGPoint, to endPoint: CGPoint) {
        guard let selected = selectedElement,
              let moveStart = moveStartPoint,
              let _ = elementStartPosition else { 
            return 
        }
        
        // Calculate the delta movement
        let deltaX = endPoint.x - moveStart.x
        let deltaY = endPoint.y - moveStart.y
        
        // Apply movement based on element type
        moveElement(selected, deltaX: deltaX, deltaY: deltaY)
        
        // Clear move state
        moveStartPoint = nil
        elementStartPosition = nil
        
        canvasView.needsDisplay = true
    }
    
    private func moveElement(_ element: any MarkupElement, deltaX: CGFloat, deltaY: CGFloat) {
        // Move different element types
        if let arrow = element as? ArrowElement {
            arrow.move(by: CGPoint(x: deltaX, y: deltaY))
        } else if let rectangle = element as? RectangleElement {
            rectangle.move(by: CGPoint(x: deltaX, y: deltaY))
        } else if let stepCounter = element as? StepCounterElement {
            stepCounter.move(by: CGPoint(x: deltaX, y: deltaY))
        } else if let text = element as? TextElement {
            text.move(by: CGPoint(x: deltaX, y: deltaY))
        }
    }
    
    private func handleStepCounterStamp(at point: CGPoint) {
        // Clamp the center point to ensure the stamp doesn't extend beyond image bounds
        // Step counter has a radius of 20 pixels
        let radius: CGFloat = 20.0
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        let clampedPoint = CGPoint(
            x: max(radius, min(point.x, imageRect.maxX - radius)),
            y: max(radius, min(point.y, imageRect.maxY - radius))
        )
        
        // Calculate the next step number based on existing step counter elements
        let existingStepNumbers = markupElements.compactMap { element in
            return (element as? StepCounterElement)?.stepNumber
        }
        
        // Find the highest existing number and add 1
        let nextStepNumber = (existingStepNumbers.max() ?? 0) + 1
        
        // Create the new step counter element with clamped position
        let stepCounter = StepCounterElement(centerPoint: clampedPoint, stepNumber: nextStepNumber, color: MarkupColorManager.shared.currentColor)
        markupElements.append(stepCounter)
        
        // Update the canvas view's elements
        canvasView.markupElements = markupElements
        canvasView.needsDisplay = true
    }
    
    private func handleTextInput(at point: CGPoint) {
        // Clamp the text position to ensure it starts within image bounds
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        let clampedPoint = CGPoint(
            x: max(0, min(point.x, imageRect.maxX)),
            y: max(0, min(point.y, imageRect.maxY))
        )
        
        // Start text editing at the clamped location
        canvasView.startTextEditing(at: clampedPoint)
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
        
        // Show feedback to user
        showCopyFeedback()
    }
    
    private func showCopyFeedback() {
        guard let window = window else { return }
        
        // Create feedback view
        let feedbackView = NSView()
        feedbackView.wantsLayer = true
        feedbackView.layer?.cornerRadius = 8
        feedbackView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        
        // Create label
        let label = NSTextField(labelWithString: "Copied to Clipboard")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor.white
        label.alignment = .center
        
        // Create icon (checkmark)
        let checkmarkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success") ?? NSImage()
        let imageView = NSImageView(image: checkmarkImage)
        imageView.contentTintColor = NSColor.white
        
        // Create stack view
        let stackView = NSStackView(views: [imageView, label])
        stackView.orientation = NSUserInterfaceLayoutOrientation.horizontal
        stackView.spacing = 8
        stackView.alignment = NSLayoutConstraint.Attribute.centerY
        
        // Add stack view to feedback view
        feedbackView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: feedbackView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: feedbackView.centerYAnchor),
            feedbackView.widthAnchor.constraint(greaterThanOrEqualTo: stackView.widthAnchor, constant: 20),
            feedbackView.heightAnchor.constraint(greaterThanOrEqualTo: stackView.heightAnchor, constant: 12),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // Add to window content view
        window.contentView?.addSubview(feedbackView)
        feedbackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            feedbackView.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            feedbackView.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 50)
        ])
        
        // Initial state - hidden
        feedbackView.alphaValue = 0
        feedbackView.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)
        
        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            feedbackView.animator().alphaValue = 1
            feedbackView.layer?.transform = CATransform3DIdentity
        } completionHandler: {
            // Animate out after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    feedbackView.animator().alphaValue = 0
                    feedbackView.layer?.transform = CATransform3DMakeScale(0.9, 0.9, 1)
                } completionHandler: {
                    feedbackView.removeFromSuperview()
                }
            }
        }
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
    func canvasDidSelectElement(_ element: any MarkupElement)
    var selectedElement: (any MarkupElement)? { get }
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
    var textView: MarkupTextView?
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
    
    /// Clamps a point to stay within the image bounds
    private func clampToImageBounds(_ point: CGPoint) -> CGPoint {
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
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
        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        baseImage.draw(in: imageRect)
        
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
            }
        }
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

// MARK: - Toolbar View
protocol MarkupToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: MarkupTool)
    func toolbarDidSelectColor(_ color: NSColor)
    func thicknessButtonClicked(_ sender: NSButton)
    func colorButtonClicked(_ sender: NSButton)
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
        // Each tool button (6): 40pt wide
        // Separator: 1pt wide
        // Thickness button: 40pt wide
        // Color button: 40pt wide
        // Spacing between items: 8pt each (7 spaces total: 6 tools + 1 separator + thickness + color = 8 items - 1 = 7 spaces)
        // Leading padding: 12pt
        // Trailing padding: 16pt (for rounded corner clearance)
        let totalWidth = (6 * 40) + 1 + 40 + 40 + (7 * 8) + 12 + 16 // = 240 + 1 + 40 + 40 + 56 + 12 + 16 = 405pt
        let size = NSSize(width: CGFloat(totalWidth), height: 32)
        print("DEBUG: TitleBarToolbarView intrinsicContentSize calculated as: \(size)")
        return size
    }
    
    private func updateToolbarBackground() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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