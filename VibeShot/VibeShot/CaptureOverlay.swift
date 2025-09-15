import AppKit

protocol CaptureOverlayDelegate: AnyObject {
    func overlayDidFinish(rect: CGRect?)
}

final class CaptureOverlayController: NSObject {
    private var window: OverlayWindow?
    let display: NSScreen
    weak var delegate: CaptureOverlayDelegate?

    init(display: NSScreen) {
        self.display = display
    }

    func begin() {
        let w = OverlayWindow(screen: display)
        w.overlayDelegate = self
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

extension CaptureOverlayController: OverlayInteractionDelegate {
    func overlayCancelled() {
        window?.orderOut(nil)
        window = nil
        delegate?.overlayDidFinish(rect: nil)
    }
    func overlayCompleted(rect: CGRect) {
        // Convert local (window-content) rect to global screen coordinates.
        // Window origin equals display.frame.origin, and overlayView's coordinate system is unflipped with origin at bottom-left.
        let global = rect.offsetBy(dx: display.frame.origin.x, dy: display.frame.origin.y)
        window?.orderOut(nil)
        window = nil
        delegate?.overlayDidFinish(rect: global)
    }
}

// MARK: - Window / View
private final class OverlayWindow: NSWindow, OverlayInteractionDelegate {
    weak var overlayDelegate: OverlayInteractionDelegate?
    private let overlayView: OverlayRootView

    init(screen: NSScreen) {
        overlayView = OverlayRootView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = overlayView
        overlayView.interactionDelegate = self
    }
    override var canBecomeKey: Bool { true }

    // MARK: OverlayInteractionDelegate passthrough
    func overlayCancelled() { overlayDelegate?.overlayCancelled() }
    func overlayCompleted(rect: CGRect) { overlayDelegate?.overlayCompleted(rect: rect) }
}

private protocol OverlayInteractionDelegate: AnyObject {
    func overlayCancelled()
    func overlayCompleted(rect: CGRect)
}

private final class OverlayRootView: NSView {
    weak var interactionDelegate: OverlayInteractionDelegate?

    private var dragStart: CGPoint?
    private var currentRect: CGRect? { didSet { needsDisplay = true } }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .black.withAlphaComponent(0.5)
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.masksToBounds = true
        label.alignment = .center
        // Ensure crosshair cursor immediately
        NSCursor.crosshair.set()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        dirtyRect.fill()
        guard let rect = currentRect else { return }

        // Punch hole
        let full = NSBezierPath(rect: bounds)
        let sel = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        full.append(sel)
        full.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.25).setFill()
        full.fill()

        // Border (double for contrast)
        NSColor.black.withAlphaComponent(0.6).setStroke(); sel.lineWidth = 1.5; sel.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke(); sel.lineWidth = 1; sel.stroke()

        // Guides
        let guides = NSBezierPath()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        guides.lineWidth = 0.5
        guides.move(to: CGPoint(x: rect.minX+0.5, y: 0)); guides.line(to: CGPoint(x: rect.minX+0.5, y: bounds.height))
        guides.move(to: CGPoint(x: rect.maxX-0.5, y: 0)); guides.line(to: CGPoint(x: rect.maxX-0.5, y: bounds.height))
        guides.move(to: CGPoint(x: 0, y: rect.minY+0.5)); guides.line(to: CGPoint(x: bounds.width, y: rect.minY+0.5))
        guides.move(to: CGPoint(x: 0, y: rect.maxY-0.5)); guides.line(to: CGPoint(x: bounds.width, y: rect.maxY-0.5))
        guides.stroke()

        // Handles (visual only for now)
        let handleSize: CGFloat = 6
        let handleColor = NSColor.white
        let positions: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY), // bl
            CGPoint(x: rect.midX, y: rect.minY), // b
            CGPoint(x: rect.maxX, y: rect.minY), // br
            CGPoint(x: rect.minX, y: rect.midY), // l
            CGPoint(x: rect.maxX, y: rect.midY), // r
            CGPoint(x: rect.minX, y: rect.maxY), // tl
            CGPoint(x: rect.midX, y: rect.maxY), // t
            CGPoint(x: rect.maxX, y: rect.maxY)  // tr
        ]
        for p in positions {
            let r = CGRect(x: p.x - handleSize/2, y: p.y - handleSize/2, width: handleSize, height: handleSize)
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            NSColor.black.withAlphaComponent(0.55).setFill(); path.fill()
            handleColor.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    // Label layout
    private func updateLabel(for rect: CGRect) {
        let text = "\(Int(rect.width))×\(Int(rect.height))"
        label.stringValue = text
        let size = label.intrinsicContentSize
        var labelFrame = CGRect(x: rect.minX, y: rect.maxY + 8, width: size.width + 12, height: size.height + 6)
        if labelFrame.maxX > bounds.maxX - 4 { labelFrame.origin.x = bounds.maxX - labelFrame.width - 4 }
        if labelFrame.maxY > bounds.maxY - 4 { labelFrame.origin.y = rect.minY - labelFrame.height - 8 }
        label.frame = labelFrame
    }

    override func mouseDown(with event: NSEvent) {
        var start = convert(event.locationInWindow, from: nil)
        // Clamp start within bounds
        start.x = max(0, min(bounds.width, start.x))
        start.y = max(0, min(bounds.height, start.y))
        dragStart = start
        currentRect = CGRect(origin: dragStart!, size: .zero)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var p = convert(event.locationInWindow, from: nil)
        // Clamp drag point within bounds
        p.x = max(0, min(bounds.width, p.x))
        p.y = max(0, min(bounds.height, p.y))
        var rect = CGRect(x: min(start.x, p.x),
                          y: min(start.y, p.y),
                          width: abs(start.x - p.x),
                          height: abs(start.y - p.y))
        // Redundant safety clamp (in case of numeric weirdness)
        rect = rect.intersection(bounds)
        currentRect = rect
        updateLabel(for: rect)
    }
    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width >= 3, rect.height >= 3 else {
            interactionDelegate?.overlayCancelled(); return
        }
        interactionDelegate?.overlayCompleted(rect: rect)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { interactionDelegate?.overlayCancelled() }
    }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
}
