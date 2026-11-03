//
//  AppearanceConfig.swift
//  Encore
//
//  Placement-level brand colours and trigger chrome, set in app code alongside the app's own theme.
//  Mirrors the web SDK's `PlacementOptions.appearance` names and hex formats.
//

import Foundation
import SwiftUI

/// Brand colours for one presentation. Unset fields keep the sheet's defaults.
/// Hex formats: `#RGB`, `#RRGGBB`, `#RRGGBBAA` (alpha last, as in CSS).
public struct AppearanceConfig: Sendable, Equatable {
    /// Primary CTAs, selected states and the active page dot.
    public var accentColor: String?
    /// Sheet canvas; card and divider colours are derived from it.
    public var backgroundColor: String?
    /// Primary text; on the sheet it applies only together with `backgroundColor`.
    public var textColor: String?
    /// Secondary copy in trigger components; unset, the text colour faded as each look draws it.
    public var secondaryTextColor: String?
    /// Progress tracks in trigger components; unset, the text colour faded as each look draws it.
    public var trackColor: String?
    /// Ink on the accent (arrows, button labels) in trigger components. Unset, an arrow is black or
    /// white for contrast, and a label is the background colour when it reads at 3:1 on the accent,
    /// else black or white.
    public var onAccentColor: String?
    /// Light or dark for trigger components; nil follows the app's portal setting, else dark.
    public var colorScheme: ColorScheme?
    /// The second stop of a trigger look's background gradient (leading to trailing); unset, the
    /// look is solid in the background colour. Trigger components only; the sheet ignores it.
    public var backgroundEndColor: String?

    // MARK: Trigger chrome (trigger components only; the sheet ignores every field below)

    /// A font the app registered (`UIAppFonts`), drawn for every text run at the look's own size
    /// and weight: a face name resolves to its family at that weight. A name `UIFont` cannot load
    /// falls back to the system font, with one warning.
    public var fontFamily: String?
    /// A second registered font for numeric runs (a countdown's digits): every text run whose font
    /// has `monospacedDigits`. Unset, those runs draw `fontFamily`; a name `UIFont` cannot load falls
    /// back the same way, with one warning.
    public var countdownFontFamily: String?
    /// The look's outer shape corner radius, in points.
    public var cornerRadius: CGFloat?
    /// A shadow preset on the look's outer shape; unset keeps the look's own shadow.
    public var shadow: EncoreShadow?
    /// A stroke inside the look's outer shape, in points; alone, it draws in the look's own border
    /// colour, else the accent.
    public var borderWidth: CGFloat?
    /// The stroke's colour (hex); alone, it draws at the look's own border width, else 1 pt.
    public var borderColor: String?
    /// An image in the app's main bundle, filling the look's outer shape above `backgroundColor`.
    public var backgroundImage: String?
    /// Cap insets, in points of the image's own size: set, `backgroundImage` is stretched to the look's
    /// frame with its corners kept (a shape image); unset, it is aspect-filled and cropped.
    public var backgroundImageCapInsets: EdgeInsets?
    /// An image in the app's main bundle, drawn in the look's icon slot in place of the gift or app icon.
    /// Per component instance: a gift button and a claim reminder each take their own.
    public var iconImage: String?

    /// The palette a trigger component draws with.
    public enum ColorScheme: String, Sendable, CaseIterable {
        /// Follows the device's light or dark appearance.
        case system
        case light
        case dark
    }

    /// The 2.1 initializer, kept as its own symbol so binaries built against it still link.
    public init(accentColor: String? = nil, backgroundColor: String? = nil, textColor: String? = nil) {
        self.init(accentColor: accentColor, backgroundColor: backgroundColor, textColor: textColor, colorScheme: nil)
    }

    /// The 2.4 initializer, kept as an exported symbol for the XCFramework ABI. Disfavoured so a
    /// call that names only the three sheet colours keeps resolving to the 2.1 initializer above.
    @_disfavoredOverload
    public init(
        accentColor: String? = nil,
        backgroundColor: String? = nil,
        backgroundEndColor: String? = nil,
        textColor: String? = nil,
        secondaryTextColor: String? = nil,
        trackColor: String? = nil,
        onAccentColor: String? = nil,
        colorScheme: ColorScheme? = nil
    ) {
        self.init(
            accentColor: accentColor, backgroundColor: backgroundColor, backgroundEndColor: backgroundEndColor, textColor: textColor,
            secondaryTextColor: secondaryTextColor, trackColor: trackColor, onAccentColor: onAccentColor, colorScheme: colorScheme,
            fontFamily: nil
        )
    }

    /// Disfavoured so a call that names none of the chrome fields resolves to the older initializers.
    @_disfavoredOverload
    public init(
        accentColor: String? = nil,
        backgroundColor: String? = nil,
        backgroundEndColor: String? = nil,
        textColor: String? = nil,
        secondaryTextColor: String? = nil,
        trackColor: String? = nil,
        onAccentColor: String? = nil,
        colorScheme: ColorScheme? = nil,
        fontFamily: String? = nil,
        countdownFontFamily: String? = nil,
        cornerRadius: CGFloat? = nil,
        shadow: EncoreShadow? = nil,
        borderWidth: CGFloat? = nil,
        borderColor: String? = nil,
        backgroundImage: String? = nil,
        backgroundImageCapInsets: EdgeInsets? = nil,
        iconImage: String? = nil
    ) {
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.backgroundEndColor = backgroundEndColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.trackColor = trackColor
        self.onAccentColor = onAccentColor
        self.colorScheme = colorScheme
        self.fontFamily = fontFamily
        self.countdownFontFamily = countdownFontFamily
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.backgroundImage = backgroundImage
        self.backgroundImageCapInsets = backgroundImageCapInsets
        self.iconImage = iconImage
    }
}

/// A drop shadow preset for a trigger component's outer shape. Not `none`: on an optional field
/// Swift reads `.none` as `nil`, which would silently keep the look's own shadow.
public enum EncoreShadow: String, Sendable, CaseIterable {
    /// No shadow, even when the look draws one.
    case flat
    /// Black at 12%, 8 pt blur, 2 pt down.
    case soft
    /// Black at 28%, 16 pt blur, 6 pt down.
    case strong
}
