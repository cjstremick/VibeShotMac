import AppKit

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
            require(beforePositions == afterPositions,
                    "Accepted glyph positions changed for \(sample.debugDescription): \(beforePositions) -> \(afterPositions)")
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
