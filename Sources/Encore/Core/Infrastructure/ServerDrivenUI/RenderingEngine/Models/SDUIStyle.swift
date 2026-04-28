//
//  SDUIStyle.swift
//  Encore
//
//  SDUI styling types - colors, fonts, padding, frame, shadows
//

import SwiftUI

// MARK: - Color System

/// Semantic colors that adapt to dark/light mode
enum SDUISemanticColor: String, Decodable {
    case label
    case secondaryLabel
    case tertiaryLabel
    case systemBackground
    case secondarySystemBackground
    case systemGroupedBackground
    case secondarySystemGroupedBackground
    case separator
    case tertiarySystemFill
    
    var uiColor: UIColor {
        switch self {
        case .label: return .label
        case .secondaryLabel: return .secondaryLabel
        case .tertiaryLabel: return .tertiaryLabel
        case .systemBackground: return .systemBackground
        case .secondarySystemBackground: return .secondarySystemBackground
        case .systemGroupedBackground: return .systemGroupedBackground
        case .secondarySystemGroupedBackground: return .secondarySystemGroupedBackground
        case .separator: return .separator
        case .tertiarySystemFill: return .tertiarySystemFill
        }
    }
    
    var color: Color {
        Color(uiColor)
    }
}

/// Color definition supporting both hex and semantic colors
enum SDUIColor {
    case hex(String)
    case semantic(SDUISemanticColor)
    
    var color: Color {
        switch self {
        case .hex(let hexString):
            return Color(hex: hexString)
        case .semantic(let semanticColor):
            return semanticColor.color
        }
    }
}

extension SDUIColor: Decodable {
    private enum CodingKeys: String, CodingKey {
        case hex, semantic
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let hexValue = try? container.decode(String.self, forKey: .hex) {
            self = .hex(hexValue)
        } else if let semanticValue = try? container.decode(SDUISemanticColor.self, forKey: .semantic) {
            self = .semantic(semanticValue)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "SDUIColor must have either 'hex' or 'semantic' key"
                )
            )
        }
    }
}

// MARK: - Typography

enum SDUIFontWeight: String, Decodable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    
    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

struct SDUIFont: Decodable {
    let size: CGFloat
    let weight: SDUIFontWeight
    
    var font: Font {
        .system(size: size, weight: weight.fontWeight)
    }
    
    static let title = SDUIFont(size: 24, weight: .semibold)
    static let subtitle = SDUIFont(size: 17, weight: .regular)
    static let body = SDUIFont(size: 16, weight: .regular)
    static let caption = SDUIFont(size: 15, weight: .semibold)
    static let small = SDUIFont(size: 12, weight: .bold)
}

// MARK: - Layout & Styling

enum SDUIAlignment: String, Decodable {
    case leading, trailing, center
    case top, bottom
    case topLeading, topTrailing
    case bottomLeading, bottomTrailing
    
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        case .center, .top, .bottom: return .center
        }
    }
    
    var verticalAlignment: VerticalAlignment {
        switch self {
        case .top, .topLeading, .topTrailing: return .top
        case .bottom, .bottomLeading, .bottomTrailing: return .bottom
        case .center, .leading, .trailing: return .center
        }
    }
    
    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
    
    var textAlignment: TextAlignment {
        switch self {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        case .center, .top, .bottom: return .center
        }
    }
}

struct SDUIPadding: Decodable {
    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?
    var horizontal: CGFloat?
    var vertical: CGFloat?
    var all: CGFloat?
    
    var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: top ?? vertical ?? all ?? 0,
            leading: leading ?? horizontal ?? all ?? 0,
            bottom: bottom ?? vertical ?? all ?? 0,
            trailing: trailing ?? horizontal ?? all ?? 0
        )
    }
    
    static func all(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(all: value)
    }
    
    static func horizontal(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(horizontal: value)
    }
    
    static func vertical(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(vertical: value)
    }
    
    static func top(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(top: value)
    }
    
    static func leading(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(leading: value)
    }
    
    static func trailing(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(trailing: value)
    }
    
    static func bottom(_ value: CGFloat) -> SDUIPadding {
        SDUIPadding(bottom: value)
    }
}

/// Represents a dimension that can be a fixed value or infinity
enum SDUIDimension: Decodable {
    case fixed(CGFloat)
    case infinity
    
    var value: CGFloat? {
        switch self {
        case .fixed(let v): return v
        case .infinity: return .infinity
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self), stringValue == "infinity" {
            self = .infinity
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .fixed(CGFloat(doubleValue))
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected number or 'infinity'")
        }
    }
}

struct SDUIFrame: Decodable {
    var width: CGFloat?
    var height: CGFloat?
    var minWidth: CGFloat?
    var maxWidth: SDUIDimension?
    var minHeight: CGFloat?
    var maxHeight: SDUIDimension?
    var alignment: SDUIAlignment?
    
    // Computed properties for CGFloat values
    var maxWidthValue: CGFloat? { maxWidth?.value }
    var maxHeightValue: CGFloat? { maxHeight?.value }
    
    static func fixed(width: CGFloat, height: CGFloat) -> SDUIFrame {
        SDUIFrame(width: width, height: height)
    }
    
    static func width(_ width: CGFloat) -> SDUIFrame {
        SDUIFrame(width: width)
    }
    
    static func height(_ height: CGFloat) -> SDUIFrame {
        SDUIFrame(height: height)
    }
    
    static func maxWidth(_ maxWidth: CGFloat, alignment: SDUIAlignment? = nil) -> SDUIFrame {
        SDUIFrame(maxWidth: .fixed(maxWidth), alignment: alignment)
    }
    
    static var infinity: SDUIFrame {
        SDUIFrame(maxWidth: .infinity)
    }
    
    static func infinityWidth(alignment: SDUIAlignment) -> SDUIFrame {
        SDUIFrame(maxWidth: .infinity, alignment: alignment)
    }
    
    static func infinityBoth(alignment: SDUIAlignment) -> SDUIFrame {
        SDUIFrame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

struct SDUIShadow: Decodable {
    let color: SDUIColor
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    let opacity: CGFloat?
    
    init(color: SDUIColor, radius: CGFloat, x: CGFloat, y: CGFloat, opacity: CGFloat? = nil) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
        self.opacity = opacity
    }
    
    static func standard(opacity: CGFloat = 0.1) -> SDUIShadow {
        SDUIShadow(color: .semantic(.label), radius: 4, x: 0, y: 0, opacity: opacity)
    }
}

enum SDUIClipShape: Decodable {
    case rectangle(cornerRadius: CGFloat)
    case circle
    case capsule
    
    private enum CodingKeys: String, CodingKey {
        case rectangle, circle, capsule
    }
    
    private struct RectangleData: Decodable {
        let cornerRadius: CGFloat
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let data = try? container.decode(RectangleData.self, forKey: .rectangle) {
            self = .rectangle(cornerRadius: data.cornerRadius)
        } else if container.contains(.circle) {
            self = .circle
        } else if container.contains(.capsule) {
            self = .capsule
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown clip shape"))
        }
    }
}

/// Per-corner radius configuration for uneven rounded rectangles
struct SDUICornerRadii: Decodable {
    var topLeading: CGFloat?
    var topTrailing: CGFloat?
    var bottomLeading: CGFloat?
    var bottomTrailing: CGFloat?
    
    /// Returns RectangleCornerRadii for use with UnevenRoundedRectangle
    @available(iOS 16.0, *)
    var rectCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: topLeading ?? 0,
            bottomLeading: bottomLeading ?? 0,
            bottomTrailing: bottomTrailing ?? 0,
            topTrailing: topTrailing ?? 0
        )
    }
}

/// Complete styling for any element
struct SDUIStyle: Decodable {
    var padding: SDUIPadding?
    var frame: SDUIFrame?
    var cornerRadius: CGFloat?
    /// Per-corner radius (takes precedence over cornerRadius if specified)
    var cornerRadii: SDUICornerRadii?
    var backgroundColor: SDUIColor?
    var shadow: SDUIShadow?
    var opacity: CGFloat?
    var clipShape: SDUIClipShape?
    var clipped: Bool?
    var ignoresSafeArea: Bool?
    var layoutPriority: Double?
    /// Makes the view fill the container width (like containerRelativeFrame(.horizontal))
    var containerRelativeFrame: SDUIContainerRelativeFrame?
    /// For scroll views - uses scrollTargetLayout
    var scrollTargetLayout: Bool?
    /// Border width in points
    var borderWidth: CGFloat?
    /// Border color
    var borderColor: SDUIColor?
    
    static let none = SDUIStyle()
}

/// Configuration for containerRelativeFrame behavior
struct SDUIContainerRelativeFrame: Decodable {
    var axis: SDUIScrollAxis?
    
    static let horizontal = SDUIContainerRelativeFrame(axis: .horizontal)
    static let vertical = SDUIContainerRelativeFrame(axis: .vertical)
}

// MARK: - Scroll Axis (needed by SDUIContainerRelativeFrame)

enum SDUIScrollAxis: String, Decodable {
    case horizontal, vertical
    
    var axis: Axis.Set {
        switch self {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        }
    }
}
