import AppKit
import ScreenCaptureKit

// MARK: - Public API
protocol RegionCapturing {
    @MainActor func capture(rect: CGRect, on display: NSScreen) async throws -> QuickSCKitCapture.Result
}

final class QuickSCKitCapture: RegionCapturing {
    
    struct Result { let image: NSImage }
    
    enum CaptureError: Error { case unsupported, noDisplay, frameTimeout, permissionDenied }
    
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
        config.showsCursor = false
        
        let filter = try await contentFilter(for: display)
        
        return try await withCheckedThrowingContinuation { continuation in
            let collector = FirstFrameCollector(continuation: continuation, size: bounded.size)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            do {
                try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: .main)
                collector.stream = stream
                
                stream.startCapture { error in
                    if let error = error {
                        // Only resume if not already resumed (e.g. by timeout)
                        if collector.continuation != nil {
                            continuation.resume(throwing: error)
                            collector.continuation = nil
                            collector.stream = nil
                        }
                    }
                }
                
                // Start timeout timer
                collector.startTimeout()
                
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
    var continuation: CheckedContinuation<QuickSCKitCapture.Result, Error>?
    private let size: CGSize
    var stream: SCStream?
    
    init(continuation: CheckedContinuation<QuickSCKitCapture.Result, Error>, size: CGSize) {
        self.continuation = continuation
        self.size = size
    }
    
    func startTimeout() {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second timeout
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(throwing: QuickSCKitCapture.CaptureError.frameTimeout)
                try? await self.stream?.stopCapture()
                self.stream = nil
            }
        }
    }
    
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard let continuation = continuation, outputType == .screen,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        self.continuation = nil
        
        let ci = CIImage(cvImageBuffer: buffer)
        if let cgImage = ciContext.createCGImage(ci, from: ci.extent) {
            let nsImage = NSImage(cgImage: cgImage, size: size)
            continuation.resume(returning: QuickSCKitCapture.Result(image: nsImage))
        } else {
            continuation.resume(throwing: QuickSCKitCapture.CaptureError.frameTimeout)
        }
        
        Task {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }
}
