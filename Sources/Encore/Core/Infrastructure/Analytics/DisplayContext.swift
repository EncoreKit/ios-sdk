// The window an offer sheet renders in, sent as `display` on `sdk_offer_presentation_success`
// so session replay can draw the layout at the user's size (EncoreKit/backend#848).
// Read once when the sheet shows; no device model, because a replay needs the layout, not the hardware.

import UIKit

struct DisplayContext: Encodable, Equatable {
    let widthPt: Double
    let heightPt: Double
    let safeAreaTopPt: Double
    let safeAreaBottomPt: Double
    let safeAreaLeftPt: Double
    let safeAreaRightPt: Double
    /// Body text size relative to the default content size category, so 1 is the system default.
    let fontScale: Double
    let colorScheme: String
    let orientation: String

    /// The mapping from window values to the wire, kept pure so its rules are testable without a window.
    static func make(
        size: CGSize,
        insets: UIEdgeInsets,
        contentSize: UIContentSizeCategory,
        style: UIUserInterfaceStyle
    ) -> DisplayContext {
        let base: CGFloat = 17
        let scaled = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: base, compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSize))
        return DisplayContext(
            widthPt: Double(size.width),
            heightPt: Double(size.height),
            safeAreaTopPt: Double(insets.top),
            safeAreaBottomPt: Double(insets.bottom),
            safeAreaLeftPt: Double(insets.left),
            safeAreaRightPt: Double(insets.right),
            fontScale: (Double(scaled / base) * 100).rounded() / 100,
            colorScheme: style == .dark ? "dark" : "light",
            orientation: size.width > size.height ? "landscape" : "portrait"
        )
    }

    /// The app window the sheet will show in. `appearance` is the sheet's own override, which wins over the window's style.
    @MainActor
    static func current(appearance: UIUserInterfaceStyle) -> DisplayContext? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return nil }
        let traits = window.traitCollection
        return make(
            size: window.bounds.size,
            insets: window.safeAreaInsets,
            contentSize: traits.preferredContentSizeCategory,
            style: appearance == .unspecified ? traits.userInterfaceStyle : appearance
        )
    }
}
