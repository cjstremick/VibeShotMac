import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records a screen region to an H.264 `.mp4` file.
///
/// This pass records video only. There is deliberately no audio track, so the
/// recorder needs no microphone entitlement and no extra permission beyond the
/// existing Screen Recording grant. It reuses the still-capture region geometry
/// so a recording covers exactly the same pixels as a screenshot of that region.
final class ScreenRecorder: NSObject {

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording
        case displayUnavailable
        case writerCreationFailed(String)
        case writingFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "A recording is already in progress."
            case .notRecording: return "No recording is in progress."
            case .displayUnavailable: return "The selected display is not available for recording."
            case .writerCreationFailed(let reason): return "Could not start recording: \(reason)"
            case .writingFailed(let detail): return "The recording could not be finished: \(detail)"
            }
        }
    }

    /// Called on the main queue once writing has finished or failed.
    typealias Completion = (Result<URL, Error>) -> Void

    private let queue = DispatchQueue(label: "com.stremick.VibeShot.recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var isRecording = false
    private var pendingCompletion: Completion?

    /// Set before `start`. Called on the main queue if the stream stops on its
    /// own, such as a display change or a revoked Screen Recording grant.
    var onUnexpectedStop: Completion?

    var isActive: Bool { isRecording }

    /// Starts capturing `region` (global screen coordinates) on `display`.
    /// `excludingWindowNumbers` should contain the recording HUD windows so the
    /// border/dim/Stop control stay out of the video. Any other VibeShot window
    /// (such as the pointer-effects overlay) is intentionally captured.
    @MainActor
    func start(region: CGRect,
               on display: NSScreen,
               showsCursor: Bool = false,
               excludingWindowNumbers: Set<CGWindowID> = []) async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let bounded = region.intersection(display.frame)
        guard !bounded.isEmpty else { throw RecorderError.displayUnavailable }

        // Match the still-capture conversion: display-local points, Y flipped
        // for SCStream, and a pixel size that respects the backing scale.
        let local = CGRect(x: bounded.minX - display.frame.minX,
                           y: bounded.minY - display.frame.minY,
                           width: bounded.width,
                           height: bounded.height)
        let flippedY = display.frame.height - local.origin.y - local.height
        let sourceRect = CGRect(x: local.origin.x, y: flippedY, width: local.width, height: local.height)
        let outputSize = Self.outputPixelSize(for: bounded.size,
                                              scale: display.backingScaleFactor)
        let pixelWidth = outputSize.width
        let pixelHeight = outputSize.height

        let filter = try await Self.contentFilter(for: display,
                                                  excludingWindowNumbers: excludingWindowNumbers)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeShot-Recording-\(UUID().uuidString).mp4")
        let (writer, input) = try Self.makeWriter(url: url,
                                                  pixelWidth: pixelWidth,
                                                  pixelHeight: pixelHeight)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = showsCursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        // Publish state before the stream starts delivering frames.
        self.stream = stream
        self.writer = writer
        self.videoInput = input
        self.outputURL = url
        self.sessionStarted = false

        do {
            try await stream.startCapture()
            isRecording = true
        } catch {
            self.stream = nil
            self.writer = nil
            self.videoInput = nil
            self.outputURL = nil
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Stops the stream and finalizes the file. The result carries the temporary
    /// MP4 URL, which the caller must move or discard.
    func stop(completion: @escaping Completion) {
        guard isRecording, let stream, let writer, let videoInput, let url = outputURL else {
            completion(.failure(RecorderError.notRecording))
            return
        }
        isRecording = false
        pendingCompletion = completion

        // Capture self strongly. The AppDelegate drops its reference as soon as
        // Stop is pressed, so a weak capture here let the recorder deallocate
        // before the stream finished and the save step was silently skipped.
        stream.stopCapture { [self] error in
            if let error {
                NSLog("[ScreenRecorder] stopCapture error: \(Self.describe(error))")
            }
            self.queue.async { [self] in
                if self.sessionStarted {
                    videoInput.markAsFinished()
                } else {
                    // No frames arrived, so there is nothing worth keeping.
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    self.finish(.failure(RecorderError.writerCreationFailed("no frames were captured")))
                    return
                }

                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        self.finish(.success(url))
                    } else {
                        NSLog("[ScreenRecorder] finishWriting failed: \(Self.describe(writer.error))")
                        try? FileManager.default.removeItem(at: url)
                        self.finish(.failure(RecorderError.writingFailed(Self.describe(writer.error))))
                    }
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        DispatchQueue.main.async {
            self.cleanup()
            let completion = self.pendingCompletion
            self.pendingCompletion = nil
            completion?(result)
        }
    }

    private func cleanup() {
        stream = nil
        writer = nil
        videoInput = nil
        outputURL = nil
        sessionStarted = false
    }

    /// Encoded pixel size for a captured region. H.264 requires even dimensions,
    /// and very large Retina regions can exceed the hardware encoder's limits;
    /// cap at 4K and let ScreenCaptureKit scale the source region to fit.
    static func outputPixelSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let rawWidth = max(4, Int((size.width * scale).rounded()))
        let rawHeight = max(4, Int((size.height * scale).rounded()))
        let factor = min(1.0, min(3840.0 / Double(rawWidth), 2160.0 / Double(rawHeight)))
        let width = max(4, Int((Double(rawWidth) * factor).rounded()) & ~1)
        let height = max(4, Int((Double(rawHeight) * factor).rounded()) & ~1)
        return (width, height)
    }

    /// Creates the H.264 writer. Shared with the regression test so the encoder
    /// configuration is exercised without a real screen capture.
    static func makeWriter(url: URL, pixelWidth: Int, pixelHeight: Int) throws -> (AVAssetWriter, AVAssetWriterInput) {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw RecorderError.writerCreationFailed(describe(error))
        }

        // ~2 bits per pixel, clamped, is plenty for screen content and keeps the
        // encoder well inside its level limits.
        let bitrate = max(2_000_000, min(20_000_000, pixelWidth * pixelHeight * 2))
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: compression
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writerCreationFailed("unsupported video settings")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw RecorderError.writerCreationFailed(describe(writer.error))
        }
        return (writer, input)
    }

    /// Reads the full domain/code text and the underlying error, because
    /// `localizedDescription` alone is often just "The operation could not be completed".
    static func describe(_ error: Error?) -> String {
        guard let error else { return "unknown error" }
        let ns = error as NSError
        var text = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " | \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
        }
        return text
    }

    private static func contentFilter(for display: NSScreen,
                                      excludingWindowNumbers: Set<CGWindowID>) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        guard let id = display.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let scDisplay = content.displays.first(where: { $0.displayID == id }) else {
            throw RecorderError.displayUnavailable
        }

        // Exclude only the recording HUD windows. The pointer-effects overlay is
        // a VibeShot window that must stay in the capture so its ripples appear
        // in the recorded video.
        if !excludingWindowNumbers.isEmpty {
            let excluded = content.windows.filter { excludingWindowNumbers.contains($0.windowID) }
            NSLog("[ScreenRecorder] Excluding \(excluded.count) HUD window(s) from the recording")
            return SCContentFilter(display: scDisplay, excludingWindows: excluded)
        }

        // Fallback when no HUD numbers were supplied: exclude all own windows.
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownWindows = ownBundleIdentifier.map { identifier in
            content.windows.filter { $0.owningApplication?.bundleIdentifier == identifier }
        } ?? []
        return SCContentFilter(display: scDisplay, excludingWindows: ownWindows)
    }
}

// MARK: - Sample delivery

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let writer, let videoInput else { return }
        if writer.status == .failed {
            NSLog("[ScreenRecorder] Writer failed: \(Self.describe(writer.error))")
            return
        }
        guard writer.status == .writing else { return }

        // Only append fully rendered frames. ScreenCaptureKit also emits idle
        // and blank frames whose sample buffers must not go into the encoder.
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRaw = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        if !videoInput.append(sampleBuffer) {
            NSLog("[ScreenRecorder] Frame append failed: \(Self.describe(writer.error))")
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A display change or revoked permission ends the stream; keep what we
        // have and hand the file back through the same path as a manual stop.
        NSLog("[ScreenRecorder] Stream stopped with error: \(Self.describe(error))")
        guard isRecording else { return }
        stop { [weak self] result in
            self?.onUnexpectedStop?(result)
        }
    }
}
