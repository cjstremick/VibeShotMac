import AppKit

/// Draws click ripples and scroll indicators into the capture.
///
/// This click-through window is deliberately **not** excluded from the
/// ScreenCaptureKit filter (unlike the recording HUD), so its drawing becomes
/// part of the recorded pixels. The real pointer shape comes from
/// `SCStreamConfiguration.showsCursor`.
final class PointerActivityOverlay {
    private let window: NSWindow
    private let effectsView: PointerEffectsView
    private let region: CGRect       // global screen coordinates
    private let displayFrame: CGRect
    private var monitor: Any?
    private var lastScrollTimestamp: TimeInterval = 0

    init(region: CGRect, display: NSScreen) {
        self.region = region
        self.displayFrame = display.frame

        let frame = display.frame
        effectsView = PointerEffectsView(frame: NSRect(origin: .zero, size: frame.size))

        window = NSWindow(contentRect: frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = effectsView
    }

    func show() {
        window.orderFrontRegardless()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            // Global monitors usually deliver on the main thread; hop to be safe.
            DispatchQueue.main.async { self?.handle(event) }
        }
        if monitor == nil {
            NSLog("[Pointer] Global mouse monitor is unavailable; click and scroll effects will be missing")
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window.orderOut(nil)
    }

    private func handle(_ event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        guard region.contains(screenPoint) else { return }
        let local = CGPoint(x: screenPoint.x - displayFrame.minX,
                            y: screenPoint.y - displayFrame.minY)

        switch event.type {
        case .leftMouseDown:
            effectsView.addClick(at: local, color: .systemBlue)
        case .rightMouseDown:
            effectsView.addClick(at: local, color: .systemRed)
        case .otherMouseDown:
            effectsView.addClick(at: local, color: .systemYellow)
        case .scrollWheel:
            // A burst of scroll events should not flood the overlay.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastScrollTimestamp > 0.06 else { return }
            lastScrollTimestamp = now
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return }
            effectsView.addScroll(at: local, up: delta > 0)
        default:
            break
        }
    }
}

/// Renders transient click rings and scroll chevrons as Core Animation layers.
private final class PointerEffectsView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addClick(at point: CGPoint, color: NSColor) {
        let scale = window?.backingScaleFactor ?? 2

        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6), transform: nil)
        dot.fillColor = color.cgColor
        dot.position = point
        dot.contentsScale = scale
        layer?.addSublayer(dot)
        let dotFade = CABasicAnimation(keyPath: "opacity")
        dotFade.fromValue = 0.95
        dotFade.toValue = 0
        animate(dot, animations: [dotFade], duration: 0.3, key: "dot")

        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.5
        ring.position = point
        ring.contentsScale = scale
        layer?.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.5
        grow.toValue = 2.4
        let ringFade = CABasicAnimation(keyPath: "opacity")
        ringFade.fromValue = 0.95
        ringFade.toValue = 0
        animate(ring, animations: [grow, ringFade], duration: 0.55, key: "ripple")
    }

    func addScroll(at point: CGPoint, up: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        let arrow = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -7, y: up ? 4 : -4))
        path.addLine(to: CGPoint(x: 0, y: up ? -4 : 4))
        path.addLine(to: CGPoint(x: 7, y: up ? 4 : -4))
        arrow.path = path
        arrow.strokeColor = NSColor.white.cgColor
        arrow.fillColor = NSColor.clear.cgColor
        arrow.lineWidth = 2
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.position = point
        arrow.contentsScale = scale
        arrow.shadowColor = NSColor.black.cgColor
        arrow.shadowOpacity = 0.6
        arrow.shadowRadius = 2
        arrow.shadowOffset = .zero
        layer?.addSublayer(arrow)

        let drift = CABasicAnimation(keyPath: "position.y")
        drift.fromValue = point.y
        drift.toValue = point.y + (up ? 14 : -14)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.95
        fade.toValue = 0
        animate(arrow, animations: [drift, fade], duration: 0.45, key: "scroll")
    }

    private func animate(_ shape: CALayer, animations: [CAAnimation],
                         duration: CFTimeInterval, key: String) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        shape.add(group, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            shape.removeFromSuperlayer()
        }
    }
}
