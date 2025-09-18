import Foundation
import AppKit

/// Represents different markup tools available in the editor
enum MarkupTool: CaseIterable {
    case selection
    case arrow
    case rectangle
    case stepCounter
    
    var displayName: String {
        switch self {
        case .selection: return "Selection"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .stepCounter: return "Step Counter"
        }
    }
    
    var iconName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .stepCounter: return "1.circle.fill"
        }
    }
}

/// Protocol for markup elements that can be drawn, selected, and manipulated
protocol MarkupElement: AnyObject {
    var id: UUID { get }
    var isSelected: Bool { get set }
    var bounds: CGRect { get }
    
    func draw(in context: CGContext)
    func contains(point: CGPoint) -> Bool
}

/// Arrow markup element with start and end points
final class ArrowElement: MarkupElement {
    let id = UUID()
    var isSelected = false
    
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: NSColor
    let lineWidth: CGFloat
    
    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0), lineWidth: CGFloat = 6.0) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
    }
    
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x) - lineWidth
        let minY = min(startPoint.y, endPoint.y) - lineWidth
        let maxX = max(startPoint.x, endPoint.x) + lineWidth
        let maxY = max(startPoint.y, endPoint.y) + lineWidth
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    func draw(in context: CGContext) {
        context.saveGState()
        
        // Set line properties
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Calculate arrow geometry - increased arrowhead size
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = lineWidth * 5.0  // Doubled from 2.5 to 5.0
        
        // Calculate where the line should end (closer to the arrowhead tip for better connection)
        let lineEndPoint = CGPoint(
            x: endPoint.x - arrowLength * 0.6 * cos(angle),  // Reduced from full length to 60%
            y: endPoint.y - arrowLength * 0.6 * sin(angle)
        )
        
        // Draw the line (shortened to not extend past arrowhead)
        context.move(to: startPoint)
        context.addLine(to: lineEndPoint)
        context.strokePath()
        
        // Draw arrowhead
        drawArrowhead(in: context)
        
        // Draw selection indicator if selected
        if isSelected {
            drawSelectionIndicator(in: context)
        }
        
        context.restoreGState()
    }
    
    private func drawArrowhead(in context: CGContext) {
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let arrowLength: CGFloat = lineWidth * 5.0  // Doubled from 2.5 to 5.0
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
    }
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bounds)
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        // Check if point is near the line within tolerance
        let tolerance: CGFloat = max(lineWidth / 2 + 4, 8)
        
        // Distance from point to line segment
        let lineLength = sqrt(pow(endPoint.x - startPoint.x, 2) + pow(endPoint.y - startPoint.y, 2))
        guard lineLength > 0 else { return false }
        
        let t = max(0, min(1, ((point.x - startPoint.x) * (endPoint.x - startPoint.x) + (point.y - startPoint.y) * (endPoint.y - startPoint.y)) / pow(lineLength, 2)))
        
        let closestPoint = CGPoint(
            x: startPoint.x + t * (endPoint.x - startPoint.x),
            y: startPoint.y + t * (endPoint.y - startPoint.y)
        )
        
        let distance = sqrt(pow(point.x - closestPoint.x, 2) + pow(point.y - closestPoint.y, 2))
        return distance <= tolerance
    }
}

/// Rectangle markup element with rounded corners
final class RectangleElement: MarkupElement {
    let id = UUID()
    var isSelected = false
    
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: NSColor
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    
    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0), lineWidth: CGFloat = 6.0, cornerRadius: CGFloat = 8.0) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
    }
    
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x) - lineWidth / 2
        let minY = min(startPoint.y, endPoint.y) - lineWidth / 2
        let maxX = max(startPoint.x, endPoint.x) + lineWidth / 2
        let maxY = max(startPoint.y, endPoint.y) + lineWidth / 2
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private var rect: CGRect {
        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }
    
    func draw(in context: CGContext) {
        context.saveGState()
        
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
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bounds)
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        // Check if point is near the rectangle border within tolerance
        let tolerance: CGFloat = max(lineWidth / 2 + 4, 8)
        let expandedRect = rect.insetBy(dx: -tolerance, dy: -tolerance)
        let innerRect = rect.insetBy(dx: tolerance, dy: tolerance)
        
        // Point is considered inside if it's in the expanded rect but not in the inner rect (border area)
        return expandedRect.contains(point) && !innerRect.contains(point)
    }
}

/// Step counter markup element - a circular stamp with a number
final class StepCounterElement: MarkupElement {
    let id = UUID()
    var isSelected = false
    
    let centerPoint: CGPoint
    let stepNumber: Int
    let color: NSColor
    let radius: CGFloat
    
    init(centerPoint: CGPoint, stepNumber: Int, color: NSColor = NSColor(red: 0.847, green: 0.106, blue: 0.376, alpha: 1.0), radius: CGFloat = 20.0) {
        self.centerPoint = centerPoint
        self.stepNumber = stepNumber
        self.color = color
        self.radius = radius
    }
    
    var bounds: CGRect {
        return CGRect(
            x: centerPoint.x - radius,
            y: centerPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
    
    func draw(in context: CGContext) {
        context.saveGState()
        
        // Draw filled circle
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: bounds)
        
        // Draw the number text
        let textColor = NSColor.white // White text for good contrast against pink background
        let fontSize: CGFloat = radius * 0.8 // Scale font size to circle size
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        
        let numberString = "\(stepNumber)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: numberString, attributes: attributes)
        let textSize = attributedString.size()
        
        // Center the text in the circle
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
    
    private func drawSelectionIndicator(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        
        // Draw selection indicator around the circle
        let selectionBounds = bounds.insetBy(dx: -4, dy: -4)
        context.strokeEllipse(in: selectionBounds)
        
        context.restoreGState()
    }
    
    func contains(point: CGPoint) -> Bool {
        // Check if point is within the circle with a small tolerance
        let tolerance: CGFloat = 4.0
        let distance = sqrt(pow(point.x - centerPoint.x, 2) + pow(point.y - centerPoint.y, 2))
        return distance <= radius + tolerance
    }
}
