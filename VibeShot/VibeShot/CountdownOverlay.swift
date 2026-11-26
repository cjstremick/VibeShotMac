import AppKit

/// Full-screen countdown shown after a region is chosen and before recording
/// starts. It is click-through and is never captured because recording has not
/// begun yet.
final class CountdownOverlayController {
    private let window: NSWindow
    private let numberLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "Recording starts in")
    private var remaining: Int
    private let completion: () -> Void
    private var finished = false

    init(region: CGRect, display: NSScreen, seconds: Int, completion: @escaping () -> Void) {
        let seconds = max(1, seconds)
        self.remaining = seconds
        self.completion = completion

        let frame = display.frame
        let localRegion = region.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        // Transparent: the recording HUD behind this window already dims
        // everything outside the selected region.
        container.layer?.backgroundColor = NSColor.clear.cgColor

        // Scale the countdown to the selected region so it stays inside small
        // captures instead of spilling across the screen.
        let baseHalo: CGFloat = 240
        let fit = min(1.0,
                      (localRegion.width * 0.8) / baseHalo,
                      (localRegion.height * 0.8) / baseHalo)
        let scale = max(0.25, fit)
        let haloSize = baseHalo * scale

        // A frame-backed container maps the countdown onto the capture region;
        // its subviews then center with Auto Layout.
        let regionContainer = NSView(frame: localRegion)
        container.addSubview(regionContainer)

        // A soft halo keeps the number readable over bright content without
        // darkening the region being captured.
        let halo = NSView()
        halo.wantsLayer = true
        halo.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        halo.layer?.cornerRadius = haloSize / 2
        halo.translatesAutoresizingMaskIntoConstraints = false
        regionContainer.addSubview(halo)

        numberLabel.stringValue = "\(seconds)"
        numberLabel.font = NSFont.systemFont(ofSize: 170 * scale, weight: .heavy)
        numberLabel.textColor = .white
        numberLabel.alignment = .center
        numberLabel.wantsLayer = true
        numberLabel.layer?.shadowColor = NSColor.black.cgColor
        numberLabel.layer?.shadowOpacity = 0.55
        numberLabel.layer?.shadowRadius = 14
        numberLabel.layer?.shadowOffset = .zero
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: max(10, 20 * scale), weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.alignment = .center
        subtitleLabel.isHidden = localRegion.height < 140
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        regionContainer.addSubview(numberLabel)
        regionContainer.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            halo.centerXAnchor.constraint(equalTo: regionContainer.centerXAnchor),
            halo.centerYAnchor.constraint(equalTo: regionContainer.centerYAnchor),
            halo.widthAnchor.constraint(equalToConstant: haloSize),
            halo.heightAnchor.constraint(equalToConstant: haloSize),
            numberLabel.centerXAnchor.constraint(equalTo: regionContainer.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: regionContainer.centerYAnchor),
            subtitleLabel.centerXAnchor.constraint(equalTo: regionContainer.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: -8 * scale)
        ])

        window = NSWindow(contentRect: frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = container
    }

    func begin() {
        window.orderFrontRegardless()
        tick()
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        window.orderOut(nil)
    }

    private func tick() {
        guard !finished else { return }
        if remaining <= 0 {
            finished = true
            window.orderOut(nil)
            completion()
            return
        }
        numberLabel.stringValue = "\(remaining)"
        animatePop()
        remaining -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.tick()
        }
    }

    private func animatePop() {
        guard let layer = numberLabel.layer else { return }
        layer.removeAllAnimations()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.65
        scale.toValue = 1.0
        scale.duration = 0.38
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: "pop")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.35
        fade.toValue = 1.0
        fade.duration = 0.25
        layer.add(fade, forKey: "fade")
    }
}
