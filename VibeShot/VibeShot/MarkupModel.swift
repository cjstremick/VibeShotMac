import Foundation
import Cocoa

// MARK: - Constants
/// Centralized constants for consistent styling and behavior
enum MarkupConstants {
    /// Selection and element styling
    enum Selection {
        static let color = NSColor.selectedControlColor
        static let lineWidth: CGFloat = 2.0
        static let dashPattern: [CGFloat] = [4, 4]
        static let inset: CGFloat = -5
    }
    
    /// Arrow element sizing
    enum Arrow {
        static let minimumLength: CGFloat = 30.0
        static let headLengthMultiplier: CGFloat = 5.0
        static let headAngle: CGFloat = .pi / 6  // 30 degrees
        static let lineEndRatio: CGFloat = 0.6
    }
    
    /// Rectangle element sizing
    enum Rectangle {
        static let minimumSize: CGFloat = 20.0
        static let cornerRadius: CGFloat = 8.0
    }
    
    /// Step counter sizing
    enum StepCounter {
        static let radius: CGFloat = 20.0
        static let fontSize: CGFloat = 14.0
    }
    
    /// Text element sizing
    enum Text {
        static let fontSize: CGFloat = 18.0
        static let minimumWidth: CGFloat = 100.0
        static let minimumHeight: CGFloat = 30.0
    }
    
    /// Blur effect settings
    enum Blur {
        static let radius: CGFloat = 8.0
        static let minimumSize: CGFloat = 10.0
    }
    
    /// Resize handle settings
    enum ResizeHandle {
        static let size: CGFloat = 10.0
        static let minimumElementSize: CGFloat = 20.0
    }
    
    /// Undo/Redo settings
    enum UndoRedo {
        static let maxStackSize: Int = 30
    }
    
    /// Z-order for element layering (lower values draw first/behind)
    enum ZOrder {
        static let blur: Int = 0
        static let standard: Int = 100  // arrows, rectangles, text
        static let stepCounter: Int = 200
    }
}

// MARK: - Arrow Drawing Helper
/// Shared arrow geometry and drawing logic
enum ArrowDrawing {
    struct ArrowGeometry {
        let startPoint: CGPoint
        let endPoint: CGPoint
        let lineEndPoint: CGPoint
        let arrowPoint1: CGPoint
        let arrowPoint2: CGPoint
    }
    
    static func calculateGeometry(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> ArrowGeometry {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = lineWidth * MarkupConstants.Arrow.headLengthMultiplier
        
        let lineEndPoint = CGPoint(
            x: end.x - arrowLength * MarkupConstants.Arrow.lineEndRatio * cos(angle),
            y: end.y - arrowLength * MarkupConstants.Arrow.lineEndRatio * sin(angle)
        )
        
        let arrowAngle = MarkupConstants.Arrow.headAngle
        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        return ArrowGeometry(
            startPoint: start,
            endPoint: end,
            lineEndPoint: lineEndPoint,
            arrowPoint1: arrowPoint1,
            arrowPoint2: arrowPoint2
        )
    }
    
    static func draw(geometry: ArrowGeometry, color: CGColor, lineWidth: CGFloat, in context: CGContext) {
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw the line
        context.move(to: geometry.startPoint)
        context.addLine(to: geometry.lineEndPoint)
        context.strokePath()
        
        // Draw arrowhead
        context.setFillColor(color)
        context.move(to: geometry.endPoint)
        context.addLine(to: geometry.arrowPoint1)
        context.addLine(to: geometry.arrowPoint2)
        context.closePath()
        context.fillPath()
    }
}

// MARK: - Color Management
final class MarkupColorManager {
    static let shared = MarkupColorManager()
    
    private let colorKey = "VibeShot.MarkupColor"
    
    // Default dark pink color
    private let defaultColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0)
    
    private init() {}
    
    var currentColor: NSColor {
        get {
            guard let colorData = UserDefaults.standard.data(forKey: colorKey),
                  let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) else {
                return defaultColor
            }
            return color
        }
        set {
            if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) {
                UserDefaults.standard.set(colorData, forKey: colorKey)
            }
        }
    }
    
    func resetToDefault() {
        currentColor = defaultColor
    }
}

// MARK: - Line Thickness Management
final class MarkupLineThicknessManager {
    static let shared = MarkupLineThicknessManager()
    
    private let thicknessKey = "VibeShot.LineThickness"
    
    // Default line thickness (current arrow thickness)
    private let defaultThickness: CGFloat = 6.0
    
    // Available thickness options (2pt to 12pt)
    let availableThicknesses: [CGFloat] = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
    
    private init() {}
    
    var currentThickness: CGFloat {
        get {
            let thickness = UserDefaults.standard.double(forKey: thicknessKey)
            return thickness > 0 ? CGFloat(thickness) : defaultThickness
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: thicknessKey)
        }
    }
    
    func resetToDefault() {
        currentThickness = defaultThickness
    }
}

// MARK: - Markup Tool Types
enum MarkupTool: Int, CaseIterable {
    case selection = 0
    case arrow = 1
    case line = 7
    case rectangle = 2
    case stepCounter = 3
    case text = 4
    case blur = 5
    case crop = 6
    case highlighter = 8
    
    var displayName: String {
        switch self {
        case .selection: return "Selection"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .stepCounter: return "Step Counter"
        case .text: return "Text"
        case .blur: return "Blur"
        case .crop: return "Crop"
        case .highlighter: return "Highlighter"
        }
    }
    
    var iconName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .stepCounter: return "number.circle"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .crop: return "crop"
        case .highlighter: return "highlighter"
        }
    }
    
    var keyboardShortcut: String {
        switch self {
        case .selection: return "s"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .stepCounter: return "c"
        case .text: return "t"
        case .blur: return "b"
        case .crop: return "k"
        case .highlighter: return "h"
        }
    }
    
    var displayNameWithShortcut: String {
        return "\(displayName) (\(keyboardShortcut.uppercased()))"
    }
}

// MARK: - Base Markup Element Protocol
enum MarkupRenderMode { case editor, output }

protocol MarkupElement: AnyObject, Identifiable {
    var id: UUID { get }
    var isSelected: Bool { get set }
    var bounds: CGRect { get }
    var zOrder: Int { get }  // Lower values draw first (behind)
    
    func draw(in context: CGContext, mode: MarkupRenderMode)
    func contains(point: CGPoint) -> Bool
    func duplicate() -> any MarkupElement
    func move(by translation: CGPoint)
}

extension MarkupElement {
    func draw(in context: CGContext) { draw(in: context, mode: .editor) }
}

// MARK: - Resize Handle Types
enum ResizeHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    
    static var handleSize: CGFloat { MarkupConstants.ResizeHandle.size }
    
    func position(for bounds: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
        }
    }
    
    func rect(for bounds: CGRect) -> CGRect {
        let pos = position(for: bounds)
        return CGRect(
            x: pos.x - Self.handleSize / 2,
            y: pos.y - Self.handleSize / 2,
            width: Self.handleSize,
            height: Self.handleSize
        )
    }
    
    static func hitTest(point: CGPoint, bounds: CGRect) -> ResizeHandle? {
        for handle in ResizeHandle.allCases {
            if handle.rect(for: bounds).contains(point) {
                return handle
            }
        }
        return nil
    }
}

// MARK: - Resizable Element Protocol
protocol ResizableElement: MarkupElement {
    func resize(handle: ResizeHandle, to point: CGPoint)
    func drawResizeHandles(in context: CGContext)
}

extension ResizableElement {
    func drawResizeHandles(in context: CGContext) {
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.selectedControlColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [])
        
        for handle in ResizeHandle.allCases {
            let handleRect = handle.rect(for: bounds)
            context.fill(handleRect)
            context.stroke(handleRect)
        }
    }
}

// MARK: - Lines and Arrows
class LineElement: MarkupElement, ResizableElement {
    private let hasArrowhead: Bool
    let id = UUID()
    var isSelected: Bool = false
    let zOrder: Int = MarkupConstants.ZOrder.standard
    
    private var startPoint: CGPoint
    private var endPoint: CGPoint
    private let lineWidth: CGFloat
    private let color: NSColor
    
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x) - lineWidth
        let minY = min(startPoint.y, endPoint.y) - lineWidth
        let maxX = max(startPoint.x, endPoint.x) + lineWidth
        let maxY = max(startPoint.y, endPoint.y) + lineWidth
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // Expose endpoints for line and arrow resize handles
    var startPosition: CGPoint { startPoint }
    var endPosition: CGPoint { endPoint }
    
    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = MarkupColorManager.shared.currentColor,
         lineWidth: CGFloat? = nil, hasArrowhead: Bool = false) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth ?? MarkupLineThicknessManager.shared.currentThickness
        self.hasArrowhead = hasArrowhead
    }

    func duplicate() -> any MarkupElement {
        if hasArrowhead {
            return ArrowElement(startPoint: startPoint, endPoint: endPoint, color: color, lineWidth: lineWidth)
        }
        return LineElement(startPoint: startPoint, endPoint: endPoint, color: color, lineWidth: lineWidth)
    }

    func resize(handle: ResizeHandle, to point: CGPoint) {
        // For arrows: bottomLeft = start, topRight = end
        switch handle {
        case .bottomLeft, .topLeft:
            startPoint = point
        case .bottomRight, .topRight:
            endPoint = point
        }
    }
    
    func drawResizeHandles(in context: CGContext) {
        // Arrows draw handles as part of their selection indicator,
        // so this is intentionally empty to avoid double-drawing
    }
    
    // Endpoint hit testing shared by lines and arrows
    func hitTestEndpoint(point: CGPoint) -> Bool? {
        let handleSize = ResizeHandle.handleSize
        let startRect = CGRect(x: startPoint.x - handleSize/2, y: startPoint.y - handleSize/2, width: handleSize, height: handleSize)
        let endRect = CGRect(x: endPoint.x - handleSize/2, y: endPoint.y - handleSize/2, width: handleSize, height: handleSize)
        
        if startRect.contains(point) { return true }  // true = start point
        if endRect.contains(point) { return false }   // false = end point
        return nil
    }
    
    func setStartPoint(_ point: CGPoint) {
        startPoint = point
    }
    
    func setEndPoint(_ point: CGPoint) {
        endPoint = point
    }
    
    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        context.saveGState()
        
        if hasArrowhead {
            let geometry = ArrowDrawing.calculateGeometry(from: startPoint, to: endPoint, lineWidth: lineWidth)
            ArrowDrawing.draw(geometry: geometry, color: color.cgColor, lineWidth: lineWidth, in: context)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
        }
        
        // Draw selection indicator if selected
        if isSelected && mode == .editor {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        // Check if point is near the line or arrowhead
        let lineDistance = distanceFromPointToLine(point: point, lineStart: startPoint, lineEnd: endPoint)
        return lineDistance <= lineWidth / 2 + 5 // Add some tolerance
    }
    
    private func distanceFromPointToLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let A = point.x - lineStart.x
        let B = point.y - lineStart.y
        let C = lineEnd.x - lineStart.x
        let D = lineEnd.y - lineStart.y
        
        let dot = A * C + B * D
        let lenSq = C * C + D * D
        
        guard lenSq != 0 else { return sqrt(A * A + B * B) }
        
        let param = dot / lenSq
        let xx: CGFloat
        let yy: CGFloat
        
        if param < 0 {
            xx = lineStart.x
            yy = lineStart.y
        } else if param > 1 {
            xx = lineEnd.x
            yy = lineEnd.y
        } else {
            xx = lineStart.x + param * C
            yy = lineStart.y + param * D
        }
        
        let dx = point.x - xx
        let dy = point.y - yy
        return sqrt(dx * dx + dy * dy)
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        // For arrows, just draw grab handles at endpoints instead of a bounding box
        let handleSize = ResizeHandle.handleSize
        
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [])
        
        for point in [startPoint, endPoint] {
            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(handleRect)
            context.stroke(handleRect)
        }
    }
    
    func move(by translation: CGPoint) {
        startPoint.x += translation.x
        startPoint.y += translation.y
        endPoint.x += translation.x
        endPoint.y += translation.y
    }
}

final class ArrowElement: LineElement {
    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = MarkupColorManager.shared.currentColor,
         lineWidth: CGFloat? = nil) {
        super.init(startPoint: startPoint, endPoint: endPoint, color: color,
                   lineWidth: lineWidth, hasArrowhead: true)
    }
}

// MARK: - Rectangle Element
final class RectangleElement: MarkupElement, ResizableElement {
    let id = UUID()
    var isSelected: Bool = false
    let zOrder: Int = MarkupConstants.ZOrder.standard
    
    private var startPoint: CGPoint
    private var endPoint: CGPoint
    private let lineWidth: CGFloat
    private let color: NSColor
    
    var bounds: CGRect {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        return rect.insetBy(dx: -lineWidth/2, dy: -lineWidth/2)
    }
    
    // Inner rect without line width adjustment (for resize calculations)
    private var innerRect: CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }
    
    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = MarkupColorManager.shared.currentColor) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = MarkupLineThicknessManager.shared.currentThickness
    }
    
    // Private init for duplication
    private init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor, lineWidth: CGFloat) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
    }
    
    func duplicate() -> any MarkupElement {
        return RectangleElement(startPoint: startPoint, endPoint: endPoint, color: color, lineWidth: lineWidth)
    }
    
    func resize(handle: ResizeHandle, to point: CGPoint) {
        let rect = innerRect
        let minSize = MarkupConstants.ResizeHandle.minimumElementSize
        switch handle {
        case .topLeft:
            startPoint = CGPoint(x: min(point.x, rect.maxX - minSize), y: min(point.y, rect.maxY - minSize))
        case .topRight:
            endPoint.x = max(point.x, rect.minX + minSize)
            startPoint.y = min(point.y, rect.maxY - minSize)
        case .bottomRight:
            endPoint = CGPoint(x: max(point.x, rect.minX + minSize), y: max(point.y, rect.minY + minSize))
        case .bottomLeft:
            startPoint.x = min(point.x, rect.maxX - minSize)
            endPoint.y = max(point.y, rect.minY + minSize)
        }
    }
    
    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        context.saveGState()
        
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw rounded rectangle
        let path = CGPath(roundedRect: rect, cornerWidth: MarkupConstants.Rectangle.cornerRadius, cornerHeight: MarkupConstants.Rectangle.cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
        
        // Draw selection indicator if selected
        if isSelected && mode == .editor {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        return bounds.contains(point)
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
        context.setLineWidth(MarkupConstants.Selection.lineWidth)
        context.setLineDash(phase: 0, lengths: MarkupConstants.Selection.dashPattern)
        context.stroke(bounds.insetBy(dx: MarkupConstants.Selection.inset, dy: MarkupConstants.Selection.inset))
    }
    
    func move(by translation: CGPoint) {
        startPoint.x += translation.x
        startPoint.y += translation.y
        endPoint.x += translation.x
        endPoint.y += translation.y
    }
}

// MARK: - Step Counter Element
final class StepCounterElement: MarkupElement {
    let id = UUID()
    var isSelected: Bool = false
    let zOrder: Int = MarkupConstants.ZOrder.stepCounter
    
    private var centerPoint: CGPoint
    let stepNumber: Int
    private let radius: CGFloat
    private let backgroundColor: NSColor
    
    // Compute text color based on background brightness
    private var textColor: NSColor {
        return backgroundColor.isLight ? NSColor.black : NSColor.white
    }
    
    var bounds: CGRect {
        return CGRect(
            x: centerPoint.x - radius,
            y: centerPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
    
    init(centerPoint: CGPoint, stepNumber: Int, color: NSColor = MarkupColorManager.shared.currentColor) {
        self.centerPoint = centerPoint
        self.stepNumber = stepNumber
        self.backgroundColor = color
        self.radius = MarkupConstants.StepCounter.radius
    }
    
    func duplicate() -> any MarkupElement {
        return StepCounterElement(centerPoint: centerPoint, stepNumber: stepNumber, color: backgroundColor)
    }
    
    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        context.saveGState()
        
        // Draw circle background
        context.setFillColor(backgroundColor.cgColor)
        context.addEllipse(in: bounds)
        context.fillPath()
        
        // Draw number text
        let numberString = "\(stepNumber)"
        let font = NSFont.systemFont(ofSize: MarkupConstants.StepCounter.fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: numberString, attributes: attributes)
        let textSize = attributedString.size()
        
        let textRect = CGRect(
            x: centerPoint.x - textSize.width / 2,
            y: centerPoint.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        attributedString.draw(in: textRect)

        // Draw selection indicator if selected
        if isSelected && mode == .editor {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        let distance = sqrt(pow(point.x - centerPoint.x, 2) + pow(point.y - centerPoint.y, 2))
        return distance <= radius
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
        context.setLineWidth(MarkupConstants.Selection.lineWidth)
        context.setLineDash(phase: 0, lengths: MarkupConstants.Selection.dashPattern)
        context.addEllipse(in: bounds.insetBy(dx: MarkupConstants.Selection.inset, dy: MarkupConstants.Selection.inset))
        context.strokePath()
    }
    
    func move(by translation: CGPoint) {
        centerPoint.x += translation.x
        centerPoint.y += translation.y
    }
}

// MARK: - Text Element
final class TextElement: MarkupElement {
    let id = UUID()
    var isSelected = false
    let zOrder = MarkupConstants.ZOrder.standard
    var isBeingEdited = false

    private var position: CGPoint
    let layoutWidth: CGFloat?
    let textColor: NSColor
    var text: String { didSet { layout = makeLayout(text: text) } }
    private var layout: AnnotationTextLayout!

    var bounds: CGRect { CGRect(origin: position, size: layout.size) }

    init(position: CGPoint, text: String = "", color: NSColor = MarkupColorManager.shared.currentColor,
         layoutWidth: CGFloat? = nil) {
        self.position = position
        self.text = text
        self.textColor = color
        self.layoutWidth = layoutWidth
        self.layout = makeLayout(text: text)
    }

    func makeLayout(text: String) -> AnnotationTextLayout {
        AnnotationTextLayout(text: text, color: textColor, width: layoutWidth)
    }

    func duplicate() -> any MarkupElement {
        TextElement(position: position, text: text, color: textColor, layoutWidth: layoutWidth)
    }

    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        guard !isBeingEdited else { return }
        context.saveGState()
        defer { context.restoreGState() }
        layout.draw(at: position)
        if isSelected && mode == .editor {
            context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
            context.setLineWidth(MarkupConstants.Selection.lineWidth)
            context.setLineDash(phase: 0, lengths: MarkupConstants.Selection.dashPattern)
            context.stroke(bounds.insetBy(dx: MarkupConstants.Selection.inset, dy: MarkupConstants.Selection.inset))
        }
    }

    func contains(point: CGPoint) -> Bool { bounds.insetBy(dx: -5, dy: -5).contains(point) }
    func updateText(_ newText: String) { text = newText }
    func move(by translation: CGPoint) {
        position.x += translation.x
        position.y += translation.y
    }
}

// MARK: - NSColor Extension for Brightness Detection
extension NSColor {
    /// Determines if the color is light based on its perceived luminance
    var isLight: Bool {
        // Convert to RGB color space if needed
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            // Fallback: assume dark if we can't determine
            return false
        }
        
        // Get RGB components
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate perceived luminance using the relative luminance formula
        // This is more accurate than simple RGB averaging
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        
        // Consider colors with luminance > 0.6 as light
        // This threshold ensures good contrast for both white and black text
        return luminance > 0.6
    }
}

// MARK: - Blur Element
final class BlurElement: MarkupElement, ResizableElement {
    let id = UUID()
    var isSelected: Bool = false
    let zOrder: Int = MarkupConstants.ZOrder.blur
    
    private var rect: CGRect
    private var baseImage: NSImage?
    private var cachedBlurredImage: NSImage?
    private var cachedRect: CGRect = .zero  // For throttling blur regeneration

    var bounds: CGRect { rect }

    /// Current cached blur pixels, reused by the canvas for cheap drag previews.
    /// Call `finalizeBlur()` after a drag to refresh the exact pixels.
    var previewImage: NSImage? { cachedBlurredImage }
    
    init(rect: CGRect, baseImage: NSImage) {
        self.rect = rect
        self.baseImage = baseImage
        updateBlurredImage(force: true)
    }
    
    private init(rect: CGRect, baseImage: NSImage?, cachedImage: NSImage?, cachedRect: CGRect) {
        self.rect = rect
        self.baseImage = baseImage
        self.cachedBlurredImage = cachedImage
        self.cachedRect = cachedRect
    }

    func duplicate() -> any MarkupElement {
        BlurElement(rect: rect, baseImage: baseImage, cachedImage: cachedBlurredImage, cachedRect: cachedRect)
    }

    func move(by translation: CGPoint) {
        rect.origin.x += translation.x
        rect.origin.y += translation.y
        updateBlurredImage()
    }
    
    func resize(handle: ResizeHandle, to point: CGPoint) {
        let minSize = MarkupConstants.ResizeHandle.minimumElementSize
        switch handle {
        case .topLeft:
            let newWidth = rect.maxX - point.x
            let newHeight = rect.maxY - point.y
            if newWidth > minSize && newHeight > minSize {
                rect = CGRect(x: point.x, y: point.y, width: newWidth, height: newHeight)
            }
        case .topRight:
            let newWidth = point.x - rect.minX
            let newHeight = rect.maxY - point.y
            if newWidth > minSize && newHeight > minSize {
                rect = CGRect(x: rect.minX, y: point.y, width: newWidth, height: newHeight)
            }
        case .bottomRight:
            let newWidth = point.x - rect.minX
            let newHeight = point.y - rect.minY
            if newWidth > minSize && newHeight > minSize {
                rect = CGRect(x: rect.minX, y: rect.minY, width: newWidth, height: newHeight)
            }
        case .bottomLeft:
            let newWidth = rect.maxX - point.x
            let newHeight = point.y - rect.minY
            if newWidth > minSize && newHeight > minSize {
                rect = CGRect(x: point.x, y: rect.minY, width: newWidth, height: newHeight)
            }
        }
        updateBlurredImage()
    }
    
    func updateBaseImage(_ newBaseImage: NSImage) {
        self.baseImage = newBaseImage
        updateBlurredImage(force: true)
    }
    
    /// Update the cached blur image. Throttled to avoid regenerating on every small change.
    /// - Parameter force: If true, always regenerate regardless of rect changes
    private func updateBlurredImage(force: Bool = false) {
        guard let image = baseImage else { return }
        
        // Throttle: only regenerate if rect changed significantly (>5 points in any dimension)
        let threshold: CGFloat = 5.0
        let shouldRegenerate = force ||
            abs(rect.origin.x - cachedRect.origin.x) > threshold ||
            abs(rect.origin.y - cachedRect.origin.y) > threshold ||
            abs(rect.width - cachedRect.width) > threshold ||
            abs(rect.height - cachedRect.height) > threshold
        
        guard shouldRegenerate else { return }
        
        cachedRect = rect
        self.cachedBlurredImage = BlurElement.createBlurredImage(from: image, rect: rect)
    }
    
    /// Force regeneration of blur (call after resize completes)
    func finalizeBlur() {
        updateBlurredImage(force: true)
    }
    
    private static let ciContext = CIContext(options: nil)

    static func createBlurredImage(from image: NSImage, rect: CGRect) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(source.width) / image.size.width
        let scaleY = CGFloat(source.height) / image.size.height
        let region = CGRect(x: rect.minX * scaleX,
                            y: (image.size.height - rect.maxY) * scaleY,
                            width: rect.width * scaleX, height: rect.height * scaleY)
        let input = CIImage(cgImage: source)
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: MarkupConstants.Blur.radius * scaleX
        ]).cropped(to: region)
        guard let output = ciContext.createCGImage(blurred, from: region) else { return nil }
        return NSImage(cgImage: output, size: rect.size)
    }

    func draw(in context: CGContext, mode: MarkupRenderMode = .editor) {
        context.saveGState()
        
        if let blurredImage = cachedBlurredImage {
            // Use NSGraphicsContext to draw NSImage easily
            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = nsContext
            
            blurredImage.draw(in: rect)
            
            NSGraphicsContext.restoreGraphicsState()
        }
        
        // Draw selection indicator if selected
        if isSelected && mode == .editor {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(MarkupConstants.Selection.color.cgColor)
        context.setLineWidth(MarkupConstants.Selection.lineWidth)
        context.setLineDash(phase: 0, lengths: MarkupConstants.Selection.dashPattern)
        context.stroke(rect)
    }
}
