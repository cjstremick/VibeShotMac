import AppKit
import AVFoundation

/// Render the actual live field's layout without its caret or selection highlight.
private final class LiveTextPreview: MarkupElement {
    let id = UUID()
    var isSelected = false
    let zOrder = 0
    let field: NSTextView
    init(_ field: NSTextView) { self.field = field }
    var bounds: CGRect { field.frame }
    func draw(in context: CGContext, mode: MarkupRenderMode) {
        let manager = field.layoutManager!
        let container = field.textContainer!
        manager.ensureLayout(for: container)
        let range = manager.glyphRange(for: container)
        let point = CGPoint(x: field.frame.minX + field.textContainerOrigin.x,
                            y: field.frame.minY + field.textContainerOrigin.y)
        manager.drawBackground(forGlyphRange: range, at: point)
        manager.drawGlyphs(forGlyphRange: range, at: point)
    }
    func contains(point: CGPoint) -> Bool { bounds.contains(point) }
    func duplicate() -> any MarkupElement { self }
    func move(by translation: CGPoint) {}
}

@main
struct RegressionTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func bitmap(_ image: NSImage) -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    }
    static func fixture(scale: Int) -> NSImage {
        let context = CGContext(data: nil, width: 120 * scale, height: 100 * scale,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 120 * scale, height: 50 * scale))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 50 * scale, width: 120 * scale, height: 50 * scale))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 120, height: 100))
    }
    static func pixels(_ image: NSImage) throws -> Data { try CompositeRenderer.png(image) }

    static func videoSampleBuffer(width: Int, height: Int, at time: CMTime) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attributes as CFDictionary,
                                  &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }
        return sampleBuffer
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        for scale in [1, 2] {
            let base = fixture(scale: scale)
            let top = try CompositeRenderer.crop(base, topOriginRect: CGRect(x: 10, y: 5, width: 40, height: 20))
            let rep = bitmap(top)
            require(rep.pixelsWide == 40 * scale && rep.pixelsHigh == 20 * scale, "Crop must preserve source pixels")
            let color = rep.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
            require(color.redComponent > 0.9 && color.blueComponent < 0.1, "Top-origin crop must extract red top, not blue bottom")
            let roundTrip = bitmap(try CompositeRenderer.render(base: base, elements: []))
            require(roundTrip.pixelsWide == 120 * scale && roundTrip.pixelsHigh == 100 * scale, "Render dimensions changed")
            require(roundTrip.colorAt(x: 10, y: 5)!.usingColorSpace(.sRGB)!.redComponent > 0.9, "Render flipped the base image")
            let elements: [any MarkupElement] = [
                ArrowElement(startPoint: CGPoint(x: 10, y: 20), endPoint: CGPoint(x: 90, y: 40)),
                LineElement(startPoint: CGPoint(x: 10, y: 80), endPoint: CGPoint(x: 90, y: 80)),
                RectangleElement(startPoint: CGPoint(x: 20, y: 30), endPoint: CGPoint(x: 70, y: 60)),
                StepCounterElement(centerPoint: CGPoint(x: 60, y: 50), stepNumber: 2),
                TextElement(position: CGPoint(x: 10, y: 10), text: "UP 123"),
                BlurElement(rect: CGRect(x: 10, y: 10, width: 20, height: 20), baseImage: base),
                HighlighterElement(rect: CGRect(x: 5, y: 5, width: 15, height: 10))
            ]
            let clean = try pixels(CompositeRenderer.render(base: base, elements: elements))
            elements.forEach { $0.isSelected = true }
            let selected = try pixels(CompositeRenderer.render(base: base, elements: elements))
            require(clean == selected, "Selection decoration leaked into exported image")
            require(elements.allSatisfy { $0.isSelected }, "Export changed editor selection")
            let blur = BlurElement.createBlurredImage(from: base, rect: CGRect(x: 10, y: 5, width: 20, height: 20))!
            let blurRep = bitmap(blur)
            require(blurRep.pixelsWide == 20 * scale, "Blur lost Retina pixels")
            require(blurRep.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!.redComponent > 0.8, "Blur sampled wrong vertical region")
        }

        let line = LineElement(startPoint: CGPoint(x: 10, y: 40), endPoint: CGPoint(x: 90, y: 40), color: .white, lineWidth: 4)
        let arrow = ArrowElement(startPoint: CGPoint(x: 10, y: 40), endPoint: CGPoint(x: 90, y: 40), color: .white, lineWidth: 4)
        let lineImage = bitmap(try CompositeRenderer.render(base: fixture(scale: 1), elements: [line]))
        let arrowImage = bitmap(try CompositeRenderer.render(base: fixture(scale: 1), elements: [arrow]))
        require(lineImage.colorAt(x: 80, y: 44)!.usingColorSpace(.sRGB)!.blueComponent < 0.5,
                "Plain line grew an arrowhead: \(lineImage.colorAt(x: 80, y: 44)!)")
        require(arrowImage.colorAt(x: 80, y: 44)!.usingColorSpace(.sRGB)!.blueComponent > 0.9,
                "Arrow lost its arrowhead")
        require(line.contains(point: CGPoint(x: 50, y: 40)) && !line.contains(point: CGPoint(x: 50, y: 70)), "Line hit testing failed")
        require(line.hitTestEndpoint(point: line.startPosition) == true, "Line start handle missing")
        line.setEndPoint(CGPoint(x: 95, y: 60))
        line.move(by: CGPoint(x: 2, y: 3))
        let lineCopy = line.duplicate() as! LineElement
        require(lineCopy.endPosition == CGPoint(x: 97, y: 63), "Line snapshot lost resized/moved endpoints")

        let highlight = HighlighterElement(rect: CGRect(x: 5, y: 5, width: 25, height: 15))
        let highlightCopy = highlight.duplicate() as! HighlighterElement
        highlight.move(by: CGPoint(x: 5, y: 10))
        require(highlightCopy.bounds == CGRect(x: 5, y: 5, width: 25, height: 15), "Highlight snapshots share mutable geometry")
        highlight.resize(handle: .bottomRight, to: CGPoint(x: 50, y: 40))
        require(highlight.bounds.maxX == 50 && highlight.bounds.maxY == 40, "Highlight resize failed")

        let canvas = MarkupCanvasView(baseImage: fixture(scale: 1))
        let existing = TextElement(position: CGPoint(x: 10, y: 10), text: "Original")
        canvas.markupElements = [existing]
        canvas.setCurrentTool(.text)
        canvas.startTextEditing(at: CGPoint(x: 12, y: 12))
        canvas.textView?.string = "Changed"
        canvas.textViewDidReceiveEscape()
        require(canvas.markupElements.count == 1 && existing.text == "Original", "Escape deleted existing text")
        require(!existing.isBeingEdited, "Cancelled text remains hidden")
        canvas.markupElements = []
        canvas.startTextEditing(at: CGPoint(x: 10, y: 10))
        canvas.textViewDidReceiveEscape()
        require(canvas.markupElements.isEmpty, "Escape must discard a new annotation")
        canvas.startTextEditing(at: CGPoint(x: 10, y: 10))
        canvas.textView?.string = "Committed"
        canvas.endTextEditingIfActive()
        require((canvas.markupElements.first as? TextElement)?.text == "Committed", "Export preparation lost active text")

        // Editing and accepting must retain the same glyph layout, including wraps and whitespace.
        for sample in ["A longer sentence that wraps into several lines without changing on accept.",
                       "  Indented first line\nSecond line\n", "Supercalifragilisticexpialidocious"] {
            canvas.markupElements = []
            canvas.startTextEditing(at: CGPoint(x: 10, y: 10))
            let field = canvas.textView!
            field.string = sample
            canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: field))
            let manager = field.layoutManager!
            let container = field.textContainer!
            manager.ensureLayout(for: container)
            let range = manager.glyphRange(for: container)
            let beforePositions = (range.location..<NSMaxRange(range)).map { manager.location(forGlyphAt: $0) }
            var beforeLines: [NSRange] = []
            manager.enumerateLineFragments(forGlyphRange: range) { _, _, _, glyphRange, _ in beforeLines.append(glyphRange) }
            let beforeSize = field.frame.size
            let beforeOrigin = field.frame.origin
            require(container.containerSize.width == 110, "Editor width must stay tied to the screenshot edge")
            require(field.textContainerOrigin == .zero, "Editor inset shifts accepted text")
            let livePixels = try pixels(CompositeRenderer.render(base: fixture(scale: 2), elements: [LiveTextPreview(field)]))
            canvas.endTextEditingIfActive()
            let acceptedPixels = try pixels(CompositeRenderer.render(base: fixture(scale: 2), elements: canvas.markupElements))
            require(livePixels == acceptedPixels, "Text pixels changed when accepting the annotation")
            let accepted = canvas.markupElements[0] as! TextElement
            require(accepted.text == sample, "Accepting text changed spaces or explicit newlines")
            require(accepted.bounds.size == beforeSize && accepted.bounds.origin == beforeOrigin,
                    "Accepting text changed its size or position: before \(beforeSize) at \(beforeOrigin), after \(accepted.bounds), sample \(sample.debugDescription)")
            let layout = accepted.makeLayout(text: accepted.text)
            layout.manager.ensureLayout(for: layout.container)
            let afterRange = layout.manager.glyphRange(for: layout.container)
            let afterPositions = (afterRange.location..<NSMaxRange(afterRange)).map { layout.manager.location(forGlyphAt: $0) }
            var afterLines: [NSRange] = []
            layout.manager.enumerateLineFragments(forGlyphRange: afterRange) { _, _, _, glyphRange, _ in afterLines.append(glyphRange) }
            // A live NSTextView and a standalone layout manager can allocate different
            // line-fragment rectangles on different macOS versions. Compare actual
            // wrapping and glyph positions, not the unused allocation around a line.
            // Exact rendered-pixel and annotation-size checks above remain in place.
            require(range == afterRange && beforeLines == afterLines,
                    "Accepted line breaks changed for \(sample.debugDescription): \(beforeLines) -> \(afterLines)")
            // TextKit on macOS 15 can differ by a few billionths of a point
            // between live and standalone layouts. One millionth of a point
            // tolerates that rounding while remaining far below a display pixel.
            let glyphTolerance: CGFloat = 0.000001
            let positionsMatch = beforePositions.count == afterPositions.count &&
                zip(beforePositions, afterPositions).allSatisfy { before, after in
                    abs(before.x - after.x) <= glyphTolerance &&
                    abs(before.y - after.y) <= glyphTolerance
                }
            require(positionsMatch,
                    "Accepted glyph positions changed beyond \(glyphTolerance) points for \(sample.debugDescription): \(beforePositions) -> \(afterPositions)")
            require(afterLines.count > 1, "Fixture must exercise wrapping or explicit line breaks")
            let clone = accepted.duplicate() as! TextElement
            require(clone.layoutWidth == accepted.layoutWidth && clone.bounds == accepted.bounds,
                    "Undo snapshots lost wrapped layout")
            // Reopen with a different current color: the existing annotation keeps its own style.
            MarkupColorManager.shared.currentColor = .green
            canvas.startTextEditing(at: CGPoint(x: 12, y: 12))
            require(canvas.textView!.textColor == accepted.textColor, "Reopening changed text color")
            require(canvas.textView!.frame.size == beforeSize, "Reopening changed wrapping")
            canvas.textViewDidReceiveEscape()
        }

        // Real responder routing and toolbar construction without capturing the user's screen.
        let editor = MarkupEditorController(baseImage: fixture(scale: 2))
        let window = editor.window!
        require(window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "save" } == true, "Save toolbar item missing")
        require(window.styleMask.contains(.resizable), "Editor cannot resize")
        require(window.minSize.width >= MarkupToolbarMetrics.width,
                "Editor can be narrower than its toolbar: \(window.minSize.width) < \(MarkupToolbarMetrics.width)")
        require((window.contentView?.bounds.width ?? 0) >= MarkupToolbarMetrics.width,
                "Small capture window does not fit the markup toolbar")
        let markupItem = window.toolbar!.items.first { $0.itemIdentifier.rawValue == "markup" }!
        require(markupItem.menuFormRepresentation?.submenu?.items.count == MarkupTool.allCases.count + 3,
                "Narrow windows lost access to markup and style commands")
        let scroll = window.contentView as! NSScrollView
        let centered = scroll.contentView.constrainBoundsRect(NSRect(x: 0, y: 0, width: 300, height: 250))
        require(centered.minX < 0 && centered.minY < 0, "Small screenshots must stay centered")
        var responder: NSResponder? = window
        var foundController = false
        while let current = responder {
            if current === editor { foundController = true; break }
            responder = current.nextResponder
        }
        require(foundController, "Editor actions are absent from the responder chain")
        editor.toolbarDidSelectTool(.line)
        editor.canvasDidFinishDrawing(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 40))
        let drawingCanvas = scroll.documentView as! MarkupCanvasView
        require(drawingCanvas.markupElements.first is LineElement && !(drawingCanvas.markupElements.first is ArrowElement), "Line tool created an arrow")
        editor.undo(nil)
        require(drawingCanvas.markupElements.isEmpty, "Undo did not remove line")
        editor.redo(nil)
        require(drawingCanvas.markupElements.count == 1 && !(drawingCanvas.markupElements.first is ArrowElement), "Redo changed line type")

        let originalDrawingColor = MarkupColorManager.shared.currentColor
        editor.toolbarDidSelectTool(.highlighter)
        editor.toolbarDidSelectColor(.cyan)
        require(MarkupColorManager.shared.currentColor == originalDrawingColor, "Highlighter changed the drawing color")
        require(drawingCanvas.highlightColor == .cyan, "Highlighter preview ignored its selected color")
        editor.canvasDidFinishDrawing(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 20, y: 15))
        require(drawingCanvas.markupElements.last is HighlighterElement, "Highlighter tool did not create a callout")
        editor.undo(nil)
        require(drawingCanvas.markupElements.count == 1, "Undo did not remove highlighter")
        editor.redo(nil)
        require(drawingCanvas.markupElements.last is HighlighterElement, "Redo lost highlighter")

        // Cancelling a new text annotation must not consume an undo step.
        let textUndoEditor = MarkupEditorController(baseImage: fixture(scale: 1))
        let textUndoScroll = textUndoEditor.window!.contentView as! NSScrollView
        let textUndoCanvas = textUndoScroll.documentView as! MarkupCanvasView
        textUndoEditor.toolbarDidSelectTool(.line)
        textUndoEditor.canvasDidFinishDrawing(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 40))
        require(textUndoCanvas.markupElements.count == 1, "Line setup failed")
        textUndoEditor.toolbarDidSelectTool(.text)
        textUndoEditor.canvasDidStartDrawing(at: CGPoint(x: 20, y: 20))
        textUndoCanvas.textViewDidReceiveEscape()
        require(textUndoCanvas.textView == nil, "Text editor did not close")
        textUndoEditor.undo(nil)
        require(textUndoCanvas.markupElements.isEmpty, "Cancelling text left an empty undo step")

        // Stopping an idle recorder must fail cleanly rather than start a writer.
        var idleRecordingFailed = false
        ScreenRecorder().stop { result in
            if case .failure = result { idleRecordingFailed = true }
        }
        require(idleRecordingFailed, "Stopping an idle recorder did not report an error")

        // Encoded dimensions stay even and within H.264-friendly limits.
        let smallOutput = ScreenRecorder.outputPixelSize(for: CGSize(width: 101, height: 77), scale: 2)
        require(smallOutput.width % 2 == 0 && smallOutput.height % 2 == 0,
                "Recording dimensions must be even: \(smallOutput)")
        let hugeOutput = ScreenRecorder.outputPixelSize(for: CGSize(width: 3008, height: 1692), scale: 2)
        require(hugeOutput.width <= 3840 && hugeOutput.height <= 2160,
                "Recording dimensions exceeded the 4K cap: \(hugeOutput)")
        require(hugeOutput.width % 2 == 0 && hugeOutput.height % 2 == 0,
                "Capped recording dimensions must be even: \(hugeOutput)")

        // The H.264 writer configuration must produce a non-empty file from
        // frames. This catches dimension/profile/bitrate mistakes without a
        // real screen capture.
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeShotTest-\(UUID().uuidString).mp4")
        let (videoWriter, videoInput) = try ScreenRecorder.makeWriter(url: videoURL,
                                                                     pixelWidth: 320,
                                                                     pixelHeight: 240)
        var frameTime = CMTime.zero
        for index in 0..<6 {
            guard let sample = videoSampleBuffer(width: 320, height: 240, at: frameTime) else {
                fatalError("Could not build a synthetic video frame")
            }
            let readyDeadline = Date().addingTimeInterval(5)
            while !videoInput.isReadyForMoreMediaData && Date() < readyDeadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            if index == 0 { videoWriter.startSession(atSourceTime: frameTime) }
            require(videoInput.append(sample),
                    "Synthetic frame append failed: \(String(describing: videoWriter.error))")
            frameTime = CMTimeAdd(frameTime, CMTime(value: 1, timescale: 30))
        }
        videoInput.markAsFinished()
        videoWriter.finishWriting {}
        let finishDeadline = Date().addingTimeInterval(10)
        while videoWriter.status == .writing && Date() < finishDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        require(videoWriter.status == .completed,
                "Synthetic writer did not complete: \(String(describing: videoWriter.error))")
        let videoAttributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
        let videoSize = (videoAttributes?[.size] as? Int) ?? 0
        require(videoSize > 0, "Synthetic recording file is empty")
        try? FileManager.default.removeItem(at: videoURL)

        // The on-screen Stop control stays just outside the recorded region.
        let displayFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let recordRegion = CGRect(x: 300, y: 300, width: 400, height: 240)
        let stopFrame = RecordingHUDController.stopButtonFrame(
            region: recordRegion, displayFrame: displayFrame,
            size: RecordingHUDController.stopButtonSize, gap: 10)
        require(!recordRegion.intersects(stopFrame), "Stop control overlaps the recording region")
        require(displayFrame.contains(stopFrame), "Stop control left the display")

        // A region flush with the bottom edge pushes the control above it.
        let bottomRegion = CGRect(x: 200, y: 0, width: 300, height: 120)
        let bottomStop = RecordingHUDController.stopButtonFrame(
            region: bottomRegion, displayFrame: displayFrame,
            size: RecordingHUDController.stopButtonSize, gap: 10)
        require(!bottomRegion.intersects(bottomStop), "Stop control overlapped a bottom-edge region")
        require(displayFrame.contains(bottomStop), "Stop control left the display at the bottom edge")

        // Recording settings persist independently of the real defaults.
        let suiteName = "VibeShotTests-\(UUID().uuidString)"
        if let testDefaults = UserDefaults(suiteName: suiteName) {
            testDefaults.removePersistentDomain(forName: suiteName)
            let settings = RecordingSettings(defaults: testDefaults)
            require(settings.destination == .ask, "Default recording destination changed")
            settings.destination = .clipboard
            require(settings.destination == .clipboard, "Recording destination did not persist")
            settings.countdownSeconds = 5
            require(settings.countdownSeconds == 5, "Countdown did not persist")
            settings.countdownSeconds = 7
            require(settings.countdownSeconds == 0, "Invalid countdown was not rejected")
            require(settings.showPointerActivity == false, "Pointer activity should default to off")
            settings.showPointerActivity = true
            require(settings.showPointerActivity, "Pointer activity did not persist")
            require(RecordingSettings.recordingFileName().hasSuffix(".mp4"),
                    "Recording filename is missing its extension")
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let settingsWindow = SettingsWindowController()
        require(settingsWindow.window?.title == "VibeShot Settings", "Settings window did not build")

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeShotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let first = RecordingStorage.uniqueDestination(in: scratch, name: "Clip.mp4")
        try Data().write(to: first)
        let second = RecordingStorage.uniqueDestination(in: scratch, name: "Clip.mp4")
        require(second.lastPathComponent == "Clip 2.mp4", "Unique destination did not avoid a collision")
        let preview = try CompositeRenderer.render(base: fixture(scale: 2), elements: [
            TextElement(position: CGPoint(x: 10, y: 5), text: "UP 123", color: .white),
            StepCounterElement(centerPoint: CGPoint(x: 60, y: 65), stepNumber: 2)
        ])
        if !CommandLine.arguments.contains("--interactive") {
            try CompositeRenderer.png(preview).write(to: URL(fileURLWithPath: "build/render-check.png"))
        }
        let previewContext = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        previewContext.setFillColor(NSColor.white.cgColor)
        previewContext.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        let previewBase = NSImage(cgImage: previewContext.makeImage()!, size: NSSize(width: 640, height: 400))
        let detailBase = try CompositeRenderer.render(base: previewBase, elements: [
            TextElement(position: CGPoint(x: 25, y: 30), text: "Detail 123", color: .black, layoutWidth: 110)
        ])
        let featurePreview = try CompositeRenderer.render(base: detailBase, elements: [
            HighlighterElement(rect: CGRect(x: 20, y: 28, width: 125, height: 23)),
            TextElement(position: CGPoint(x: 25, y: 150), text: "Text still wraps consistently.\nLines stay plain. Highlight what matters.", color: .black, layoutWidth: 300),
            LineElement(startPoint: CGPoint(x: 25, y: 330), endPoint: CGPoint(x: 500, y: 330), color: .systemBlue, lineWidth: 4)
        ])
        let highlightedPixels = bitmap(featurePreview)
        let tint = highlightedPixels.colorAt(x: 22, y: 35)!.usingColorSpace(.sRGB)!
        require(tint.redComponent > 0.8 && tint.greenComponent > 0.6 && tint.blueComponent < 0.85,
                "Highlighter did not tint the white background yellow")
        var foundBlack = false
        for y in 32..<48 {
            for x in 26..<120 {
                let color = highlightedPixels.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.15 { foundBlack = true }
            }
        }
        require(foundBlack, "Highlighter obscured the underlying black text")
        if !CommandLine.arguments.contains("--interactive") {
            try CompositeRenderer.png(featurePreview).write(to: URL(fileURLWithPath: "build/followup-preview.png"))
        }
        if CommandLine.arguments.contains("--interactive") {
            let delegate = AppDelegate()
            delegate.setupApplicationMenu()
            NSApp.setActivationPolicy(.regular)
            window.setContentSize(NSSize(width: 900, height: 450))
            editor.show()
            editor.onClose = { NSApp.terminate(nil) }
            withExtendedLifetime(delegate) { NSApp.run() }
        }
        print("PASS: 1×/2× crop, output dimensions, selection-free export, blur region, text WYSIWYG wrapping, line and highlighter drawing/undo, toolbar and responder routing")
    }
}
