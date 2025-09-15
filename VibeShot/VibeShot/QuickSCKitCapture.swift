import AppKit
import ScreenCaptureKit

// MARK: - Public API
protocol RegionCapturing {
    @MainActor func capture(rect: CGRect, on display: NSScreen) async throws -> QuickSCKitCapture.Result
}

final class QuickSCKitCapture: RegionCapturing {

    struct Result { let image: NSImage }

    enum CaptureError: Error { case unsupported, noDisplay, frameTimeout, permissionDenied }

    // Convenience test utility used by diagnostics.
    @MainActor
    func captureCentralRectOnActiveDisplay() async throws -> Result {
        guard let display = NSScreen.main else { throw CaptureError.noDisplay }
        let size = CGSize(width: 400, height: 300)
        let origin = CGPoint(x: display.frame.midX - size.width / 2,
                             y: display.frame.midY - size.height / 2)
        return try await capture(rect: CGRect(origin: origin, size: size), on: display)
    }

    @MainActor
    func capture(rect: CGRect, on display: NSScreen) async throws -> Result {
        try preflight()
        let bounded = rect.intersection(display.frame)
        guard !bounded.isEmpty else { throw CaptureError.noDisplay }

        let (sourceRect, pixelSize) = try await computeSourceRect(for: bounded, on: display)

        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.sourceRect = sourceRect

        let filter = try await contentFilter(for: display)
        let stream = try SCStream(filter: filter, configuration: config, delegate: nil)
        let collector = FirstFrameCollector()
        try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        defer { Task { try? await stream.stopCapture(); try? stream.removeStreamOutput(collector, type: .screen) } }

        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            if let image = collector.image { return Result(image: NSImage(cgImage: image, size: bounded.size)) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw CaptureError.frameTimeout
    }

    // MARK: - Helpers
    @MainActor private func preflight() throws {
        guard #available(macOS 13.0, *) else { throw CaptureError.unsupported }
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess(); throw CaptureError.permissionDenied }
    }

    @MainActor private func computeSourceRect(for bounded: CGRect, on display: NSScreen) async throws -> (CGRect, CGSize) {
        // Convert to display-local coordinates and flip for SCStream
        let local = CGRect(x: bounded.minX - display.frame.minX,
                           y: bounded.minY - display.frame.minY,
                           width: bounded.width,
                           height: bounded.height)
        let flippedY = display.frame.height - local.origin.y - local.height
        let sourceRect = CGRect(x: local.origin.x, y: flippedY, width: local.width, height: local.height)
        return (sourceRect, bounded.size)
    }

    @MainActor private func contentFilter(for display: NSScreen) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        guard let id = display.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let scDisplay = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        return SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
    }
}

@available(macOS 13.0, *)
private final class FirstFrameCollector: NSObject, SCStreamOutput {
    private let ciContext = CIContext(options: nil)
    var image: CGImage?

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard image == nil, outputType == .screen,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvImageBuffer: buffer)
        image = ciContext.createCGImage(ci, from: ci.extent)
    }
}
