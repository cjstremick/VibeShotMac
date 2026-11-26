import AppKit

protocol RecordingHUDDelegate: AnyObject {
    func recordingHUDDidRequestStop(_ hud: RecordingHUDController)
}

/// On-screen evidence that a region is being recorded: a subtle dim outside the
/// captured area, a red border around it, and a Stop button just outside it.
/// VibeShot excludes its own application from the capture stream so none of this
/// chrome appears in the recorded video.
final class RecordingHUDController: NSObject {
    /// Called when the on-screen Stop button is pressed.
    weak var delegate: RecordingHUDDelegate?

    static let stopButtonSize = CGSize(width: 84, height: 30)

    private let maskWindow: NSWindow
    private let stopPanel: NSPanel

    init(region: CGRect, display: NSScreen) {
        let displayFrame = display.frame
        let localRegion = region.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)

        let maskView = RecordingMaskView(frame: NSRect(origin: .zero, size: displayFrame.size),
                                         region: localRegion)
        let mask = NSWindow(contentRect: displayFrame, styleMask: [.borderless],
                            backing: .buffered, defer: false)
        mask.isReleasedWhenClosed = false
        mask.isOpaque = false
        mask.backgroundColor = .clear
        mask.hasShadow = false
        mask.ignoresMouseEvents = true  // never block the app being recorded
        mask.level = .floating
        mask.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        mask.contentView = maskView
        maskWindow = mask

        let frame = Self.stopButtonFrame(region: region, displayFrame: displayFrame,
                                         size: Self.stopButtonSize, gap: 10)
        let button = NSButton()
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.systemRed.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        button.attributedTitle = NSAttributedString(string: "Stop", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        button.toolTip = "Stop recording"
        button.setAccessibilityLabel("Stop recording")
        button.frame = NSRect(origin: .zero, size: frame.size)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = button
        stopPanel = panel

        super.init()

        // Target/action needs a fully initialized self.
        button.target = self
        button.action = #selector(stopPressed)
    }

    /// Shows the dimmed surround and border. The Stop control is added separately
    /// so it does not flash on screen during the countdown.
    func show() {
        maskWindow.orderFrontRegardless()
    }

    /// Window IDs the capture filter should exclude. Other VibeShot windows,
    /// such as the pointer-effects overlay, stay in the recording.
    var windowNumbers: Set<CGWindowID> {
        Set([maskWindow.windowNumber, stopPanel.windowNumber]
            .filter { $0 > 0 }
            .map { CGWindowID($0) })
    }

    /// The Stop control is hidden during the countdown and shown once recording
    /// actually begins.
    func setStopControlVisible(_ visible: Bool) {
        if visible {
            stopPanel.orderFrontRegardless()
        } else {
            stopPanel.orderOut(nil)
        }
    }

    func close() {
        maskWindow.orderOut(nil)
        stopPanel.orderOut(nil)
    }

    @objc private func stopPressed() {
        delegate?.recordingHUDDidRequestStop(self)
    }

    /// Places the Stop control just outside the region, preferring below, then
    /// above, then beside it, and always clamps it inside the display.
    static func stopButtonFrame(region: CGRect, displayFrame: CGRect,
                                size: CGSize, gap: CGFloat) -> CGRect {
        let minX = displayFrame.minX + gap
        let maxX = displayFrame.maxX - size.width - gap
        let minY = displayFrame.minY + gap
        let maxY = displayFrame.maxY - size.height - gap

        var origin = CGPoint(x: region.maxX - size.width, y: region.minY - size.height - gap)  // below
        if origin.y < minY {
            origin = CGPoint(x: region.maxX - size.width, y: region.maxY + gap)  // above
            if origin.y > maxY {
                origin = CGPoint(x: region.maxX + gap, y: region.midY - size.height / 2)  // right
                if origin.x > maxX {
                    origin = CGPoint(x: region.minX - size.width - gap, y: region.midY - size.height / 2)  // left
                    if origin.x < minX {
                        // Very small display: fall back to the inside of the corner.
                        origin = CGPoint(x: region.maxX - size.width - gap, y: region.minY + gap)
                    }
                }
            }
        }

        let clampedX = min(max(origin.x, minX), max(maxX, minX))
        let clampedY = min(max(origin.y, minY), max(maxY, minY))
        return CGRect(x: clampedX, y: clampedY, width: size.width, height: size.height)
    }
}

/// Draws the dimmed surround, the red capture border and a small REC badge.
private final class RecordingMaskView: NSView {
    private let region: CGRect

    init(frame frameRect: NSRect, region: CGRect) {
        self.region = region
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything outside the captured region, leaving the region clear.
        context.saveGState()
        let surround = CGMutablePath()
        surround.addRect(bounds)
        surround.addRect(region)
        context.addPath(surround)
        context.clip(using: .evenOdd)
        context.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
        context.fill(bounds)
        context.restoreGState()

        // Red border around the captured region.
        context.saveGState()
        context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(2)
        context.stroke(region)
        context.restoreGState()

        drawRecBadge()
    }

    private func drawRecBadge() {
        let text = "\u{25CF} REC" as NSString  // ● REC
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = NSSize(width: 8, height: 4)
        let badgeSize = NSSize(width: textSize.width + padding.width * 2,
                               height: textSize.height + padding.height * 2)

        var origin = CGPoint(x: region.minX, y: region.maxY + 6)
        if origin.y + badgeSize.height > bounds.maxY - 4 {
            origin.y = region.maxY - badgeSize.height - 6
        }
        if origin.x + badgeSize.width > bounds.maxX - 4 {
            origin.x = bounds.maxX - badgeSize.width - 4
        }
        origin.x = max(bounds.minX + 4, origin.x)
        origin.y = max(bounds.minY + 4, origin.y)

        let badgeRect = CGRect(origin: origin, size: badgeSize)
        NSColor.systemRed.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height),
                  withAttributes: attributes)
    }
}
