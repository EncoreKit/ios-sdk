// Presentation/Utils/Window/PresentationWindow.swift
//
// UIWindow utilities for presentation management.
// Encapsulates UIKit bridging for SwiftUI overlay presentation.
//

import UIKit
import SwiftUI

/// Manages presentation windows and view controller discovery.
///
/// This is the SDK's UIKit escape hatch for "present above everything" semantics.
/// SwiftUI views are hosted in a custom `UIWindow` at the highest window level.
///
/// Thread Safety: All operations are `@MainActor` isolated.
internal extension OfferContext.AppearanceMode {
    /// `.unspecified` for `auto` so the sheet inherits the HOST app rather than
    /// the device — a light-only publisher should not get a dark sheet.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        case .auto:  return .unspecified
        }
    }
}

@MainActor
internal enum PresentationWindow {
    
    // MARK: - Window State
    
    /// The custom window used for presenting offer sheets.
    private(set) static var window: UIWindow?
    
    /// The hosting controller for the presented SwiftUI view.
    private static var hostingController: UIViewController?
    
    /// Called when the window is dismissed (cleanup, swipe-away, etc.)
    private static var onDismissHandler: (() -> Void)?
    
    /// Whether an offer sheet is currently presented.
    static var isPresented: Bool { window != nil }
    
    // MARK: - Present SwiftUI View
    
    /// Presents a SwiftUI view in a transparent overlay `UIWindow` above all other content.
    /// Returns the created window on success, nil when no window scene is available.
    /// `overrideUserInterfaceStyle` forces the sheet's appearance; `.unspecified` (the
    /// default) inherits the host app, which is what `auto` means.
    /// `onDismiss` fires when the window is cleaned up (dismissal, system removal, etc).
    @discardableResult
    static func present<Content: View>(
        _ rootView: Content,
        overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified,
        _ onDismiss: (() -> Void)? = nil
    ) -> UIWindow? {
        // Auto-clean stale window instead of bailing — prevents stuck states
        if window != nil {
            Logger.warn(.presentation, "Stale window detected — cleaning up")
            analyticsClient?.track(SDKErrorEvent(
                error: .domain("Stale presentation window detected"),
                context: .presentOfferInitialization
            ))
            cleanup()
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            Logger.error(.integration(.notConfigured), context: .presentOfferInitialization)
            return nil
        }
        
        // Store dismiss handler
        onDismissHandler = onDismiss
        
        // Read before the overlay exists, so it is the host's window and not ours or another SDK's.
        let appWindows = windowScene.windows.filter { $0.windowLevel == .normal }
        let hostWindow = appWindows.first(where: \.isKeyWindow) ?? appWindows.first

        // Create overlay window
        let newWindow = UIWindow(windowScene: windowScene)
        // Set on the WINDOW, not via `.preferredColorScheme`: the SDUI palette
        // is dynamic UIColors, which resolve against the UIKit trait collection
        // and ignore the SwiftUI environment — so an explicit `appearance_mode`
        // had no effect inside a host that pins its own style.
        newWindow.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        newWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1000)
        newWindow.backgroundColor = .clear

        // Hosted at the root rather than presented from it. OfferSheetContainer
        // runs its own SwiftUI .sheet or .fullScreenCover, so a UIKit transition
        // here animates a transparent controller before anything appears, and
        // again on the way out while the overlay still swallows the host's taps.
        let hosting = HostOrientationHostingController(rootView: rootView)
        hosting.hostWindow = hostWindow
        hosting.view.backgroundColor = .clear
        newWindow.rootViewController = hosting
        newWindow.isHidden = false

        window = newWindow
        hostingController = hosting
        return newWindow
    }
    
    // MARK: - Cleanup

    /// Cleans up the presentation window after dismissal.
    static func cleanup() {
        let handler = onDismissHandler
        
        // The hosting controller is the window root, so this closes whatever
        // OfferSheetContainer presented, not the overlay. Kept because the
        // window teardown below does not run a SwiftUI sheet's dismissal.
        hostingController?.dismiss(animated: false)
        hostingController = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        onDismissHandler = nil
        
        // Fire handler after clearing state to prevent re-entrancy issues
        handler?()
    }
    
    #if DEBUG
    /// Test-only: set the dismiss handler without presenting a window.
    static func _setDismissHandler(_ handler: (() -> Void)?) {
        onDismissHandler = handler
    }
    #endif

    // MARK: - Orientation

    /// The orientations the sheet allows: the host's, as UIKit reads them, so a game that fixes its orientation
    /// in code keeps it. Nil with no host, or no overlap with the app's own orientations, so the system default applies.
    static func sheetOrientations(host: UIViewController?, app: UIInterfaceOrientationMask) -> UIInterfaceOrientationMask? {
        guard var controller = host else { return nil }
        // UIKit asks the root and full-screen presentations only, never a container's child.
        while let presented = controller.presentedViewController,
              [.fullScreen, .overFullScreen].contains(presented.modalPresentationStyle) {
            controller = presented
        }
        let mask = controller.supportedInterfaceOrientations.intersection(app)
        return mask.isEmpty ? nil : mask
    }

    // MARK: - View Controller Discovery
    
    /// Finds the top-most presented view controller in the app's window hierarchy.
    static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return nil
        }
        return topViewController(from: rootViewController)
    }
    
    /// Recursively traverses view controller hierarchy to find the top-most controller.
    static func topViewController(from viewController: UIViewController) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController {
            return topViewController(from: presentedViewController)
        }
        if let navigationController = viewController as? UINavigationController,
           let top = navigationController.topViewController {
            return topViewController(from: top)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return topViewController(from: selected)
        }
        return viewController
    }
}

/// The overlay is the top window, so iOS takes the scene's orientation from it; it answers with the host's rules.
@MainActor
final class HostOrientationHostingController<Content: View>: UIHostingController<Content> {
    weak var hostWindow: UIWindow?
    /// The app's own orientations for a window; a seam so tests run without an app scene.
    var appOrientations: (UIWindow?) -> UIInterfaceOrientationMask = { UIApplication.shared.supportedInterfaceOrientations(for: $0) }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        PresentationWindow.sheetOrientations(host: hostWindow?.rootViewController, app: appOrientations(hostWindow))
            ?? super.supportedInterfaceOrientations
    }
}
