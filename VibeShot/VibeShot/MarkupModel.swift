import Foundation
import Cocoa

// MARK: - Markup Tool Types
enum MarkupTool: CaseIterable {
    case selection
    case arrow
    case rectangle
    case stepCounter
    case text
    
    var displayName: String {
        switch self {
        case .selection: return "Selection"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .stepCounter: return "Step Counter"
        case .text: return "Text"
        }
    }
    
    var iconName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .stepCounter: return "number.circle"
        case .text: return "textformat"
        }
    }
}

// MARK: - Base Markup Element Protocol
protocol MarkupElement: AnyObject, Identifiable {
    var id: UUID { get }
    var isSelected: Bool { get set }
    var bounds: CGRect { get }
    
    func draw(in context: CGContext)
    func contains(point: CGPoint) -> Bool
}

// MARK: - Arrow Element
final class ArrowElement: MarkupElement {
    let id = UUID()
    var isSelected: Bool = false
    
    private let startPoint: CGPoint
    private let endPoint: CGPoint
    private let color = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0)
    private let lineWidth: CGFloat = 6.0
    
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x) - lineWidth
        let minY = min(startPoint.y, endPoint.y) - lineWidth
        let maxX = max(startPoint.x, endPoint.x) + lineWidth
        let maxY = max(startPoint.y, endPoint.y) + lineWidth
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    init(startPoint: CGPoint, endPoint: CGPoint) {
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    func draw(in context: CGContext) {
        context.saveGState()
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate arrow geometry
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = lineWidth * 5.0
        
        // Calculate where the line should end
        let lineEndPoint = CGPoint(
            x: endPoint.x - arrowLength * 0.6 * cos(angle),
            y: endPoint.y - arrowLength * 0.6 * sin(angle)
        )
        
        // Draw the line
        context.move(to: startPoint)
        context.addLine(to: lineEndPoint)
        context.strokePath()
        
        // Draw arrowhead
        let arrowAngle: CGFloat = .pi / 6 // 30 degrees
        
        let arrowPoint1 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        )
        
        let arrowPoint2 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        )
        
        context.setFillColor(color.cgColor)
        context.move(to: endPoint)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
        
        // Draw selection indicator if selected
        if isSelected {
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
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bounds.insetBy(dx: -5, dy: -5))
    }
}

// MARK: - Rectangle Element
final class RectangleElement: MarkupElement {
    let id = UUID()
    var isSelected: Bool = false
    
    private let startPoint: CGPoint
    private let endPoint: CGPoint
    private let color = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0)
    private let lineWidth: CGFloat = 6.0
    private let cornerRadius: CGFloat = 8.0
    
    var bounds: CGRect {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        return rect.insetBy(dx: -lineWidth/2, dy: -lineWidth/2)
    }
    
    init(startPoint: CGPoint, endPoint: CGPoint) {
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    func draw(in context: CGContext) {
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
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.strokePath()
        
        // Draw selection indicator if selected
        if isSelected {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        return bounds.contains(point)
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bounds.insetBy(dx: -5, dy: -5))
    }
}

// MARK: - Step Counter Element
final class StepCounterElement: MarkupElement {
    let id = UUID()
    var isSelected: Bool = false
    
    private let centerPoint: CGPoint
    let stepNumber: Int
    private let radius: CGFloat = 20.0
    private let backgroundColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0)
    private let textColor = NSColor.white
    
    var bounds: CGRect {
        return CGRect(
            x: centerPoint.x - radius,
            y: centerPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
    
    init(centerPoint: CGPoint, stepNumber: Int) {
        self.centerPoint = centerPoint
        self.stepNumber = stepNumber
    }
    
    func draw(in context: CGContext) {
        context.saveGState()
        
        // Draw circle background
        context.setFillColor(backgroundColor.cgColor)
        context.addEllipse(in: bounds)
        context.fillPath()
        
        // Draw number text
        let numberString = "\(stepNumber)"
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
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
        if isSelected {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        let distance = sqrt(pow(point.x - centerPoint.x, 2) + pow(point.y - centerPoint.y, 2))
        return distance <= radius
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.addEllipse(in: bounds.insetBy(dx: -5, dy: -5))
        context.strokePath()
    }
}

// MARK: - Text Element
final class TextElement: MarkupElement {
    let id = UUID()
    var isSelected: Bool = false
    var isBeingEdited: Bool = false  // Add this property to hide element while editing
    
    private var position: CGPoint
    var text: String {
        didSet {
            updateBounds()
        }
    }
    private let fontSize: CGFloat = 18.0
    private let textColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0)
    private let font: NSFont
    private var _bounds: CGRect
    
    var bounds: CGRect {
        return _bounds
    }
    
    init(position: CGPoint, text: String = "") {
        self.position = position
        self.text = text
        self.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        self._bounds = CGRect.zero
        updateBounds()
    }
    
    private func updateBounds() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: text.isEmpty ? "Type here..." : text, attributes: attributes)
        let textSize = attributedString.size()
        
        _bounds = CGRect(
            x: position.x,
            y: position.y,
            width: max(textSize.width, 100), // Minimum width for empty text
            height: textSize.height
        )
    }
    
    func draw(in context: CGContext) {
        // Don't draw if currently being edited to avoid double rendering
        guard !isBeingEdited else { return }
        
        context.saveGState()
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let displayText = text
        let attributedString = NSAttributedString(string: displayText, attributes: attributes)
        
        // Draw the text without any background - transparent editing
        attributedString.draw(in: bounds)
        
        // Draw selection indicator if selected
        if isSelected && !isBeingEdited {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        return bounds.insetBy(dx: -5, dy: -5).contains(point)
    }
    
    func updateText(_ newText: String) {
        text = newText
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bounds.insetBy(dx: -5, dy: -5))
    }
}
