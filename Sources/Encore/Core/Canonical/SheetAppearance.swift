// The reward sheet's skin from app code: fonts the app registered and styles per tagged component.
// Merged per property under the portal skin, fonts from here only; contract in backend docs/architecture/sdui-sheet-skin.md.

import Foundation

/// The sheet's look from app code. A property the portal skin sets wins; app values fill the rest.
/// The two fonts come from here only: a portal skin sets no fonts.
public struct SheetAppearance: Sendable, Equatable {
    /// A font the app registered, for text a component styles with `font: .heading`. Unset, that text draws the system font.
    public var headingFontFamily: String?
    /// A font the app registered, for text styled `font: .body` and every other text on the sheet.
    public var bodyFontFamily: String?
    /// Styles by component name; a name no element in the variant carries does nothing.
    /// `offerTitle`, `offerDetail` and the `offerLogo` image are the advertiser's content: ignored with one warning.
    public var components: [SheetComponent: SheetComponentStyle]

    public init(
        headingFontFamily: String? = nil,
        bodyFontFamily: String? = nil,
        components: [SheetComponent: SheetComponentStyle] = [:]
    ) {
        self.headingFontFamily = headingFontFamily
        self.bodyFontFamily = bodyFontFamily
        self.components = components
    }
}

/// A component name a variant tags its elements with. Any string works, so a name added after
/// this release is styleable too; the constants are the catalogue at release time.
public struct SheetComponent: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ name: String) { self.rawValue = name }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let sheetBackground = SheetComponent("sheetBackground")
    public static let closeButton = SheetComponent("closeButton")
    public static let title = SheetComponent("title")
    public static let subtitle = SheetComponent("subtitle")
    public static let footnote = SheetComponent("footnote")
    public static let offerRow = SheetComponent("offerRow")
    public static let offerRowSelected = SheetComponent("offerRowSelected")
    public static let offerCard = SheetComponent("offerCard")
    public static let selectionIndicator = SheetComponent("selectionIndicator")
    public static let offerLogo = SheetComponent("offerLogo")
    public static let offerTitle = SheetComponent("offerTitle")
    public static let offerDetail = SheetComponent("offerDetail")
    public static let badge = SheetComponent("badge")
    public static let primaryButton = SheetComponent("primaryButton")
    public static let secondaryButton = SheetComponent("secondaryButton")
    public static let linkButton = SheetComponent("linkButton")
    public static let filterChip = SheetComponent("filterChip")
    public static let pageIndicator = SheetComponent("pageIndicator")
    public static let footer = SheetComponent("footer")
    public static let panel = SheetComponent("panel")
    public static let stepList = SheetComponent("stepList")
    public static let stepMarker = SheetComponent("stepMarker")
    public static let stepMarkerCurrent = SheetComponent("stepMarkerCurrent")
    public static let stepTitle = SheetComponent("stepTitle")
    public static let stepDetail = SheetComponent("stepDetail")
    public static let summaryCard = SheetComponent("summaryCard")
    public static let statusIcon = SheetComponent("statusIcon")
    public static let giftBox = SheetComponent("giftBox")
    public static let heroImage = SheetComponent("heroImage")
    public static let giftBoxImage = SheetComponent("giftBoxImage")
}

/// A Lottie file in place of a component's picture or icon. It plays when the host app links lottie-ios 4.x
/// and Reduce Motion is off; otherwise `fallbackImage` draws. EncoreKit never links Lottie.
public struct SheetAnimation: Sendable, Equatable {
    /// HTTPS Lottie JSON, at most 150 KB, with a content-hashed name.
    public var url: URL
    /// The still, drawn until the file is ready and whenever it cannot play.
    public var fallbackImage: URL
    /// Nil loops; false plays once and holds the last frame.
    public var loop: Bool?
    /// Nil plays; false draws the first frame.
    public var autoplay: Bool?
    /// Offer pictures for the file's placeholder images, by Lottie image asset id.
    public var images: [String: SheetAnimationImage]?

    public init(url: URL, fallbackImage: URL, loop: Bool? = nil, autoplay: Bool? = nil, images: [String: SheetAnimationImage]? = nil) {
        self.url = url
        self.fallbackImage = fallbackImage
        self.loop = loop
        self.autoplay = autoplay
        self.images = images
    }
}

/// Which of an offer's pictures fills a Lottie placeholder.
public enum SheetOfferPicture: String, Sendable, CaseIterable {
    case logo, hero, primaryCreative
}

/// An offer picture drawn into a Lottie placeholder, filling its box. `offer` is the position in the sheet's
/// offers, 0 to 9; a missing offer or picture keeps the placeholder.
public struct SheetAnimationImage: Sendable, Equatable {
    public var offer: Int
    public var picture: SheetOfferPicture

    public init(offer: Int, picture: SheetOfferPicture) {
        self.offer = offer
        self.picture = picture
    }
}

/// How a sheet motion eases.
public enum SheetMotionCurve: String, Sendable, CaseIterable {
    case linear, easeIn, easeOut, easeInOut
}

/// A pose relative to the element's own, applied after layout; a property left nil holds the element's value.
/// Scale 0 to 10 and rotation (degrees, -3600 to 3600) about the centre; setting one offset sets both, the other 0.
/// Offsets here are in points only; an offset in the element's own size (`offsetFraction`) is set in the portal.
public struct SheetPose: Sendable, Equatable {
    public var scale: Double?
    /// 0 to 1, multiplied with the element's own.
    public var opacity: Double?
    public var rotation: Double?
    /// Points, -2000 to 2000.
    public var offsetX: Double?
    public var offsetY: Double?

    public init(scale: Double? = nil, opacity: Double? = nil, rotation: Double? = nil, offsetX: Double? = nil, offsetY: Double? = nil) {
        self.scale = scale
        self.opacity = opacity
        self.rotation = rotation
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

/// An entrance from `from` to the element's own pose over `duration` seconds (above 0, at most 10), after
/// `delay` seconds (0 to 10). Skipped under Reduce Motion.
public struct SheetEnter: Sendable, Equatable {
    public var from: SheetPose
    public var duration: Double
    public var delay: Double?
    /// Nil eases out.
    public var curve: SheetMotionCurve?

    public init(from: SheetPose, duration: Double, delay: Double? = nil, curve: SheetMotionCurve? = nil) {
        self.from = from
        self.duration = duration
        self.delay = delay
        self.curve = curve
    }
}

/// One pose of a `SheetLoop`, `at` 0 to 1 through the cycle.
public struct SheetKeyframe: Sendable, Equatable {
    public var at: Double
    public var pose: SheetPose

    public init(at: Double, pose: SheetPose) {
        self.at = at
        self.pose = pose
    }
}

/// A repeating animation: `keyframes` (two or more, `at` from 0 to 1, never falling) over `duration` seconds,
/// started `phaseOffset` (0 to 1) of the way in, after `delay` seconds (0 to 30). After `repeatCount` cycles
/// (1 to 1000) it holds the last keyframe; nil runs forever. Under Reduce Motion it shows `reducedMotion`.
public struct SheetLoop: Sendable, Equatable {
    public var duration: Double
    public var keyframes: [SheetKeyframe]
    /// Nil is linear, applied per segment.
    public var curve: SheetMotionCurve?
    public var phaseOffset: Double?
    public var reducedMotion: SheetPose?
    public var delay: Double?
    public var repeatCount: Int?

    public init(
        duration: Double, keyframes: [SheetKeyframe], curve: SheetMotionCurve? = nil, phaseOffset: Double? = nil,
        reducedMotion: SheetPose? = nil, delay: Double? = nil, repeatCount: Int? = nil
    ) {
        self.duration = duration
        self.keyframes = keyframes
        self.curve = curve
        self.phaseOffset = phaseOffset
        self.reducedMotion = reducedMotion
        self.delay = delay
        self.repeatCount = repeatCount
    }
}

/// One component's look. Every field is optional; the tagged element's type decides which apply,
/// and a value that does not apply or is out of range is dropped with one warning.
public struct SheetComponentStyle: Sendable, Equatable {
    /// Which of the two sheet fonts a component's text takes.
    public enum FontRole: String, Sendable, CaseIterable {
        case heading
        case body
    }

    /// The background of a container, button or text, a shape's fill. One hex, or a light and a dark pair.
    public var fill: SheetColor?
    /// Points, 0 to 999 (999 draws a capsule).
    public var cornerRadius: CGFloat?
    /// Points, 0 to 8.
    public var borderWidth: CGFloat?
    public var borderColor: SheetColor?
    /// Text and icon colour, inside the component too.
    public var contentColor: SheetColor?
    public var font: FontRole?
    /// HTTPS: replaces a picture, or an icon (the button keeps its spoken label, and the icon shows until the image loads).
    public var image: URL?
    /// HTTPS: replaces a conditional's true or false branch, such as a selection check.
    public var trueImage: URL?
    public var falseImage: URL?
    /// HTTPS: covers the element's box behind its content, cropped at the edges and clipped to its corner.
    public var backgroundImage: URL?
    /// A Lottie file in place of the picture or icon; it wins over `image`.
    public var animation: SheetAnimation?
    /// An entrance played once when the element appears.
    public var enter: SheetEnter?
    /// A repeating animation; it replaces a served loop.
    public var loop: SheetLoop?

    /// The skin's original properties, kept as their own symbol for code built against them.
    public init(
        fill: SheetColor? = nil,
        cornerRadius: CGFloat? = nil,
        borderWidth: CGFloat? = nil,
        borderColor: SheetColor? = nil,
        contentColor: SheetColor? = nil,
        font: FontRole? = nil,
        image: URL? = nil,
        trueImage: URL? = nil,
        falseImage: URL? = nil,
        backgroundImage: URL? = nil
    ) {
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.contentColor = contentColor
        self.font = font
        self.image = image
        self.trueImage = trueImage
        self.falseImage = falseImage
        self.backgroundImage = backgroundImage
    }

    /// Every property, motion included. Disfavoured, so a call naming only the original ones resolves above.
    @_disfavoredOverload
    public init(
        fill: SheetColor? = nil,
        cornerRadius: CGFloat? = nil,
        borderWidth: CGFloat? = nil,
        borderColor: SheetColor? = nil,
        contentColor: SheetColor? = nil,
        font: FontRole? = nil,
        image: URL? = nil,
        trueImage: URL? = nil,
        falseImage: URL? = nil,
        backgroundImage: URL? = nil,
        animation: SheetAnimation? = nil,
        enter: SheetEnter? = nil,
        loop: SheetLoop? = nil
    ) {
        self.init(fill: fill, cornerRadius: cornerRadius, borderWidth: borderWidth, borderColor: borderColor,
                  contentColor: contentColor, font: font, image: image, trueImage: trueImage, falseImage: falseImage,
                  backgroundImage: backgroundImage)
        self.animation = animation
        self.enter = enter
        self.loop = loop
    }
}

/// A sheet colour: one hex (`#RRGGBB` or `#RRGGBBAA`) for both schemes, or a light and a dark one.
/// A string literal is one hex, so `fill: "#F5C52B"` works. A bad hex is dropped with one warning.
public struct SheetColor: Sendable, Equatable, ExpressibleByStringLiteral {
    /// The hex drawn in light mode.
    public let light: String
    /// The hex drawn in dark mode; the same as `light` for a single colour.
    public let dark: String

    /// One hex for both schemes.
    public init(_ hex: String) {
        self.light = hex
        self.dark = hex
    }

    /// A hex for each scheme; the sheet draws the one the system is in.
    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    public init(stringLiteral value: String) { self.init(value) }
}
