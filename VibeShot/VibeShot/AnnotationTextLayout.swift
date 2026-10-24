import AppKit

/// The editor and rendered annotation use the same TextKit configuration.
/// Width stays fixed; content grows vertically without changing its line breaks.
final class AnnotationTextLayout {
    static let font = NSFont.systemFont(ofSize: MarkupConstants.Text.fontSize, weight: .medium)
    let storage: NSTextStorage
    let manager: NSLayoutManager
    let container: NSTextContainer
    let attributes: [NSAttributedString.Key: Any]

    init(text: String, color: NSColor, width: CGFloat?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        attributes = [.font: Self.font, .foregroundColor: color, .paragraphStyle: paragraph]
        storage = NSTextStorage(string: text, attributes: attributes)
        manager = NSLayoutManager()
        container = NSTextContainer(containerSize: NSSize(width: max(1, width ?? 1_000_000),
                                                         height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    var size: NSSize { Self.size(manager: manager, container: container) }

    static func size(manager: NSLayoutManager, container: NSTextContainer) -> NSSize {
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentTextContainer === container ? manager.extraLineFragmentRect : .zero
        let width = container.containerSize.width < 1_000_000
            ? container.containerSize.width : max(1, ceil(used.maxX) + 1)
        return NSSize(width: width,
                      height: max(ceil(manager.defaultLineHeight(for: font)), ceil(max(used.maxY, extra.maxY))))
    }

    func draw(at point: CGPoint) {
        manager.ensureLayout(for: container)
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: point)
        manager.drawGlyphs(forGlyphRange: range, at: point)
    }
}
