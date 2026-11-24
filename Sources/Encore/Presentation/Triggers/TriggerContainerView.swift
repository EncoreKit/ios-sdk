// The SDK's container for a presented trigger look (vocab §2.11): a centred popup, a half sheet or a
// full-screen cover, each with a close button, an ad label and VoiceOver held inside. The look itself
// is drawn by the trigger's own renderer, exactly as in its slot.

import SwiftUI
import UIKit

/// The container's chrome: its corner radius from the mount's ``AppearanceConfig``, its surface from the
/// look it holds (as the slot draws the look's root), the app's own only when the look sets no background.
internal struct TriggerContainerChrome: Equatable {
    /// A card (or cover) colour and the ad label and close glyph colour on it. A nil colour is the
    /// system's; a nil ink the system's secondary label, which follows dark mode.
    struct Surface: Equatable {
        var color: AppearanceHex.RGBA?
        var ink: AppearanceHex.RGBA?

        /// The app's own: `surfaceColor`, else `backgroundColor`; on it `textColor`, else black or white for it.
        init(appearance: AppearanceConfig?) {
            color = (appearance?.surfaceColor).flatMap(AppearanceHex.parse) ?? (appearance?.backgroundColor).flatMap(AppearanceHex.parse)
            // An adaptive label could vanish on a fixed surface, and a fixed ink on the adaptive one (as on the
            // sheet, a text colour applies only with a background of the app's own).
            ink = color.map { color in (appearance?.textColor).flatMap(AppearanceHex.parse) ?? color.contrastingInk }
        }

        /// The look's resolved background and text when its palette sets a background; else `app`.
        init(theme: TriggerTheme, app: Surface) {
            guard theme.lookBackground != nil else { self = app; return }
            color = theme.background
            ink = theme.text
        }
    }

    /// The card's corners; the look's own `cornerRadius` setting, else 24.
    var cornerRadius: CGFloat = 24
    /// The surface for the look's palette (its `colors`, or `lightColors` under a light scheme).
    var surface: Surface
    /// The surface for a light device when the look's palette follows the device (`system`); nil keeps ``surface``.
    var lightSurface: Surface?

    init(appearance: AppearanceConfig?, themes: TriggerThemes? = nil) {
        if let radius = appearance?.cornerRadius, radius.isFinite, TriggerVocabulary.cornerRadiusRange.contains(Double(radius)) {
            cornerRadius = radius
        }
        let app = Surface(appearance: appearance)
        surface = themes.map { Surface(theme: $0.primary, app: app) } ?? app
        lightSurface = themes?.light.map { Surface(theme: $0, app: app) }
    }

    /// What the view draws: ``lightSurface`` on a light device when the look follows it, else ``surface``.
    func surface(for scheme: ColorScheme) -> Surface {
        scheme == .light ? lightSurface ?? surface : surface
    }

    /// The smallest the close button's tap area may be (Apple's 44 pt).
    static let closeSize: CGFloat = 44
    /// The widest a popup or half-sheet card draws (an iPad keeps it phone-sized).
    static let maxCardWidth: CGFloat = 440
    /// How far a half sheet must be pulled down (or flicked) to close.
    static let swipeToClose: CGFloat = 110
}

@available(iOS 17.0, *)
internal struct TriggerContainerView<Look: View>: View {
    let mode: TriggerPresentationMode
    let chrome: TriggerContainerChrome
    /// The look's own height; it scrolls inside a container with less room than that.
    let lookHeight: CGFloat
    /// Closes it (the X, a swipe, the escape gesture), after its exit animation.
    let onClose: () -> Void
    @ViewBuilder let look: () -> Look

    /// The copy as it was when the container was built.
    private let adLabel = SDKStrings.current[.presentedAdLabel]
    private let closeLabel = SDKStrings.current[.presentedClose]

    @State private var shown = false
    @State private var drag: CGFloat = 0
    @State private var closing = false
    @State private var bottomInset: CGFloat = 0
    /// The container's height and its header's, for the room the look has.
    @State private var height: CGFloat = .infinity
    @State private var headerHeight: CGFloat = 50
    @AccessibilityFocusState private var labelFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .footnote) private var glyphCircle: CGFloat = 30

    var body: some View {
        // The screen's own size (inside its safe areas), whatever the look asks for: the room the look has.
        GeometryReader { proxy in
            ZStack(alignment: mode == .halfSheet ? .bottom : .center) {
                if mode != .fullScreen {
                    Color.black.opacity(shown ? 0.45 : 0)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
                container
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // A half sheet runs to the screen's bottom edge; its padding keeps the look above the home indicator.
            .ignoresSafeArea(.container, edges: mode == .halfSheet ? .bottom : [])
            .onAppear { (bottomInset, height) = (proxy.safeAreaInsets.bottom, proxy.size.height) }
            .onChange(of: proxy.safeAreaInsets.bottom) { _, inset in bottomInset = inset }
            .onChange(of: proxy.size.height) { _, next in height = next }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86), value: shown)
        .onAppear {
            shown = true
            labelFocused = true
        }
    }

    /// The look, scrolled when it is taller than the room it has (a phone in landscape), so the
    /// header and its close button stay on screen.
    private var fitted: some View {
        ScrollView(.vertical) { look() }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: max(min(lookHeight, room), 1))
    }

    /// The height left for the look once the header and the mode's own spacing are drawn.
    private var room: CGFloat {
        let spacing: CGFloat
        switch mode {
        // Its margins, the bottom padding and a little slack so the card's corners stay on screen.
        case .popup: spacing = 24 + 16 + 16
        // The bottom inset is outside the measured height; only padding past it costs room.
        case .halfSheet: spacing = 12 + 13 + 8 + max(12 - bottomInset, 0)
        case .fullScreen: spacing = 16
        }
        return height - headerHeight - spacing
    }

    @ViewBuilder
    private var container: some View {
        switch mode {
        case .popup:
            card(grabber: false)
                .frame(maxWidth: TriggerContainerChrome.maxCardWidth)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
        case .halfSheet:
            card(grabber: true)
                .frame(maxWidth: TriggerContainerChrome.maxCardWidth)
                .padding(.top, 12)
                .offset(y: shown || reduceMotion ? max(drag, 0) : 600)
                .opacity(reduceMotion && !shown ? 0 : 1)
                .gesture(swipeDown)
        case .fullScreen:
            cover
                .opacity(shown ? 1 : 0)
        }
    }

    private func card(grabber: Bool) -> some View {
        VStack(spacing: 0) {
            if grabber {
                Capsule()
                    .fill(Color(uiColor: .tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            header
            fitted
                .padding(.horizontal, 16)
                .padding(.bottom, grabber ? 8 : 16)
        }
        .padding(.bottom, grabber ? max(bottomInset, 12) : 0)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: chrome.cornerRadius, bottomLeadingRadius: grabber ? 0 : chrome.cornerRadius,
                bottomTrailingRadius: grabber ? 0 : chrome.cornerRadius, topTrailingRadius: chrome.cornerRadius, style: .continuous
            )
            .fill(surface)
            // On the card's shape only, so its text casts none.
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        )
        .modalContainer(onEscape: close)
    }

    private var cover: some View {
        ZStack {
            (chrome.surface(for: colorScheme).color.map(\.color) ?? Color(uiColor: .systemBackground)).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                fitted
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modalContainer(onEscape: close)
    }

    /// The ad label at the leading edge, the close button at the trailing one.
    private var header: some View {
        HStack(alignment: .center) {
            Text(adLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityFocused($labelFocused)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ink)
                    .frame(width: glyphCircle, height: glyphCircle)
                    .background(Circle().fill(ink.opacity(0.12)))
                    .frame(minWidth: TriggerContainerChrome.closeSize, minHeight: TriggerContainerChrome.closeSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
            .accessibilityIdentifier("encore.trigger.container.close")
        }
        // The header grows with the text size, within bounds.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.top, mode == .halfSheet ? 0 : 6)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { headerHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, next in headerHeight = next }
        })
    }

    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = max($0.translation.height, 0) }
            .onEnded { value in
                if value.translation.height > TriggerContainerChrome.swipeToClose || value.predictedEndTranslation.height > 2 * TriggerContainerChrome.swipeToClose {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
                }
            }
    }

    /// A card's colour; the system's, in dark mode, stands off the dim as a sheet does.
    private var surface: Color { chrome.surface(for: colorScheme).color.map(\.color) ?? Color(uiColor: .secondarySystemGroupedBackground) }
    private var ink: Color { chrome.surface(for: colorScheme).ink.map(\.color) ?? Color(uiColor: .secondaryLabel) }

    /// Animates out, then hands the close to the host once.
    private func close() {
        guard !closing else { return }
        closing = true
        shown = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            onClose()
        }
    }
}

@available(iOS 17.0, *)
private extension View {
    /// VoiceOver stays inside the container, and the escape gesture closes it.
    func modalContainer(onEscape: @escaping () -> Void) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onEscape)
    }
}

/// A host's presented look in its container, drawn by the trigger's own renderer and tapped through the host.
@available(iOS 17.0, *)
internal struct TriggerPresentedLook<Plugin: TriggerPlugin>: View {
    @ObservedObject var model: TriggerHostModel<Plugin>
    let mode: TriggerPresentationMode
    /// The look as it was presented: the container keeps drawing it while the slot moves on.
    @State private var kept: TriggerHostModel<Plugin>.Shown?

    var body: some View {
        TriggerContainerView(
            mode: mode, chrome: TriggerContainerChrome(appearance: model.appearance, themes: (kept ?? model.containerShown ?? model.shown)?.presentation.themes),
            lookHeight: (kept ?? model.containerShown ?? model.shown)?.presentation.height ?? 0, onClose: { model.containerDismissed() }
        ) {
            if let shown = kept ?? model.containerShown ?? model.shown {
                model.plugin.render(shown.presentation.model, scope: TriggerRenderScope(
                    onScreen: true,
                    busy: model.isActing,
                    hint: model.isHinting,
                    tapped: { model.containerTapped($0) },
                    dismissed: { model.containerDismissed() }
                ))
                .frame(height: shown.presentation.height)
                .frame(maxWidth: shown.presentation.maxWidth ?? .infinity)
                .modifier(ServedLayoutDirectionModifier(locale: shown.variant.locale))
                .environment(\.sduiTriggerMotion, model.motionClocks.motion(for: TriggerHostModel<Plugin>.motionKey(shown)))
            }
        }
        .onAppear { if kept == nil { kept = model.containerShown ?? model.shown } }
    }
}
