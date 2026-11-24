//
//  View+Visible.swift
//  Encore
//
//  Generic SwiftUI primitive that fires a closure whenever a view occupies
//  at least a configurable fraction of its own area within the active
//  window's bounds. Used today for offer impression tracking on the
//  loaded primary creative; intentionally domain-free so other features
//  (exposure events, viewport-driven prefetch, A/B variant exposure
//  signals) can reach for it without coupling to ads.
//

import SwiftUI
import UIKit

extension View {
    /// Invokes `action` whenever this view occupies at least `threshold`
    /// of its own area within the active window's bounds.
    ///
    /// Stateless — `action` may fire multiple times as scroll, rotation,
    /// or layout transitions cause the frame to change while the
    /// threshold remains satisfied. Callers that need "fire exactly
    /// once" semantics must dedupe at a level whose lifetime outlasts
    /// the view itself: SwiftUI may recycle (LazyVStack), recreate
    /// (conditional branches), or rebuild the underlying view, resetting
    /// any modifier `@State`. The dedup ledger belongs higher up the tree.
    ///
    /// `threshold` is a fraction of the view's own area, not the screen.
    /// `0.5` ≈ IAB Viewable Impression definition (≥ 50% on screen).
    /// `0` means "any pixel intersects." Defaults to `0.5`.
    ///
    /// Uses the active window's bounds (not `UIScreen.main.bounds`), so
    /// iPad multi-scene / Stage Manager / Slide Over presentations
    /// report visibility against the host app's actual window, not the
    /// physical screen.
    func onVisible(
        threshold: Double = 0.5,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(VisibilityProbe(threshold: threshold, action: action))
    }
}

private struct VisibilityProbe: ViewModifier {
    let threshold: Double
    let action: () -> Void
    @Environment(\.visibilityProbesPaused) private var paused
    @Environment(\.visibilityBounds) private var visibleBounds
    /// The newest bounds: a change handler runs with the previous render's copy of this modifier.
    @State private var latestBounds = LatestBounds()

    func body(content: Content) -> some View {
        latestBounds.value = visibleBounds
        latestBounds.paused = paused
        return content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { evaluate(frame: proxy.frame(in: .global), paused: latestBounds.paused) }
                    .onChange(of: visibleBounds) { _ in evaluate(frame: proxy.frame(in: .global), paused: latestBounds.paused) }
                    .onChange(of: proxy.frame(in: .global)) { frame in
                        // Single-argument `onChange` (iOS 14+) — keeps the
                        // primitive available below iOS 17. The two-argument
                        // (`old, new`) form would gate the whole API.
                        // The newest pause too: a frame that moves in the update that pauses must not count.
                        evaluate(frame: frame, paused: latestBounds.paused)
                    }
                    // The frame does not move when a cover lifts, so check again then.
                    // Use the new value: the closure can still see the old one.
                    .onChange(of: paused) { isPaused in evaluate(frame: proxy.frame(in: .global), paused: isPaused) }
            }
        )
    }

    private func evaluate(frame: CGRect, paused: Bool) {
        guard !paused,
              VisibilityGeometry.isVisible(frame, window: VisibilityGeometry.activeWindowBounds, bounds: latestBounds.value, threshold: threshold)
        else { return }
        action()
    }
}

/// The probe's area rule, pure so it can be tested without a window.
enum VisibilityGeometry {
    /// True when at least `threshold` of `frame` lies inside the window and inside `bounds`, when a host sets one.
    static func isVisible(_ frame: CGRect, window: CGRect, bounds: CGRect?, threshold: Double) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let intersection = frame.intersection(window.intersection(bounds ?? .infinite))
        return Double(intersection.width * intersection.height / (frame.width * frame.height)) >= threshold
    }

    /// True when any of `frame` is inside the window and `bounds`; a box with no area counts by its centre.
    static func intersects(_ frame: CGRect, window: CGRect, bounds: CGRect?) -> Bool {
        let visible = window.intersection(bounds ?? .infinite)
        guard frame.width > 0, frame.height > 0 else { return visible.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        let intersection = frame.intersection(visible)
        return !intersection.isNull && intersection.width > 0 && intersection.height > 0
    }

    /// The foreground scene's key window, not `UIScreen.main`, so an iPad split view reports its own bounds.
    @MainActor static var activeWindowBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow?.bounds ?? UIScreen.main.bounds
    }
}

// MARK: - Paused probes

private struct VisibilityProbesPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while something opaque covers these views (a full-screen cover).
    /// Probes stay quiet, then check again once it clears.
    var visibilityProbesPaused: Bool {
        get { self[VisibilityProbesPausedKey.self] }
        set { self[VisibilityProbesPausedKey.self] = newValue }
    }

    /// The global rect the user can see when a host draws its content in less than the window, such as a landscape column.
    var visibilityBounds: CGRect? {
        get { self[VisibilityBoundsKey.self] }
        set { self[VisibilityBoundsKey.self] = newValue }
    }
}

private final class LatestBounds {
    var value: CGRect?
    var paused = false
}

private struct VisibilityBoundsKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

// MARK: - Optional Visibility Bridge

/// Conditionally applies `View.onVisible` only when an action is provided.
/// Skips wiring up `GeometryReader` / `onChange` instrumentation entirely
/// when the caller doesn't ask to be notified.
struct OptionallyOnVisible: ViewModifier {
    let action: (() -> Void)?
    /// `action` may only be nil for a reason that is constant for the life of
    /// the view: this branch IS an identity change, and flipping it rebuilds
    /// everything beneath.

    func body(content: Content) -> some View {
        if let action {
            content.onVisible(perform: action)
        } else {
            content
        }
    }
}
