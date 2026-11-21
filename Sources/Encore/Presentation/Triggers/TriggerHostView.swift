// Binds a host model to its plug-in's view: loads on appear, on every foreground and on
// identity changes, and reports visibility for the impression. Also the type-erased handle the
// public views and the registry pass around.

import SwiftUI
import UIKit
import Combine

// MARK: - Handle

/// One mounted trigger, erased over its plug-in.
@MainActor
internal protocol TriggerHosting: AnyObject {
    /// The height the host takes: the plug-in's height while it shows, 0 otherwise.
    var heightPublisher: AnyPublisher<CGFloat, Never> { get }
    /// The shown look's own cap (its root's maxWidth); nil fills the container.
    var maxWidthPublisher: AnyPublisher<CGFloat?, Never> { get }
    /// Height and cap together.
    var sizePublisher: AnyPublisher<TriggerSize, Never> { get }
    func makeView() -> AnyView
    /// Restyles the mounted trigger in place; the gate does not run again.
    func setAppearance(_ appearance: AppearanceConfig?)
    /// The mount's publisher values (`${values.K}`): redraws in place, never refetches. They stay on
    /// the phone: no request, event, log, cache or store ever holds one.
    func setValues(_ values: [String: String])
    /// The app's slot text (headline, subheadline, CTA): redraws in place, never refetches, never sent.
    func setTexts(_ texts: [TriggerTextSlot: String])
    /// Passed to every sheet the trigger opens.
    var publisherReward: PublisherReward? { get set }
    /// The app's copy for every sheet the trigger opens.
    var sheetText: TriggerSheetText { get set }
    /// Each opened sheet's result, once, after it closes.
    var onResult: ((PresentationResult) -> Void)? { get set }
    /// The view went away: stop work in flight (a pop waiting behind another sheet).
    func stop()
    /// What a slot reads: whether the host has answered, and its height.
    var slotStatePublisher: AnyPublisher<TriggerSlotState, Never> { get }
    /// Hidden inside a slot: no impression, no auto pop, no not-shown report.
    var suppressed: Bool { get set }
    /// Loads again, e.g. after a claim.
    func reload()
    /// The app's GiftsButton host state: redraws in place, never refetches; events carry its status only.
    func setHostState(_ state: GiftsButtonHostState?)
    /// Whether a look is drawn, once the host has answered for a user; only on change.
    var showingPublisher: AnyPublisher<Bool, Never> { get }
    /// The app's moment. With earliest-point serving on, a change serves again, debounced.
    func setMoment(_ moment: Moment?)
}

extension TriggerHosting {
    func setMoment(_ moment: Moment?) {}
}

/// What a host takes: its height, its look's cap (nil fills the container), and its aspect ratio
/// (nil keeps the fixed height; set, the height follows the width, ``TriggerAspect``).
internal struct TriggerSize: Equatable {
    var height: CGFloat
    var maxWidth: CGFloat?
    var aspectRatio: CGFloat? = nil

    /// The height drawn at `width`: the fixed height, or for an aspect look its width's height
    /// once a width is known (nothing drawn stays 0).
    func drawnHeight(width: CGFloat?) -> CGFloat {
        guard height > 0, let aspectRatio, let width, width > 0 else { return height }
        return TriggerAspect.height(width: width, maxWidth: maxWidth, ratio: aspectRatio)
    }
}

extension TriggerHosting {
    /// A host that draws no look of its own has no cap.
    var maxWidthPublisher: AnyPublisher<CGFloat?, Never> { Just(nil).eraseToAnyPublisher() }

    /// Height and cap together, so a view sizes itself once per change.
    var sizePublisher: AnyPublisher<TriggerSize, Never> {
        Publishers.CombineLatest(heightPublisher, maxWidthPublisher)
            .map { TriggerSize(height: $0, maxWidth: $1) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Only GiftsButton draws a host state.
    func setHostState(_ state: GiftsButtonHostState?) {}

    /// Once answered, whether it draws anything.
    var showingPublisher: AnyPublisher<Bool, Never> {
        slotStatePublisher.filter(\.answered).map { $0.height > 0 }.removeDuplicates().eraseToAnyPublisher()
    }
}

extension TriggerHostModel: TriggerHosting {
    var heightPublisher: AnyPublisher<CGFloat, Never> {
        $shown.map { $0?.presentation.slotHeight ?? 0 }.removeDuplicates().eraseToAnyPublisher()
    }

    var maxWidthPublisher: AnyPublisher<CGFloat?, Never> {
        $shown.map { $0?.presentation.maxWidth }.removeDuplicates().eraseToAnyPublisher()
    }

    var sizePublisher: AnyPublisher<TriggerSize, Never> {
        $shown.map { TriggerSize(height: $0?.presentation.slotHeight ?? 0, maxWidth: $0?.presentation.maxWidth, aspectRatio: $0?.presentation.aspectRatio) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// No answer before the host has a user (`configure()`), so an app keeps its own view until then.
    /// A presented look counts as drawn: an app that hides the slot on false would hide what is measured.
    var showingPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest($answeredForUser, $shown.map { ($0?.presentation.slotHeight ?? 0) > 0 || $0?.presentation.presented != nil })
            .filter { $0.0 }
            .map { $0.1 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var slotStatePublisher: AnyPublisher<TriggerSlotState, Never> {
        Publishers.CombineLatest($answered, $shown.map { $0?.presentation.slotHeight ?? 0 })
            .map { TriggerSlotState(answered: $0, height: $1) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func reload() {
        Task { [weak self] in await self?.refresh() }
    }

    func makeView() -> AnyView {
        AnyView(TriggerHostView(model: self))
    }
}

// MARK: - View

@MainActor
internal struct TriggerHostView<Plugin: TriggerPlugin>: View {
    /// Appearance lives on the model, set by the public view that owns it.
    @ObservedObject var model: TriggerHostModel<Plugin>

    @State private var onScreen = false
    @Environment(\.layoutDirection) private var appDirection

    var body: some View {
        // The zero-height spacer keeps `.task` alive while nothing shows.
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if let shown = model.shown, shown.presentation.presented != nil {
                // A presented look takes no height: only the slot's line is measured, for when it is seen.
                Color.clear.frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            TriggerVisibilityProbe(frame: proxy.frame(in: .global), report: report(fraction:covered:), measuresLine: true) { probe in
                                model.visibilityCheck = { [weak probe] in probe.map(TriggerVisibility.isSeen) ?? false }
                            }
                        }
                    )
                    .onDisappear { report(fraction: 0, covered: false) }
            } else if let shown = model.shown {
                model.plugin.render(shown.presentation.model, scope: TriggerRenderScope(
                    onScreen: onScreen,
                    busy: model.isActing,
                    hint: model.isHinting,
                    tapped: { target in Task { await model.tap(target) } },
                    dismissed: { model.dismiss() }
                ))
                // The entrance plays once per drawn content; a same-content refresh keeps the clock.
                .environment(\.sduiTriggerMotion, model.motionClocks.motion(for: TriggerHostModel<Plugin>.motionKey(shown)))
                // An aspect look fills the mount, which sizes it from its width.
                .frame(height: shown.presentation.aspectRatio == nil ? shown.presentation.height : nil)
                .frame(maxHeight: shown.presentation.aspectRatio == nil ? nil : .infinity)
                .modifier(ServedLayoutDirectionModifier(locale: shown.variant.locale))
                // The app's direction, kept for placing the look: leading is the app's leading,
                // whatever language the look is in.
                .environment(\.encoreTriggerAppDirection, appDirection)
                .background(
                    GeometryReader { proxy in
                        // The frame is only a trigger: a move makes the probe measure again.
                        TriggerVisibilityProbe(frame: proxy.frame(in: .global), report: report(fraction:covered:)) { probe in
                            model.visibilityCheck = { [weak probe] in probe.map(TriggerVisibility.isSeen) ?? false }
                        }
                    }
                )
                .onDisappear { report(fraction: 0, covered: false) }
            } else if model.awaitsHoldoutExposure {
                // A holdout is exposed when the slot's line is seen for the dwell, as an impression would be.
                Color.clear.frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            TriggerVisibilityProbe(frame: proxy.frame(in: .global), report: report(fraction:covered:), measuresLine: true) { probe in
                                model.visibilityCheck = { [weak probe] in probe.map(TriggerVisibility.isSeen) ?? false }
                            }
                        }
                    )
                    .onDisappear { report(fraction: 0, covered: false) }
            }
        }
        .task {
            model.start()
            await model.refresh()
        }
        .onDisappear { model.stop() }
        // A stopped host (its view gone, e.g. under a pushed screen) ignores these until it appears again.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.notifiedRefresh()
        }
        // A trigger mounted before `configure()` had no user to load for.
        .onReceive(NotificationCenter.default.publisher(for: .encoreDidConfigure)) { _ in
            model.notifiedRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .encoreOfferTargetingDidChange)) { _ in
            model.heldOffersChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .encoreTriggerHeldOffersChanged)) { _ in
            model.heldOffersChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .encoreIdentityDidChange)) { _ in
            model.userChanged()
            model.notifiedRefresh()
        }
    }

    /// `covered`: an Encore sheet (or another modal) is over it, so its motion pauses; the
    /// impression dwell keeps its own cover check.
    private func report(fraction: Double, covered: Bool) {
        onScreen = fraction > 0 && !covered
        model.visibilityChanged(fraction >= 0.5)
    }
}

/// Measures how much of the trigger the user can see. Sits behind it as a plain UIView so
/// it can walk the real view tree: SwiftUI's frame alone misses every ancestor that clips.
internal struct TriggerVisibilityProbe: UIViewRepresentable {
    let frame: CGRect
    let report: (Double, Bool) -> Void
    /// A slot with no height (a presented look's): measured as a line across it.
    var measuresLine = false
    /// Hands the probe to the model, which measures again when the dwell ends.
    let attach: (TriggerVisibilityProbeView) -> Void

    func makeUIView(context: Context) -> TriggerVisibilityProbeView {
        let view = TriggerVisibilityProbeView()
        view.measuresLine = measuresLine
        view.onChange = report
        attach(view)
        return view
    }

    func updateUIView(_ view: TriggerVisibilityProbeView, context: Context) {
        view.onChange = report
        view.setNeedsMeasure()
    }
}

/// Measures again when SwiftUI moves it (scrolling included, UIKit scroll views too), when it
/// joins or leaves a window, when an Encore sheet shows or closes, and when the app returns to
/// the foreground. Reports 0 in the background.
internal final class TriggerVisibilityProbeView: UIView {
    /// The share in view, and whether a sheet or another modal is over it.
    var onChange: ((Double, Bool) -> Void)?
    /// Measured as a one-point line across its top: a slot with no height is seen when its line is.
    var measuresLine = false
    /// Also measures again when an enclosing UIKit scroll view scrolls: a probe bound to a plain
    /// UIView gets no SwiftUI moves.
    var followsScrollViews = false {
        didSet { observeScrollViews() }
    }
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var scrollObservations: [NSKeyValueObservation] = []
    private var measurePending = false
    /// Seeded from the app's state: a probe made while the app is in the background reports nothing.
    private var inBackground = UIApplication.shared.applicationState == .background

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(true) }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(false) }
            },
            center.addObserver(forName: .encoreSheetShowingDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsMeasure() }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observeScrollViews()
        setNeedsMeasure()
    }

    private func observeScrollViews() {
        scrollObservations = []
        guard followsScrollViews, window != nil else { return }
        var node = superview
        while let current = node {
            if let scroll = current as? UIScrollView {
                scrollObservations.append(scroll.observe(\.contentOffset) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.setNeedsMeasure() }
                })
            }
            node = current.superview
        }
    }

    /// Measures once on the next main-queue turn: layout has settled, and no report lands
    /// inside a SwiftUI update.
    func setNeedsMeasure() {
        guard !measurePending else { return }
        measurePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurePending = false
            self.onChange?(self.inBackground ? 0 : TriggerVisibility.visibleFraction(of: self), TriggerCoverage.isCovered(self))
        }
    }

    private func setInBackground(_ value: Bool) {
        inBackground = value
        setNeedsMeasure()
    }
}

internal enum TriggerVisibility {
    /// Whether the user sees it now: at least half in view and not covered by a sheet.
    @MainActor
    static func isSeen(_ view: UIView) -> Bool {
        visibleFraction(of: view) >= 0.5 && !TriggerCoverage.isCovered(view)
    }

    /// Share of `view` in view, 0...1: its frame clipped by the window and by every ancestor
    /// that clips to its bounds (scroll views, clipped containers). Geometry only: a cover is
    /// checked apart, so a trigger under a modal keeps waiting for it to go. A view outside a
    /// window or under a hidden ancestor is not in view.
    @MainActor
    static func visibleFraction(of view: UIView) -> Double {
        guard let window = view.window, !window.isHidden else { return 0 }
        var frame = view.convert(view.bounds, to: window)
        if (view as? TriggerVisibilityProbeView)?.measuresLine == true, frame.height < 1 { frame.size.height = 1 }
        var visible = frame.intersection(window.bounds)
        var current: UIView? = view
        guard window.alpha > 0.01 else { return 0 }
        // The share the embedding framework can see (a bridge's clipping and covers).
        var hostShare = 1.0
        while let node = current, node !== window {
            // Hidden or fully transparent (the view itself or any ancestor): nothing to see.
            if node.isHidden || node.alpha <= 0.01 || node.layer.opacity <= 0.01 { return 0 }
            if let trigger = node as? EncoreTriggerView { hostShare = combined(hostShare, host: trigger.hostVisibleFraction) }
            if node !== view, node.clipsToBounds {
                visible = visible.intersection(node.convert(node.bounds, to: window))
            }
            current = node.superview
        }
        return combined(visibleFraction(of: frame, in: visible.isNull ? .zero : visible), host: hostShare)
    }

    /// `native` times the share a bridge's framework can see, clamped to 0...1. A host share
    /// that is not a finite number counts as 1 (no override).
    static func combined(_ native: Double, host: Double) -> Double {
        let share = host.isFinite ? min(max(host, 0), 1) : 1
        return min(max(native * share, 0), 1)
    }

    /// Share of `frame` inside `bounds`, 0...1.
    static func visibleFraction(of frame: CGRect, in bounds: CGRect) -> Double {
        guard frame.width > 0, frame.height > 0 else { return 0 }
        let visible = frame.intersection(bounds)
        guard !visible.isNull else { return 0 }
        return Double((visible.width * visible.height) / (frame.width * frame.height))
    }
}

/// Whether something the SDK can detect covers a trigger: an Encore sheet on screen, or a
/// controller presented above the one holding the trigger.
@MainActor
internal enum TriggerCoverage {
    /// Whether an Encore sheet is on screen. Replaceable in tests.
    static var sheetShowing: @MainActor () -> Bool = { OfferSheetCoordinator.showingPresentationId != nil }

    static func isCovered(_ view: UIView) -> Bool {
        if sheetShowing() { return true }
        guard let root = view.window?.rootViewController else { return false }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top !== root && !view.isDescendant(of: top.view)
    }
}
