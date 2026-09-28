import AppKit

/// The eight screen anchor points from the spec. `center` is intentionally absent.
enum HudAnchor: String, CaseIterable, Codable {
    case topCenter, topRight, bottomRight, bottomLeft
    case leftBottom, leftTop, rightBottom, rightTop

    var label: String {
        switch self {
        case .topCenter: return L("Oben Mitte", "Top center");    case .topRight: return L("Oben Rechts", "Top edge, right")
        case .bottomRight: return L("Unten Rechts", "Bottom edge, right"); case .bottomLeft: return L("Unten Links", "Bottom edge, left")
        case .leftBottom: return L("Links Unten", "Left edge, bottom");   case .leftTop: return L("Links Oben", "Left edge, top")
        case .rightBottom: return L("Rechts Unten", "Right edge, bottom"); case .rightTop: return L("Rechts Oben", "Right edge, top")
        }
    }

    /// Origin for a panel of `size` on `screen`, with `margin` inset and an
    /// optional fine `offset` (+x right, +y up). AppKit's origin is bottom-left.
    func origin(for size: NSSize, in screen: NSRect, margin: CGFloat = 26, offset: CGSize = .zero) -> NSPoint {
        let leftX = screen.minX + margin
        let rightX = screen.maxX - size.width - margin
        let centerX = screen.midX - size.width / 2
        let topY = screen.maxY - size.height - margin
        let bottomY = screen.minY + margin
        let upperY = screen.minY + (screen.height * 0.68) - (size.height / 2)
        let lowerY = screen.minY + (screen.height * 0.32) - (size.height / 2)
        let base: NSPoint
        switch self {
        case .topCenter:    base = NSPoint(x: centerX, y: topY)
        case .topRight:     base = NSPoint(x: rightX,  y: topY)
        case .bottomRight:  base = NSPoint(x: rightX,  y: bottomY)
        case .bottomLeft:   base = NSPoint(x: leftX,   y: bottomY)
        case .leftBottom:   base = NSPoint(x: leftX,   y: lowerY)
        case .leftTop:      base = NSPoint(x: leftX,   y: topY)
        case .rightBottom:  base = NSPoint(x: rightX,  y: lowerY)
        case .rightTop:     base = NSPoint(x: rightX,  y: upperY)
        }
        return NSPoint(x: base.x + offset.width, y: base.y + offset.height)
    }
}
