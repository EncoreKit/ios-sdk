//
//  SDUIElement.swift
//  Encore
//
//  SDUI element types - text, images, layout, shapes, scroll, data
//

import SwiftUI

// MARK: - Text Elements

struct SDUIText: Decodable {
    var text: String
    var font: SDUIFont?
    var color: SDUIColor?
    var alignment: SDUIAlignment?
    var lineSpacing: CGFloat?
    /// Line height multiplier (e.g., 1.2 = 120% of font size)
    var lineHeight: CGFloat?
    var lineLimit: Int?
    var multilineAlignment: SDUIAlignment?
    var strikethrough: Bool?
    var style: SDUIStyle?

    // For dynamic text that references context data
    var textBinding: SDUITextBinding?

    // For concatenated styled text (e.g., "Get 1 month" + " for free" with different colors)
    var segments: [SDUITextSegment]?

    // NEW: Look up text from a textMap based on a stored value
    // e.g., textMapKey: "answerTitles" looks up textMaps["answerTitles"][values[textMapValueKey]]
    var textMapKey: String?

    // Which value key to use for the lookup (defaults to textMapKey if not specified)
    var textMapValueKey: String?

    /// Read text directly from context.values[valueKey].
    /// Used for displaying runtime-set values (e.g., error messages from native validation).
    /// Unlike textMapKey (server-side lookup tables) or template variables (OfferContext),
    /// this reads from the mutable state machine values dictionary.
    var valueKey: String?

    init(text: String = "", font: SDUIFont? = nil, color: SDUIColor? = nil, alignment: SDUIAlignment? = nil, lineSpacing: CGFloat? = nil, lineHeight: CGFloat? = nil, lineLimit: Int? = nil, multilineAlignment: SDUIAlignment? = nil, style: SDUIStyle? = nil, textBinding: SDUITextBinding? = nil, segments: [SDUITextSegment]? = nil, textMapKey: String? = nil, textMapValueKey: String? = nil, valueKey: String? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.lineHeight = lineHeight
        self.lineLimit = lineLimit
        self.multilineAlignment = multilineAlignment
        self.style = style
        self.textBinding = textBinding
        self.segments = segments
        self.textMapKey = textMapKey
        self.textMapValueKey = textMapValueKey
        self.valueKey = valueKey
    }
}

/// A segment of styled text for concatenation
struct SDUITextSegment: Decodable {
    var text: String
    var font: SDUIFont?
    var color: SDUIColor?
    
    // For dynamic text binding
    var textBinding: SDUITextBinding?
}

enum SDUITextBinding: String, Decodable {
    case offerAdvertiserName
    case offerDescription
    case offerCtaText
    case titleText
    case accentTitleText
    case subtitleText
}

// MARK: - Image Elements

struct SDUISystemImage: Decodable {
    let systemName: String
    var font: SDUIFont?
    var color: SDUIColor?
    var style: SDUIStyle?
    /// SF Symbol animation on appear (e.g., "bounce")
    var symbolEffect: String?
}

struct SDUIAsyncImage: Decodable {
    var urlBinding: SDUICreativeBinding?
    var url: String?
    var aspectRatio: CGFloat?
    var contentMode: SDUIContentMode?
    var placeholderColor: SDUIColor?
    var style: SDUIStyle?
}

/// Renders the host app's bundle icon in place. No network, no async — the
/// icon is read from `Bundle.main` at render time, so it always matches the
/// icon the user sees on their home screen (including alternate icons if the
/// host app switches them at runtime).
struct SDUIAppIcon: Decodable {
    var style: SDUIStyle?
}

struct SDUIAsyncVideo: Decodable {
    var urlBinding: SDUICreativeBinding?
    var url: String?
    var contentMode: SDUIContentMode?
    var style: SDUIStyle?
}

enum SDUICreativeBinding: String, Decodable {
    case offerPrimaryCreative
    case offerLogoImage
}

enum SDUIContentMode: String, Decodable {
    case fit, fill
    
    var contentMode: ContentMode {
        switch self {
        case .fit: return .fit
        case .fill: return .fill
        }
    }
}

// MARK: - Layout Elements

struct SDUIButton: Decodable {
    let content: SDUIElement
    let action: SDUIAction
    var style: SDUIStyle?
    var disabled: Bool?
}

struct SDUIStack: Decodable {
    let children: [SDUIElement]
    var spacing: CGFloat?
    var alignment: SDUIAlignment?
    var style: SDUIStyle?
    /// If true, render via `LazyVStack` / `LazyHStack` instead of the eager
    /// `VStack` / `HStack`. Lazy variants materialize child views only as
    /// they approach the viewport, so row `.onAppear` correlates with
    /// on-screen visibility rather than parent mount. Needed for correct
    /// impression tracking on long scrolling lists. Default false.
    var lazy: Bool?
}

struct SDUISpacer: Decodable {
    var minLength: CGFloat?
    var style: SDUIStyle?
}

struct SDUIGroup: Decodable {
    let content: SDUIElement
    var style: SDUIStyle?
}

// MARK: - Input Elements

struct SDUITextField: Decodable {
    /// Key in SDUIContext.values to bind this field to
    let valueKey: String
    var placeholder: String?
    var keyboardType: SDUIKeyboardType?
    var textContentType: SDUITextContentType?
    var style: SDUIStyle?
}

struct SDUIToggle: Decodable {
    /// Key in SDUIContext.values to bind ("true"/"false")
    let valueKey: String
    /// Label element rendered beside the checkbox
    let label: SDUIElement
    var style: SDUIStyle?
}

struct SDUISlideButton: Decodable {
    /// Text displayed on the track when active
    let text: String
    /// Text displayed when disabled (e.g., "Enter Email")
    var disabledText: String?
    /// Action triggered when slide completes
    let action: SDUIAction
    /// Track background color
    var trackColor: SDUIColor?
    /// Thumb color (active state)
    var thumbColor: SDUIColor?
    /// Text color
    var textColor: SDUIColor?
    /// When set, slide is disabled until context.values[key] is non-empty
    var requiredValueKey: String?
    var style: SDUIStyle?
}

enum SDUIKeyboardType: String, Decodable {
    case emailAddress

    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .emailAddress: return .emailAddress
        }
    }
}

enum SDUITextContentType: String, Decodable {
    case emailAddress

    var uiTextContentType: UITextContentType {
        switch self {
        case .emailAddress: return .emailAddress
        }
    }
}

// MARK: - Shape Elements

enum SDUIShapeType: String, Decodable {
    case rectangle
    case roundedRectangle
    case circle
    case capsule
}

struct SDUIShape: Decodable {
    let type: SDUIShapeType
    var cornerRadius: CGFloat?
    var fillColor: SDUIColor?
    var style: SDUIStyle?
}

enum SDUIGradientDirection: String, Decodable {
    case topToBottom
    case bottomToTop
    case leadingToTrailing
    case trailingToLeading
    
    var startPoint: UnitPoint {
        switch self {
        case .topToBottom: return .top
        case .bottomToTop: return .bottom
        case .leadingToTrailing: return .leading
        case .trailingToLeading: return .trailing
        }
    }
    
    var endPoint: UnitPoint {
        switch self {
        case .topToBottom: return .bottom
        case .bottomToTop: return .top
        case .leadingToTrailing: return .trailing
        case .trailingToLeading: return .leading
        }
    }
}

struct SDUIGradient: Decodable {
    let colors: [SDUIColorStop]
    let direction: SDUIGradientDirection
    var style: SDUIStyle?
}

struct SDUIColorStop: Decodable {
    let color: SDUIColor
    let opacity: CGFloat?
    
    static func color(_ color: SDUIColor, opacity: CGFloat = 1.0) -> SDUIColorStop {
        SDUIColorStop(color: color, opacity: opacity)
    }
}

// MARK: - Scroll Elements

struct SDUIScrollView: Decodable {
    let content: SDUIElement
    var axis: SDUIScrollAxis?
    var showsIndicators: Bool?
    var style: SDUIStyle?
    /// Content margins for scroll content
    var contentMargins: SDUIPadding?
    /// Whether to use view-aligned scroll target behavior (for paging)
    var scrollTargetBehavior: SDUIScrollTargetBehavior?
}

enum SDUIScrollTargetBehavior: String, Decodable {
    case viewAligned
    case paging
}

// MARK: - Data Elements

struct SDUIForEach: Decodable {
    let dataSource: SDUIDataSource
    let itemTemplate: SDUIElement
    var limit: Int?
    var style: SDUIStyle?
}

enum SDUIDataSource: String, Decodable {
    case offers
    case pageIndicators
}

struct SDUIConditional: Decodable {
    let condition: SDUICondition
    let ifTrue: SDUIElement
    var ifFalse: SDUIElement?
}

enum SDUICondition: Decodable {
    case hasMultipleOffers
    case isCurrentPage(index: Int)
    case isCurrentPageBinding // Uses context's current index

    // Generic state machine conditions
    case stateEquals(String)                      // currentState == value
    case valueEquals(key: String, value: String)  // values[key] == value
    case hasValue(String)                         // values[key] != nil

    /// Row-aware: true when the current `forEach` offer's id matches
    /// `context.values[targetKey ?? "selectedOfferId"]`. Read-side pair to
    /// the `selectOffer` action — use to render per-card selected states
    /// (checkmark, accent border) inside a list of offers.
    case isSelectedOffer(targetKey: String?)

    private enum CodingKeys: String, CodingKey {
        case hasMultipleOffers, isCurrentPage, isCurrentPageBinding
        case stateEquals, valueEquals, hasValue
        case isSelectedOffer
    }

    private struct CurrentPageData: Decodable {
        let index: Int
    }

    private struct ValueEqualsData: Decodable {
        let key: String
        let value: String
    }

    /// Payload for `isSelectedOffer`. Optional — `{"isSelectedOffer": {}}`
    /// defaults to checking `selectedOfferId`; pass `{"targetKey": "..."}`
    /// to read from a different key.
    private struct IsSelectedOfferData: Decodable {
        let targetKey: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.hasMultipleOffers) {
            self = .hasMultipleOffers
        } else if let data = try? container.decode(CurrentPageData.self, forKey: .isCurrentPage) {
            self = .isCurrentPage(index: data.index)
        } else if container.contains(.isCurrentPageBinding) {
            self = .isCurrentPageBinding
        } else if let state = try? container.decode(String.self, forKey: .stateEquals) {
            self = .stateEquals(state)
        } else if let data = try? container.decode(ValueEqualsData.self, forKey: .valueEquals) {
            self = .valueEquals(key: data.key, value: data.value)
        } else if let key = try? container.decode(String.self, forKey: .hasValue) {
            self = .hasValue(key)
        } else if container.contains(.isSelectedOffer) {
            // Support both `{"isSelectedOffer": {}}` (default key) and
            // `{"isSelectedOffer": {"targetKey": "customKey"}}`.
            let data = try? container.decode(IsSelectedOfferData.self, forKey: .isSelectedOffer)
            self = .isSelectedOffer(targetKey: data?.targetKey)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown condition type"))
        }
    }
}

// MARK: - Main Element Enum

indirect enum SDUIElement {
    case text(SDUIText)
    case systemImage(SDUISystemImage)
    case asyncImage(SDUIAsyncImage)
    case asyncVideo(SDUIAsyncVideo)
    case appIcon(SDUIAppIcon)
    case button(SDUIButton)
    case vStack(SDUIStack)
    case hStack(SDUIStack)
    case zStack(SDUIStack)
    case spacer(SDUISpacer)
    case shape(SDUIShape)
    case gradient(SDUIGradient)
    case scrollView(SDUIScrollView)
    case forEach(SDUIForEach)
    case conditional(SDUIConditional)
    case group(SDUIGroup)
    case textField(SDUITextField)
    case toggle(SDUIToggle)
    case slideButton(SDUISlideButton)
    case compactPageIndicator
    case empty
    
    // Convenience initializers
    static func text(_ text: String, font: SDUIFont? = nil, color: SDUIColor? = nil, style: SDUIStyle? = nil) -> SDUIElement {
        .text(SDUIText(text: text, font: font, color: color, style: style))
    }
    
    static func dynamicText(binding: SDUITextBinding, font: SDUIFont? = nil, color: SDUIColor? = nil, style: SDUIStyle? = nil) -> SDUIElement {
        .text(SDUIText(text: "", font: font, color: color, style: style, textBinding: binding))
    }
}

// MARK: - SDUIElement Decodable

extension SDUIElement: Decodable {
    private enum CodingKeys: String, CodingKey {
        case text, systemImage, asyncImage, asyncVideo, appIcon, button
        case vStack, hStack, zStack
        case spacer, shape, gradient, scrollView
        case forEach, conditional, group, textField, toggle, slideButton
        case compactPageIndicator, empty
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // OPTIMIZATION: First find which key exists, then decode only that type.
        // This avoids the stack overhead of try? decoding all types in sequence,
        // which was causing stack overflow on deeply nested JSON structures.
        
        if container.contains(.text) {
            self = .text(try container.decode(SDUIText.self, forKey: .text))
        } else if container.contains(.systemImage) {
            self = .systemImage(try container.decode(SDUISystemImage.self, forKey: .systemImage))
        } else if container.contains(.asyncImage) {
            self = .asyncImage(try container.decode(SDUIAsyncImage.self, forKey: .asyncImage))
        } else if container.contains(.asyncVideo) {
            self = .asyncVideo(try container.decode(SDUIAsyncVideo.self, forKey: .asyncVideo))
        } else if container.contains(.appIcon) {
            self = .appIcon(try container.decode(SDUIAppIcon.self, forKey: .appIcon))
        } else if container.contains(.button) {
            self = .button(try container.decode(SDUIButton.self, forKey: .button))
        } else if container.contains(.vStack) {
            self = .vStack(try container.decode(SDUIStack.self, forKey: .vStack))
        } else if container.contains(.hStack) {
            self = .hStack(try container.decode(SDUIStack.self, forKey: .hStack))
        } else if container.contains(.zStack) {
            self = .zStack(try container.decode(SDUIStack.self, forKey: .zStack))
        } else if container.contains(.spacer) {
            self = .spacer(try container.decode(SDUISpacer.self, forKey: .spacer))
        } else if container.contains(.shape) {
            self = .shape(try container.decode(SDUIShape.self, forKey: .shape))
        } else if container.contains(.gradient) {
            self = .gradient(try container.decode(SDUIGradient.self, forKey: .gradient))
        } else if container.contains(.scrollView) {
            self = .scrollView(try container.decode(SDUIScrollView.self, forKey: .scrollView))
        } else if container.contains(.forEach) {
            self = .forEach(try container.decode(SDUIForEach.self, forKey: .forEach))
        } else if container.contains(.conditional) {
            self = .conditional(try container.decode(SDUIConditional.self, forKey: .conditional))
        } else if container.contains(.group) {
            self = .group(try container.decode(SDUIGroup.self, forKey: .group))
        } else if container.contains(.textField) {
            self = .textField(try container.decode(SDUITextField.self, forKey: .textField))
        } else if container.contains(.toggle) {
            self = .toggle(try container.decode(SDUIToggle.self, forKey: .toggle))
        } else if container.contains(.slideButton) {
            self = .slideButton(try container.decode(SDUISlideButton.self, forKey: .slideButton))
        } else if container.contains(.compactPageIndicator) {
            self = .compactPageIndicator
        } else if container.contains(.empty) {
            self = .empty
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown SDUIElement type. Available keys: \(container.allKeys.map { $0.stringValue })"
                )
            )
        }
    }
}
