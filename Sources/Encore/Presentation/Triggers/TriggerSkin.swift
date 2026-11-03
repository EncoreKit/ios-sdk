// The publisher's chrome on a trigger look: font family, outer-shape radius, shadow, border and
// images from `AppearanceConfig`, written into the checked tree before it decodes. The look's own
// value stays wherever a token is unset, so no look JSON changes for any of it.

import SwiftUI
import UIKit

/// `AppearanceConfig`'s chrome fields for one mount, checked against the device: a font or image
/// that does not load reads as unset (logged once), so the look's own value draws.
internal struct TriggerSkin: Hashable, Sendable {
    var fontFamily: String?
    var countdownFontFamily: String?
    var cornerRadius: CGFloat?
    var shadow: EncoreShadow?
    var borderWidth: CGFloat?
    var borderColor: AppearanceHex.RGBA?
    var backgroundImage: String?
    /// Set only with an image: alone it changes nothing.
    var backgroundImageCapInsets: CapInsets?
    var iconImage: String?

    /// `EdgeInsets` as a hashable value, in points of the image's own size.
    struct CapInsets: Hashable, Sendable {
        var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat

        /// Nil for a NaN, infinite or negative side: the image aspect-fills instead.
        init?(_ insets: EdgeInsets) {
            let sides = [insets.top, insets.leading, insets.bottom, insets.trailing]
            guard sides.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
            (top, leading, bottom, trailing) = (insets.top, insets.leading, insets.bottom, insets.trailing)
        }
    }

    /// No chrome: the look as served.
    static let plain = TriggerSkin()

    static func resolve(_ appearance: AppearanceConfig?) -> TriggerSkin {
        guard let appearance else { return .plain }
        var skin = TriggerSkin()
        skin.fontFamily = appearance.fontFamily.flatMap { checkedFont($0, field: "fontFamily", drawing: "the system font") }
        skin.countdownFontFamily = appearance.countdownFontFamily.flatMap { checkedFont($0, field: "countdownFontFamily", drawing: "fontFamily, else the system font") }
        skin.cornerRadius = appearance.cornerRadius.flatMap { bounded($0, TriggerVocabulary.cornerRadiusRange) }
        skin.shadow = appearance.shadow
        skin.borderWidth = appearance.borderWidth.flatMap { bounded($0, TriggerVocabulary.lineWidthRange) }
        skin.borderColor = AppearanceHex.parseField(appearance.borderColor, name: "borderColor")
        skin.backgroundImage = appearance.backgroundImage.flatMap { checkedImage($0, field: "backgroundImage") }
        if skin.backgroundImage != nil { skin.backgroundImageCapInsets = appearance.backgroundImageCapInsets.flatMap(CapInsets.init) }
        skin.iconImage = appearance.iconImage.flatMap { checkedImage($0, field: "iconImage") }
        return skin
    }

    /// Clamped to the vocabulary's own range, as a served look is; NaN reads as unset.
    private static func bounded(_ value: CGFloat, _ range: ClosedRange<Double>) -> CGFloat? {
        guard !value.isNaN else { return nil }
        return CGFloat(min(max(Double(value), range.lowerBound), range.upperBound))
    }

    /// The SDK bundles no fonts: a name the app did not register falls back to the system font.
    private static func checkedFont(_ family: String, field: String, drawing fallback: String) -> String? {
        guard UIFont(name: family, size: 17) != nil else {
            TriggerLog.once("skin.font.\(field).\(family)", "\(field) '\(family)' is not registered (UIAppFonts); drawing \(fallback)")
            return nil
        }
        return family
    }

    private static func checkedImage(_ name: String, field: String) -> String? {
        guard SDUIBundleImage.provider(name) != nil else {
            TriggerLog.once("skin.image.\(field).\(name)", "\(field) '\(name)' is not in the app's main bundle; drawing the look's own")
            return nil
        }
        return name
    }

    // MARK: Values

    /// `${icon}` and `${appIconUrl}` with the app's icon image in the slot (the look's `appIcon`
    /// branch, loading from the bundle). An `icon: .none` mount still hides the slot.
    func iconValues(over values: [String: String]) -> [String: String] {
        guard let iconImage, values["icon"] != TriggerIcon.none.rawValue else { return values }
        var values = values
        values["icon"] = TriggerIcon.appIcon.rawValue
        values["appIconUrl"] = SDUIBundleImage.url(named: iconImage).absoluteString
        return values
    }

    // MARK: Tree

    /// The tree with this skin: `family` on every text font (the countdown family on a
    /// `monospacedDigits` font), and the radius, shadow, border and background image on the outer
    /// surface (see ``replacingSurface(_:_:)``).
    func apply(to root: JSONValue) -> JSONValue {
        guard self != .plain else { return root }
        var tree = root
        if fontFamily != nil || countdownFontFamily != nil {
            tree = Self.rewritingFonts(root, glyphs: false) { font in
                let numeric = font["monospacedDigits"] == .bool(true)
                if let family = numeric ? countdownFontFamily ?? fontFamily : fontFamily { font["family"] = .string(family) }
            }
        }
        // Nothing beyond the fonts and the icon: no surface to rewrite.
        guard self != TriggerSkin(fontFamily: fontFamily, countdownFontFamily: countdownFontFamily, iconImage: iconImage) else { return tree }
        return Self.replacingSurface(tree, skinnedSurface) ?? Self.replacingRoot(tree, skinnedSurface)
    }

    /// Where a wrapper nests its surface (a button's content, a stack's children), in search order.
    private static let childKeys = ["content", "children"]

    /// A surface draws a fill: the look's card, or the pill inside a centring wrapper.
    static func isSurface(_ element: [String: JSONValue]) -> Bool {
        guard case .object(let style)? = element["style"] else { return false }
        return style["backgroundColor"] != nil || style["backgroundElement"] != nil
    }

    /// `wrapper` (`{"<type>": {...}}`) with its first surface, depth first, replaced by
    /// `replace(type, body)`; nil when it holds none.
    static func replacingSurface(_ wrapper: JSONValue, _ replace: (String, [String: JSONValue]) -> JSONValue) -> JSONValue? {
        guard case .object(let outer) = wrapper, outer.count == 1, let (type, body) = outer.first, case .object(var element) = body else { return nil }
        if isSurface(element) { return replace(type, element) }
        for key in childKeys {
            switch element[key] {
            case .object(_)?:
                guard let child = element[key], let rewritten = replacingSurface(child, replace) else { continue }
                element[key] = rewritten
                return .object([type: .object(element)])
            case .array(var items)?:
                for index in items.indices {
                    guard let rewritten = replacingSurface(items[index], replace) else { continue }
                    items[index] = rewritten
                    element[key] = .array(items)
                    return .object([type: .object(element)])
                }
            default:
                continue
            }
        }
        return nil
    }

    private static func replacingRoot(_ wrapper: JSONValue, _ replace: (String, [String: JSONValue]) -> JSONValue) -> JSONValue {
        guard case .object(let outer) = wrapper, outer.count == 1, let (type, body) = outer.first, case .object(let element) = body else { return wrapper }
        return replace(type, element)
    }

    /// The style keys that draw a surface's fill and its shape.
    private static let fillKeys = ["backgroundColor", "backgroundElement", "cornerRadius", "cornerRadii", "clipShape"]

    /// The skinned surface. One with a `clipShape` (`featured`, `walkie`) moves its fill behind it,
    /// into a wrapper that casts the shadow outside the clip from the fill, never from the text.
    private func skinnedSurface(_ type: String, _ element: [String: JSONValue]) -> JSONValue {
        var element = skinned(element)
        guard shadow != nil, case .object(var style)? = element["style"], style["clipShape"] != nil,
              let cast = style.removeValue(forKey: "shadow") else { return .object([type: .object(element)]) }
        var fill = style.filter { Self.fillKeys.contains($0.key) }
        fill["frame"] = Self.fillFrame
        style["backgroundColor"] = nil
        style["backgroundElement"] = nil
        element["style"] = .object(style)
        let caster = JSONValue.object(["zStack": .object([
            "children": .array([.object(["shape": .object(["type": .string("rectangle"), "fillColor": Self.clear, "style": .object(fill)])])]),
            "style": .object(["shadow": cast, "frame": Self.fillFrame]),
        ])])
        return .object(["zStack": .object(["children": .array([.object([type: .object(element)])]), "style": .object(["backgroundElement": caster])])])
    }

    private func skinned(_ element: [String: JSONValue]) -> [String: JSONValue] {
        var element = element
        var style: [String: JSONValue] = [:]
        if case .object(let served)? = element["style"] { style = served }
        if let cornerRadius {
            let radius = JSONValue.number(Double(cornerRadius))
            style["cornerRadius"] = radius
            style["cornerRadii"] = nil
            // A rectangle clip rounds with the surface, so the content never shows a different corner.
            if case .object(var clip)? = style["clipShape"], case .object(var rectangle)? = clip["rectangle"] {
                rectangle["cornerRadius"] = radius
                clip["rectangle"] = .object(rectangle)
                style["clipShape"] = .object(clip)
            }
        }
        if let shadow { style["shadow"] = Self.shadowJSON(shadow) }
        // Each border token alone keeps the look's other half, else 1 pt in the accent.
        if borderWidth != nil || borderColor != nil {
            style["borderWidth"] = borderWidth.map { .number(Double($0)) } ?? style["borderWidth"] ?? .number(1)
            style["borderColor"] = borderColor.map(Self.colorJSON) ?? style["borderColor"] ?? .object(["appearance": .string("accent")])
        }
        if let backgroundImage {
            let image = Self.imageJSON(backgroundImage, capInsets: backgroundImageCapInsets)
            // Above the look's own background element (a gradient), so a transparent image keeps it.
            style["backgroundElement"] = style["backgroundElement"].map { served in
                .object(["zStack": .object(["children": .array([served, image]), "style": .object(["frame": Self.fillFrame])])])
            } ?? image
        }
        element["style"] = .object(style)
        return element
    }

    /// Every `font` object in the tree through `transform`; `glyphs: false` leaves a `systemImage`
    /// alone (a symbol keeps the system face).
    static func rewritingFonts(_ value: JSONValue, glyphs: Bool, _ transform: (inout [String: JSONValue]) -> Void) -> JSONValue {
        switch value {
        case .object(let fields):
            var result = fields
            for (key, child) in fields {
                if key == "systemImage", !glyphs { continue }
                if key == "font", case .object(var font) = child {
                    transform(&font)
                    result[key] = .object(font)
                } else {
                    result[key] = rewritingFonts(child, glyphs: glyphs, transform)
                }
            }
            return .object(result)
        case .array(let items):
            return .array(items.map { rewritingFonts($0, glyphs: glyphs, transform) })
        default:
            return value
        }
    }

    // MARK: JSON

    private static let fillFrame = JSONValue.object(["maxWidth": .string("infinity"), "maxHeight": .string("infinity")])
    private static let clear = JSONValue.object(["hex": .string("#00000000")])

    /// The preset as the engine's `shadow`; nil removes the look's own.
    static func shadowJSON(_ preset: EncoreShadow) -> JSONValue? {
        let (opacity, radius, y): (Double, Double, Double)
        switch preset {
        case .flat: return nil
        case .soft: (opacity, radius, y) = (0.12, 8, 2)
        case .strong: (opacity, radius, y) = (0.28, 16, 6)
        }
        return .object(["color": .object(["hex": .string("#000000")]), "opacity": .number(opacity), "radius": .number(radius), "x": .number(0), "y": .number(y)])
    }

    /// The engine reads 8 hex digits as ARGB.
    static func colorJSON(_ color: AppearanceHex.RGBA) -> JSONValue {
        .object(["hex": .string(String(format: "#%02X%02X%02X%02X", color.a, color.r, color.g, color.b))])
    }

    /// A bundled image filling and clipped to its slot, stretched between `capInsets` when set. The
    /// fallback is a clear shape, not `empty`: an empty placeholder never appears, so the image would
    /// never load.
    static func imageJSON(_ name: String, capInsets: CapInsets? = nil) -> JSONValue {
        var image: [String: JSONValue] = [
            "url": .string(SDUIBundleImage.url(named: name).absoluteString),
            "contentMode": .string("fill"),
            "fallback": .object(["shape": .object(["type": .string("rectangle"), "fillColor": clear])]),
            "style": .object(["frame": fillFrame, "clipped": .bool(true), "accessibilityHidden": .bool(true)]),
        ]
        if let capInsets {
            image["capInsets"] = .object(["top": .number(capInsets.top), "leading": .number(capInsets.leading), "bottom": .number(capInsets.bottom), "trailing": .number(capInsets.trailing)])
        }
        return .object(["asyncImage": .object(image)])
    }
}
