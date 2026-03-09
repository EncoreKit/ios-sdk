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
    
    /// Presents a SwiftUI view in a new overlay window above all other content.
    ///
    /// The view is hosted in a `UIHostingController` and presented modally from
    /// a transparent `UIWindow` at `alert + 1000` window level.
    ///
    /// - Parameters:
    ///   - rootView: The SwiftUI view to present.
    ///   - onDismiss: Called when the window is cleaned up (dismissal, system removal, etc).
    /// - Returns: `true` if presentation was initiated, `false` if no window scene available.
    @discardableResult
    static func present<Content: View>(_ rootView: Content, _ onDismiss: (() -> Void)? = nil) -> Bool {
        // Prevent double presentation
        guard window == nil else {
            Logger.warn("[PresentationWindow] Already presenting, ignoring duplicate request")
            return false
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            Logger.error(.integration(.notConfigured), context: .presentOfferInitialization)
            return false
        }
        
        // Store dismiss handler
        onDismissHandler = onDismiss
        
        // Create overlay window
        let newWindow = UIWindow(windowScene: windowScene)
        newWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1000)
        newWindow.backgroundColor = .clear
        newWindow.rootViewController = UIViewController()
        newWindow.isHidden = false
        
        // Create hosting controller
        let hosting = UIHostingController(rootView: rootView)
        hosting.modalPresentationStyle = .overFullScreen
        hosting.view.backgroundColor = .clear
        
        // Store references
        window = newWindow
        hostingController = hosting
        
        // Present
        newWindow.rootViewController?.present(hosting, animated: true)
        return true
    }
    
    // MARK: - Window Lifecycle (Legacy)
    
    /// Creates and returns a new presentation window at the highest level.
    /// - Returns: The created window, or nil if no window scene is available.
    /// - Note: Prefer `present(_:onDismiss:)` for SwiftUI views. This is kept for compatibility.
    static func create() -> UIWindow? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        
        let newWindow = UIWindow(windowScene: windowScene)
        newWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1000)
        newWindow.backgroundColor = .clear
        newWindow.rootViewController = UIViewController()
        newWindow.isHidden = false
        
        window = newWindow
        return newWindow
    }
    
    /// Cleans up the presentation window after dismissal.
    static func cleanup() {
        let handler = onDismissHandler
        
        hostingController?.dismiss(animated: false)
        hostingController = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        onDismissHandler = nil
        
        // Fire handler after clearing state to prevent re-entrancy issues
        handler?()
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
