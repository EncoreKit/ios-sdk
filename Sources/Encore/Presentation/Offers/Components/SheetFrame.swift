//
//  The offer sheet's frame for one window shape. Portrait keeps the authored sheet;
//  a landscape window gets a centred column drawn smaller, so a short window still shows offers.
//

import SwiftUI

/// The sheet's size for one window. A nil `maxWidth` means the authored, full-width sheet.
struct SheetFrame: Equatable {
    var maxWidth: CGFloat?
    var heightFraction: CGFloat
    var contentScale: CGFloat = 1
    var verticalSpacingScale: CGFloat = 1

    var isColumn: Bool { maxWidth != nil }

    /// The authored sheet, unchanged.
    static let portrait = SheetFrame(maxWidth: nil, heightFraction: 1)

    /// The column's width, the same as Android's 440 dp.
    static let columnWidth: CGFloat = 440
    /// A sheet column's share of the window height.
    static let columnHeightFraction: CGFloat = 0.94
    /// A short window draws the column at height / 560 pt, so a fixed-height carousel still fits.
    static let referenceHeight: CGFloat = 560
    /// The smallest scale, so text stays readable on the shortest window.
    static let minContentScale: CGFloat = 0.55
    /// The factor for empty vertical space when the column is drawn smaller than authored.
    static let shortWindowVerticalSpacing: CGFloat = 0.5
    /// The dim over the app around a column.
    static let dimOpacity: Double = 0.5

    /// A variant's dim around its column, clamped to 0 through 1.
    static func dimOpacity(_ floating: SDUILandscapeColumn?) -> Double {
        min(max(floating?.dimOpacity ?? dimOpacity, 0), 1)
    }
    /// The status bar is hidden in a column, so its top inset is 0; content keeps at least this margin.
    static let minColumnMargin: CGFloat = 16

    /// Width over height; a square window counts as portrait.
    static func isLandscape(_ window: CGSize) -> Bool { window.width > window.height }

    /// The column's draw scale for a window height, between `minContentScale` and 1.
    static func contentScale(windowHeight: CGFloat) -> CGFloat {
        min(max(windowHeight / referenceHeight, minContentScale), 1)
    }

    /// The frame for a window: `.portrait` unless it is wider than tall.
    static func make(window: CGSize) -> SheetFrame {
        guard isLandscape(window) else { return .portrait }
        let scale = contentScale(windowHeight: window.height)
        return SheetFrame(
            maxWidth: columnWidth,
            heightFraction: columnHeightFraction,
            contentScale: scale,
            // Only a short window gives up empty space; a tablet keeps the authored layout.
            verticalSpacingScale: scale < 1 ? shortWindowVerticalSpacing : 1
        )
    }

    /// The frame for a presentation: a sheet becomes a column only in compact height, where it adapts to a cover,
    /// so an iPad form sheet keeps its layout.
    static func make(window: CGSize, isFullScreen: Bool, compactHeight: Bool) -> SheetFrame {
        isFullScreen || compactHeight ? make(window: window) : .portrait
    }

    /// The frame drawn at a floating column's own height, so a large inset shrinks the content instead of clipping it.
    func scaled(toColumnHeight height: CGFloat) -> SheetFrame {
        var frame = self
        frame.contentScale = Self.contentScale(windowHeight: height)
        frame.verticalSpacingScale = frame.contentScale < 1 ? Self.shortWindowVerticalSpacing : 1
        return frame
    }

    /// The column's size in a window, or nil for the authored portrait sheet. A full-screen layout takes the full
    /// height, and a floating column keeps `inset` clear above and below, at most a quarter of the height each.
    func columnSize(window: CGSize, fullHeight: Bool, inset: CGFloat? = nil) -> CGSize? {
        guard let maxWidth else { return nil }
        let height = inset.map { window.height - 2 * min(max($0, 0), window.height / 4) }
            ?? window.height * (fullHeight ? 1 : heightFraction)
        return CGSize(width: min(maxWidth, window.width), height: height)
    }

    /// A centred column keeps clear of the top and bottom insets only, in its own scaled points, and never less than the margin.
    static func columnSafeArea(_ device: EdgeInsets, scale: CGFloat) -> EdgeInsets {
        EdgeInsets(top: max(device.top / scale, minColumnMargin), leading: 0, bottom: max(device.bottom / scale, minColumnMargin), trailing: 0)
    }
}
