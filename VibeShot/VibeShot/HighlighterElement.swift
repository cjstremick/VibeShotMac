import AppKit

/// Translucent marker placed over the screenshot and below other annotations.
final class HighlighterElement: MarkupElement, ResizableElement {
    let id = UUID()
    var isSelected = false
    let zOrder = 50
    private var rect: CGRect
    private let color: NSColor
    var bounds: CGRect { rect }

    init(rect: CGRect, color: NSColor = .systemYellow) {
        self.rect = rect.standardized
        self.color = color
    }

    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(color.withAlphaComponent(0.35).cgColor)
        context.fill(rect)
        context.restoreGState()
        if isSelected && mode == .editor {
            context.saveGState()
            context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
            context.setLineWidth(MarkupConstants.Selection.lineWidth)
            context.setLineDash(phase: 0, lengths: MarkupConstants.Selection.dashPattern)
            context.stroke(rect)
            context.restoreGState()
        }
    }
    func contains(point: CGPoint) -> Bool { rect.contains(point) }
    func move(by translation: CGPoint) { rect = rect.offsetBy(dx: translation.x, dy: translation.y) }
    func resize(handle: ResizeHandle, to point: CGPoint) {
        switch handle {
        case .topLeft:
            let right = rect.maxX, bottom = rect.maxY
            rect = CGRect(x: min(point.x, right - 3), y: min(point.y, bottom - 3),
                          width: max(3, right - point.x), height: max(3, bottom - point.y))
        case .topRight:
            let bottom = rect.maxY
            rect = CGRect(x: rect.minX, y: min(point.y, bottom - 3),
                          width: max(3, point.x - rect.minX), height: max(3, bottom - point.y))
        case .bottomLeft:
            let right = rect.maxX
            rect = CGRect(x: min(point.x, right - 3), y: rect.minY,
                          width: max(3, right - point.x), height: max(3, point.y - rect.minY))
        case .bottomRight:
            rect.size = NSSize(width: max(3, point.x - rect.minX), height: max(3, point.y - rect.minY))
        }
    }
    func duplicate() -> any MarkupElement { HighlighterElement(rect: rect, color: color) }
}
