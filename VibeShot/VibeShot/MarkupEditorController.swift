import Cocoa
import SwiftUI

/// Main markup editor window controller
final class MarkupEditorController: NSWindowController {
    private var baseImage: NSImage
    private var markupElements: [any MarkupElement] = []
    private var currentTool: MarkupTool = .arrow  // Start with arrow tool selected
    internal var selectedElement: (any MarkupElement)?
    
    // Undo/Redo
    private struct EditorState {
        let image: NSImage
        let elements: [any MarkupElement]
    }
    
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    
    // Move tool properties
    private var moveStartPoint: CGPoint?
    private var elementStartPosition: CGPoint?
    
    private var canvasView: MarkupCanvasView!
    private var titleBarToolbar: TitleBarToolbarView!
    
    // Minimum window width to ensure title bar toolbar doesn't get clipped
    private static let minimumWindowWidth: CGFloat = 700
    
    init(baseImage: NSImage) {
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
        guard let window = window else { return }
        
        window.title = "VibeShot Editor"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Configure title bar toolbar
        configureTitleBarToolbar()
        
        // Don't set first responder here - it will be set after layout is complete
    }
    
    // MARK: - Undo/Redo Logic
    
    private func pushUndoState() {
        // Deep copy current elements
        let snapshotElements = markupElements.map { $0.duplicate() }
        let snapshot = EditorState(image: baseImage, elements: snapshotElements)
        undoStack.append(snapshot)
        
        // Limit undo stack size to prevent excessive memory usage
        if undoStack.count > MarkupConstants.UndoRedo.maxStackSize {
            undoStack.removeFirst()
        }
        
        redoStack.removeAll() // Clear redo stack on new action
    }
    
    private func performUndo() {
        guard let previousState = undoStack.popLast() else { return }
        
        // Save current state to redo stack
        let currentElements = markupElements.map { $0.duplicate() }
        let currentState = EditorState(image: baseImage, elements: currentElements)
        redoStack.append(currentState)
        
        // Restore previous state
        baseImage = previousState.image
        canvasView.image = baseImage
        markupElements = previousState.elements
        selectedElement = nil // Clear selection to avoid issues
        
        canvasView.markupElements = markupElements
        canvasView.needsDisplay = true
        
        // Update window size if image size changed
        if let window = self.window {
            let newWidth = max(baseImage.size.width, Self.minimumWindowWidth)
            let newSize = NSSize(width: newWidth, height: baseImage.size.height)
            window.setContentSize(newSize)
        }
    }
    
    private func performRedo() {
        guard let nextState = redoStack.popLast() else { return }
        
        // Save current state to undo stack
        let currentElements = markupElements.map { $0.duplicate() }
        let currentState = EditorState(image: baseImage, elements: currentElements)
        undoStack.append(currentState)
        
        // Restore next state
        baseImage = nextState.image
        canvasView.image = baseImage
        markupElements = nextState.elements
        selectedElement = nil
        
        canvasView.markupElements = markupElements
        canvasView.needsDisplay = true
        
        // Update window size if image size changed
        if let window = self.window {
            let newWidth = max(baseImage.size.width, Self.minimumWindowWidth)
            let newSize = NSSize(width: newWidth, height: baseImage.size.height)
            window.setContentSize(newSize)
        }
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
        
        // Center the canvas in the container
        // The canvas will size itself via intrinsicContentSize (matching the image size)
        NSLayoutConstraint.activate([
            canvasView.centerXAnchor.constraint(equalTo: canvasContainer.centerXAnchor),
            canvasView.centerYAnchor.constraint(equalTo: canvasContainer.centerYAnchor),
            // Ensure canvas doesn't exceed container bounds (scale down if needed, though we prefer scrolling or window resizing)
            canvasView.widthAnchor.constraint(lessThanOrEqualTo: canvasContainer.widthAnchor),
            canvasView.heightAnchor.constraint(lessThanOrEqualTo: canvasContainer.heightAnchor)
        ])
        
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
        guard let window = window else { return }
        
        // Enable layer for proper rendering
        titleBarToolbar.wantsLayer = true
        
        // Ensure the toolbar has the correct frame based on intrinsic content size
        let intrinsicSize = titleBarToolbar.intrinsicContentSize
        titleBarToolbar.frame = NSRect(origin: .zero, size: intrinsicSize)
        
        // Create title bar accessory view controller
        let accessoryViewController = NSTitlebarAccessoryViewController()
        accessoryViewController.view = titleBarToolbar
        accessoryViewController.layoutAttribute = .trailing
        
        // Add the accessory view controller to the window
        window.addTitlebarAccessoryViewController(accessoryViewController)
        
        // Initialize title bar toolbar state
        titleBarToolbar.updateColor(MarkupColorManager.shared.currentColor)
        titleBarToolbar.updateThickness(MarkupLineThicknessManager.shared.currentThickness)
        titleBarToolbar.selectTool(currentTool)
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
    }
}

// MARK: - MarkupCanvasDelegate
extension MarkupEditorController: MarkupCanvasDelegate {
    func canvasDidStartDrawing(at point: CGPoint) {
        switch currentTool {
        case .selection:
            handleSelectionStart(at: point)
        case .arrow, .rectangle, .blur:
            // Will handle in canvasDidFinishDrawing
            break
        case .stepCounter:
            // Handle step counter immediately on click
            handleStepCounterStamp(at: point)
        case .text:
            // Handle text editing immediately on click
            handleTextInput(at: point)
        case .crop:
            // Crop selection is handled by canvas view
            break
        }
    }
    
    func canvasDidFinishCrop(rect: CGRect) {
        applyCrop(rect: rect)
    }
    
    func canvasWillResize() {
        pushUndoState()  // Save state before resize operation
    }
    
    func canvasDidFinishDrawing(from startPoint: CGPoint, to endPoint: CGPoint) {
        switch currentTool {
        case .selection:
            handleSelectionFinish(from: startPoint, to: endPoint)
        case .arrow:
            // Calculate the distance of the arrow
            let distance = sqrt(pow(endPoint.x - startPoint.x, 2) + pow(endPoint.y - startPoint.y, 2))
            
            // Skip creating arrow if it's too short (likely accidental click or very short drag)
            let minimumArrowLength: CGFloat = 30.0  // About the size of the arrowhead
            guard distance >= minimumArrowLength else {
                return
            }
            
            pushUndoState() // Save state before adding
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
            
            pushUndoState() // Save state before adding
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
        case .blur:
            let rect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
            
            let minimumSize: CGFloat = 10.0
            guard rect.width >= minimumSize && rect.height >= minimumSize else { return }
            
            pushUndoState() // Save state before adding
            let blur = BlurElement(rect: rect, baseImage: baseImage)
            markupElements.append(blur)
            
            canvasView.markupElements = markupElements
            canvasView.needsDisplay = true
        case .crop:
            // Crop selection is handled by canvas view
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
            } else if event.keyCode == 6 { // Cmd+Z (Undo)
                if event.modifierFlags.contains(.shift) {
                    performRedo()
                } else {
                    performUndo()
                }
                return
            }
        }
        
        // Handle other non-command keyboard shortcuts
        if event.keyCode == 51 { // Delete key
            deleteSelectedElement()
            return
        }
        
        // Handle Enter and Escape for Crop tool
        if currentTool == .crop {
            if event.keyCode == 53 { // Escape key
                cancelCrop()
                return
            }
        }
        
        // Handle keyboard shortcuts for tool switching (only when no modifier keys are pressed)
        if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
            if let keyCharacter = event.charactersIgnoringModifiers?.lowercased() {
                for tool in MarkupTool.allCases {
                    if keyCharacter == tool.keyboardShortcut {
                        currentTool = tool
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
    
    func canvasDidRequestToolChange(_ tool: MarkupTool) {
        // Switch to the requested tool (e.g., from click-to-select)
        currentTool = tool
        titleBarToolbar.selectTool(tool)
        canvasView.setCurrentTool(tool)
    }
    
    private func handleSelectionStart(at point: CGPoint) {
        moveStartPoint = point
        
        // Check if clicking on ANY already-selected element (to move all selected)
        for element in markupElements {
            if element.isSelected && element.contains(point: point) {
                // Clicking on a selected element - prepare to move all selected elements
                elementStartPosition = element.bounds.origin
                canvasView.needsDisplay = true
                return
            }
        }
        
        // Otherwise, deselect all and try to select a new element
        for element in markupElements {
            element.isSelected = false
        }
        selectedElement = nil
        
        // Find topmost element at point (reverse order for topmost)
        for element in markupElements.reversed() {
            if element.contains(point: point) {
                selectedElement = element
                element.isSelected = true
                elementStartPosition = element.bounds.origin
                break
            }
        }
        
        canvasView.needsDisplay = true
    }
    
    private func handleSelectionFinish(from startPoint: CGPoint, to endPoint: CGPoint) {
        guard let moveStart = moveStartPoint,
              let _ = elementStartPosition else {
            // No move was prepared, clear move state
            moveStartPoint = nil
            elementStartPosition = nil
            return
        }
        
        // Check if any elements are selected
        let selectedElements = markupElements.filter { $0.isSelected }
        guard !selectedElements.isEmpty else {
            moveStartPoint = nil
            elementStartPosition = nil
            return
        }
        
        // Calculate the delta movement
        let deltaX = endPoint.x - moveStart.x
        let deltaY = endPoint.y - moveStart.y
        
        // Only apply movement if there was actual movement
        if abs(deltaX) > 1 || abs(deltaY) > 1 {
            // Push undo state before applying the move
            pushUndoState()
            
            // Move all selected elements
            let translation = CGPoint(x: deltaX, y: deltaY)
            for element in selectedElements {
                moveElement(element, by: translation)
            }
        }
        
        // Clear move state
        moveStartPoint = nil
        elementStartPosition = nil
        
        canvasView.needsDisplay = true
    }
    
    private func moveElement(_ element: any MarkupElement, by translation: CGPoint) {
        // MarkupElement protocol already has move(by:) method
        element.move(by: translation)
    }
    
    private func handleStepCounterStamp(at point: CGPoint) {
        // Clamp the center point to ensure the stamp doesn't extend beyond image bounds
        // Step counter has a radius of 20 pixels
        let radius: CGFloat = MarkupConstants.StepCounter.radius
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
        
        pushUndoState() // Save state before adding
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
        
        pushUndoState() // Save state before adding/editing text
        // Start text editing at the clamped location
        canvasView.startTextEditing(at: clampedPoint)
        // Note: Synchronization will happen after text editing is complete
    }
    
    private func deleteSelectedElement() {
        // Delete all selected elements (supports multiple selection from rectangle selection)
        let selectedElements = markupElements.filter { $0.isSelected }
        
        if !selectedElements.isEmpty {
            pushUndoState() // Save state before deletion
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
        guard let contentView = window.contentView else { return }
        contentView.addSubview(feedbackView)
        feedbackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            feedbackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            feedbackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50)
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
    
    private func applyCrop(rect: CGRect) {
        // Ensure crop rect is valid and has size
        guard rect.width > 0 && rect.height > 0 else { return }
        
        // Push undo state before modifying
        pushUndoState()
        
        // 1. Crop the image
        let newSize = rect.size
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: newSize), from: rect, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        
        // 2. Update base image
        baseImage = newImage
        canvasView.image = baseImage
        
        // 3. Shift all elements
        let offset = CGPoint(x: -rect.origin.x, y: -rect.origin.y)
        
        for element in markupElements {
            if let blurElement = element as? BlurElement {
                blurElement.updateBaseImage(baseImage)
            }
            element.move(by: offset)
        }
        
        // 4. Reset crop selection
        canvasView.cropSelectionRect = nil
        canvasView.needsDisplay = true
        
        // 5. Resize window content
        if let window = self.window {
            let windowWidth = max(newSize.width, Self.minimumWindowWidth)
            let windowSize = NSSize(width: windowWidth, height: newSize.height)
            window.setContentSize(windowSize)
        }
    }
    
    private func cancelCrop() {
        canvasView.cropSelectionRect = nil
        canvasView.needsDisplay = true
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
        
        // Draw markup elements sorted by z-order (lower values draw first/behind)
        let sortedElements = markupElements.sorted { $0.zOrder < $1.zOrder }
        for element in sortedElements {
            element.draw(in: context)
        }
        
        composite.unlockFocus()
        return composite
    }
}

