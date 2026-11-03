//
//  Which vertical space a short landscape column halves: positive vStack spacing, clear spacer rectangles, and
//  padding that draws nothing. Anything inside a fixed height keeps its size, where shrinking frees nothing.
//

import SwiftUI

/// The vertical-space rule for a short landscape column, kept pure so it can be tested like Android's `SduiVerticalSpacing`.
enum SDUIVerticalSpacing {

    /// The factor for this style's vertical padding: `factor` when it draws nothing and frees height, else 1.
    static func paddingScale(_ style: SDUIStyle?, factor: CGFloat) -> CGFloat {
        guard factor != 1, let style, !fixesHeight(style) else { return 1 }
        return paintsAroundPadding(style) ? 1 : factor
    }

    /// The factor this element's children read: 1 inside a fixed or relative height, where shrinking frees nothing.
    static func childScale(_ style: SDUIStyle?, factor: CGFloat) -> CGFloat {
        guard let style, fixesHeight(style) else { return factor }
        return 1
    }

    /// Stack spacing scaled by `factor`. A negative spacing is a deliberate overlap, so it keeps its size.
    static func stackSpacing(_ spacing: CGFloat?, factor: CGFloat) -> CGFloat {
        let value = spacing ?? 0
        return value > 0 ? value * factor : value
    }

    /// A container-relative frame sizes the height only on the vertical axis; with no axis iOS sizes the width.
    private static func fixesHeight(_ style: SDUIStyle) -> Bool {
        style.frame?.height != nil || style.relativeHeight != nil || style.containerRelativeFrame?.axis == .vertical
    }

    /// Vertical edges take `scale`; horizontal edges keep their size.
    static func scaled(_ insets: EdgeInsets, vertical scale: CGFloat) -> EdgeInsets {
        EdgeInsets(top: insets.top * scale, leading: insets.leading, bottom: insets.bottom * scale, trailing: insets.trailing)
    }

    /// A clear rectangle with a fixed height and no width, min or max height is a spacer, so its height takes `factor`.
    /// Alphas are the resolved fill and stroke; nil means none is set.
    static func spacerStyle(_ shape: SDUIShape, fillAlpha: CGFloat?, strokeAlpha: CGFloat?, factor: CGFloat) -> SDUIStyle? {
        let style = shape.style
        guard factor != 1, shape.type == .rectangle, (fillAlpha ?? 0) == 0, (strokeAlpha ?? 0) == 0,
              var frame = style?.frame, let height = frame.height,
              frame.width == nil, frame.minHeight == nil, frame.maxHeight == nil,
              let style, !paintsAroundPadding(style) else { return style }
        frame.height = height * factor
        var spacer = style
        spacer.frame = frame
        return spacer
    }

    /// The same steps Android's `SduiStylePlan` counts as drawing around the content.
    private static func paintsAroundPadding(_ style: SDUIStyle) -> Bool {
        style.backgroundElement != nil
            || style.backgroundColor != nil
            || style.shadow != nil
            || style.resolvedCornerRadius > 0
            || (style.borderWidth ?? 0) > 0
            || style.gradientBorder != nil
            || style.innerShadow != nil
            || style.clipShape != nil
            || style.overlay != nil
    }
}

private struct SDUIVerticalSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct SDUISafeAreaOverrideKey: EnvironmentKey {
    static let defaultValue: EdgeInsets? = nil
}

extension EnvironmentValues {
    /// The factor a short landscape column applies to empty vertical space. 1 everywhere else.
    var sduiVerticalSpacing: CGFloat {
        get { self[SDUIVerticalSpacingKey.self] }
        set { self[SDUIVerticalSpacingKey.self] = newValue }
    }

    /// The safe area a host gives its content when that is not the device's (a centred landscape column).
    var sduiSafeAreaOverride: EdgeInsets? {
        get { self[SDUISafeAreaOverrideKey.self] }
        set { self[SDUISafeAreaOverrideKey.self] = newValue }
    }
}
