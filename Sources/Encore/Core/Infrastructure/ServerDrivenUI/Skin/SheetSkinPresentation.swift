// Applies the merged sheet skin (portal over app code) to one presentation's layout. An empty skin
// returns the same layout untouched, so an unskinned sheet draws exactly as before.

import Foundation
import ImageIO
import UIKit

enum SheetSkinPresentation {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var logged: Set<String> = []

    /// The layout to draw. Re-decodes the raw template only for a non-empty skin, with this skin's app
    /// families baked into its role markers, and falls back to the served layout if the rewrite does not decode.
    static func skinned(
        _ layout: PresentationLayout?,
        app: SheetAppearance?,
        served: JSONValue?,
        scheme: SkinScheme,
        iconLabel: @escaping (_ icon: String, _ action: String?) -> String?
    ) -> PresentationLayout? {
        var warnings: [String] = []
        let skin = SheetSkinReader.resolveSheetSkin(app, portal: served.map(SkinJSON.init), warn: { warnings.append($0) })

        guard !SheetSkinReader.isEmptySkin(skin.components, fonts: skin.fontFlags),
              var layout, layout.config != nil, let raw = layout.rawTemplate else {
            log(warnings, id: skin.id)
            return layout
        }
        do {
            let template = try SkinJSON.parse(raw)
            let rewritten = SheetSkinApplier.applySkin(template, components: skin.components, options: .init(
                scheme: scheme, fonts: skin.fontFlags, iconLabel: iconLabel, warn: { warnings.append($0) }))
            let decoder = JSONDecoder()
            decoder.userInfo[.sheetFontRoles] = skin.fonts
            layout.config = try decoder.decode(SDUIConfig.self, from: rewritten.serialized())
            // From the served skin only, so app code alone never reads as a portal skin.
            layout.skinId = skin.id
            log(warnings, id: skin.id)
            Logger.info(.presentation, "[SKIN] Applied skin \(skin.id ?? "from app code")")
            return layout
        } catch {
            log(warnings, id: skin.id)
            Logger.error(.domain("[SKIN] The skinned sheet did not decode, drawing the served one: \(error)"), context: .presentOfferInitialization)
            return layout
        }
    }

    /// The presentation's skin: the served skin wins per property, its placement's `sheet` value (never the
    /// trigger fields) fills what it leaves unset, and the variant applies where neither sets it. Fonts are app code only.
    @MainActor
    static func skinned(_ layout: PresentationLayout?, for offerContext: OfferContext) -> PresentationLayout? {
        let strings = offerContext.strings
        return skinned(
            layout,
            app: offerContext.appearance?.sheet,
            served: offerContext.uiValues?.skin,
            scheme: scheme(for: offerContext.appearanceMode),
            iconLabel: { icon, action in
                SDUIIconButtonLabel.label(action: action.flatMap(SDUIActionType.init(rawValue:)), glyph: icon, strings: strings)
            }
        )
    }

    /// Each warning once per skin id and message.
    private static func log(_ warnings: [String], id: String?) {
        lock.lock()
        let fresh = warnings.filter { logged.insert("\(id ?? "")|\($0)").inserted }
        lock.unlock()
        for warning in fresh { Logger.warn(.presentation, "[SKIN] \(warning)") }
    }

    /// Above this many pixels a skin layer's picture is dropped, as web's `MAX_SKIN_IMAGE_PIXELS`.
    static let maxSkinImagePixels = 4_000_000

    /// Width times height from the image header, without decoding the pixels; nil when unreadable.
    static func pixelCount(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : pixels
    }

    /// One warning per url, in web's words, for a skin layer picture over the cap.
    static func warnOversizedImage(_ url: URL) {
        log(["skin image \(url.absoluteString) is over \(maxSkinImagePixels / 1_000_000) MP; its layer is dropped"], id: nil)
    }

    /// The portal skin's image and animation URLs, fetched when `/config` arrives so the first sheet is a cache hit.
    static func prefetch(served: JSONValue?) {
        guard let served else { return }
        let skin = SheetSkinReader.readSkin(SkinJSON(served), warn: { _ in })
        let animations = Set(skin.components.values.compactMap { $0.animation?.url }).compactMap(URL.init(string:))
        if !animations.isEmpty {
            // Only a host that can play them downloads them, as at draw time.
            Task { @MainActor in
                guard SDUILottieBridge.isAvailable, !UIAccessibility.isReduceMotionEnabled else { return }
                for url in animations { _ = await SDUILottieLoader.shared.load(url) }
            }
        }
        let images = Set(skin.components.values.flatMap(\.imageURLs)).compactMap(URL.init(string:))
        guard !images.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in images { _ = try? await SDUIImageLoader.load(url) }
        }
    }

    /// The scheme the skin's light and dark colours resolve for: the sheet's own mode, else the device's.
    @MainActor
    static func scheme(for mode: OfferContext.AppearanceMode) -> SkinScheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .auto:
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            return (window?.traitCollection.userInterfaceStyle ?? UITraitCollection.current.userInterfaceStyle) == .dark ? .dark : .light
        }
    }

    #if DEBUG
    static func resetForTesting() {
        lock.lock()
        logged = []
        lock.unlock()
    }
    #endif
}
