//
//  Draws the offer sheet as a centred, scaled column when its window is landscape; `LandscapeColumnDim` dims the app.
//  One view structure in both orientations, so a rotation re-lays the sheet out without rebuilding it.
//

import SwiftUI

/// Portrait keeps the authored sheet; a landscape window gets the centred, scaled column `SheetFrame` describes.
@available(iOS 17.0, *)
struct OfferSheetColumnModifier: ViewModifier {
    /// The column's fill; the dimmed app shows around it.
    let background: Color
    /// The portrait presentation background, or nil to keep the system's.
    let presentationBackground: Color?
    let isFullScreen: Bool
    let cornerRadius: CGFloat
    /// Floats the column inside the window with all corners rounded; nil keeps the default height, at the bottom for a sheet.
    let floating: SDUILandscapeColumn?
    /// Whether `LandscapeColumnDim` dims under the presentation, so the column draws no dim of its own.
    let dimsUnder: Bool
    /// Sheet content respects the bottom inset, which the column's ignored safe area no longer gives it.
    let insetsBottom: Bool
    let onDismiss: () -> Void

    /// Whether the last layout drew a column; read by the modifiers outside the reader.
    @State private var isColumn = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var deviceInsets = EdgeInsets()

    func body(content: Content) -> some View {
        // A reader's size is what it is offered, never its content's, so content that overflows cannot feed the measurement.
        GeometryReader { proxy in
            // The window, read in this same pass so no layout runs on a stale frame during a rotation. Not the
            // presentation's own size: a sheet at a partial detent is wider than it is tall in portrait too.
            let window = PresentationWindow.window?.bounds.size ?? CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            let base = SheetFrame.make(window: window, isFullScreen: isFullScreen, compactHeight: verticalSizeClass == .compact)
            let size = base.columnSize(window: window, fullHeight: isFullScreen, inset: floating.map { $0.inset ?? 0 })
            let frame = Self.frame(base, columnSize: size, floating: floating)
            let column = frame.isColumn
            let safeArea = SheetFrame.columnSafeArea(deviceInsets, scale: frame.contentScale)
            let bottomAligned = Self.isBottomAligned(isFullScreen: isFullScreen, floating: floating)
            // Offer impressions count only what is inside the column, not the dimmed area beside it.
            let visible = size.map { Self.columnRect(size: $0, in: proxy.frame(in: .global), bottomAligned: bottomAligned) }
            ZStack(alignment: column && bottomAligned ? .bottom : .center) {
                // Where `LandscapeColumnDim` can show through, it dims instead, so the dim does not slide in with the sheet.
                Color.black.opacity(column && !dimsUnder ? SheetFrame.dimOpacity(floating) : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .allowsHitTesting(column)
                    .accessibilityHidden(true)
                content
                    .padding(.bottom, column && insetsBottom ? safeArea.bottom : 0)
                    .environment(\.sduiSafeAreaOverride, column ? safeArea : nil)
                    .environment(\.sduiVerticalSpacing, frame.verticalSpacingScale)
                    .environment(\.visibilityBounds, visible)
                    // Laid out at size / scale, then drawn at scale, so every point and font shrinks together.
                    .frame(width: size.map { $0.width / frame.contentScale }, height: size.map { $0.height / frame.contentScale })
                    .scaleEffect(frame.contentScale)
                    .frame(width: size?.width, height: size?.height)
                    .background(column ? background : .clear)
                    .clipShape(Self.clip(isColumn: column, isFullScreen: isFullScreen, cornerRadius: cornerRadius, floating: floating))
                    // Taps on the column's own empty space stay off the dimmed area.
                    .contentShape(Rectangle())
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: column, initial: true) { _, column in
                isColumn = column
                let insets = PresentationWindow.window?.safeAreaInsets ?? .zero
                deviceInsets = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
            }
        }
        .ignoresSafeArea(edges: isColumn ? .all : [])
        .statusBarHidden(isColumn)
        .modifier(SheetPresentationBackground(portrait: presentationBackground, isColumn: isColumn, isSheet: !isFullScreen))
    }

    /// A floating column draws at its own height, so its content fits it; others keep the window's scale.
    static func frame(_ base: SheetFrame, columnSize: CGSize?, floating: SDUILandscapeColumn?) -> SheetFrame {
        guard floating != nil, let columnSize else { return base }
        return base.scaled(toColumnHeight: columnSize.height)
    }

    /// A floating column is centred; otherwise a sheet column sits at the bottom.
    static func isBottomAligned(isFullScreen: Bool, floating: SDUILandscapeColumn?) -> Bool {
        !isFullScreen && floating == nil
    }

    /// A floating column rounds all four corners; otherwise only a sheet column's top. Portrait clips nothing.
    static func clip(isColumn: Bool, isFullScreen: Bool, cornerRadius: CGFloat, floating: SDUILandscapeColumn?) -> SheetColumnClip {
        guard isColumn else { return SheetColumnClip(top: nil, bottom: 0) }
        if let floating {
            let radius = max(floating.cornerRadius ?? 0, 0)
            return SheetColumnClip(top: radius, bottom: radius)
        }
        return SheetColumnClip(top: isFullScreen ? 0 : cornerRadius, bottom: 0)
    }

    /// Where the stack places a column of `size`: centred across, and centred or at the bottom down.
    static func columnRect(size: CGSize, in container: CGRect, bottomAligned: Bool) -> CGRect {
        let y = bottomAligned ? container.maxY - size.height : container.midY - size.height / 2
        return CGRect(x: container.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }
}

/// Clear behind a column, so the app shows through. Without a portrait colour the system background stays.
@available(iOS 17.0, *)
struct SheetPresentationBackground: ViewModifier {
    let portrait: Color?
    let isColumn: Bool
    let isSheet: Bool

    func body(content: Content) -> some View {
        if !Self.usesPresentationBackground(isSheet: isSheet, isIOS18OrLater: Self.isIOS18OrLater) {
            content.background { if let portrait, !isColumn { portrait.ignoresSafeArea() } }
        } else if let portrait {
            content.presentationBackground(isColumn ? .clear : portrait)
        } else {
            content.background { if isColumn { Color.clear.presentationBackground(.clear) } }
        }
    }

    /// iOS 17 can loop a sheet's present forever when it sets a presentation background, so on iOS 17 a sheet draws its own.
    static func usesPresentationBackground(isSheet: Bool, isIOS18OrLater: Bool) -> Bool {
        !isSheet || isIOS18OrLater
    }

    private static var isIOS18OrLater: Bool {
        if #available(iOS 18.0, *) { return true } else { return false }
    }
}

/// Rounds a column's corners. With no top radius it clips nothing, so portrait content can still bleed.
@available(iOS 17.0, *)
struct SheetColumnClip: Shape, Equatable {
    let top: CGFloat?
    let bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let top else { return Path(rect.insetBy(dx: -1e5, dy: -1e5)) }
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top
        ).path(in: rect)
    }
}

/// Dims the app behind a landscape column. It sits under the presentation, so it is dark from the first frame instead
/// of sliding in with the sheet. A close removes the window at once, so the dim goes in the same frame as the column;
/// only a system swipe dismiss runs the fade. Android fades over its slide out; the difference is intended.
@available(iOS 17.0, *)
struct LandscapeColumnDim: View {
    let isFullScreen: Bool
    let isPresented: Bool
    let floating: SDUILandscapeColumn?
    /// From the coordinator's presentation target, not read from `PresentationWindow` at render.
    let hasOverlayWindow: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Only our own overlay window shows through a cover. An iOS 17 sheet stays opaque, and a publisher's own
    /// controller dims only itself, so there the column keeps its dim inside.
    static func drawsUnder(isFullScreen: Bool, hasOverlayWindow: Bool) -> Bool {
        guard hasOverlayWindow else { return false }
        if isFullScreen { return true }
        if #available(iOS 18.0, *) { return true }
        return false
    }

    var body: some View {
        GeometryReader { proxy in
            let window = PresentationWindow.window?.bounds.size ?? proxy.size
            let column = SheetFrame.make(window: window, isFullScreen: isFullScreen, compactHeight: verticalSizeClass == .compact).isColumn
            Color.black
                .opacity(column && isPresented && Self.drawsUnder(isFullScreen: isFullScreen, hasOverlayWindow: hasOverlayWindow) ? SheetFrame.dimOpacity(floating) : 0)
                .animation(.easeOut(duration: 0.25), value: isPresented)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
