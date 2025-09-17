import Foundation
import AppKit

/// Represents different markup tools available in the editor
enum MarkupTool: CaseIterable {
    case selection
    case arrow
    
    var displayName: String {
        switch self {
        case .selection: return "Selection"
        case .arrow: return "Arrow"
        }
    }
    
    var iconName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .arrow: return "arrow.up.right"
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
