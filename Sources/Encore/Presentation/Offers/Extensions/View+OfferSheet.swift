// Presentation/Offers/Extensions/View+Offers.swift
//
// SwiftUI modifier for declarative offer presentation.
//

import SwiftUI

// MARK: - View Extension

public extension View {
    /// Presents an Encore offer sheet when `isPresented` becomes true.
    ///
    /// This is a declarative alternative to `Placement.show()`.
    /// On iOS < 17, gracefully returns `.notGranted(.unsupportedOS)`.
    ///
    /// ## Event Callbacks vs State Tracking
    ///
    /// Use the callbacks for **one-time events** (analytics, navigation, celebration UI):
    ///
    /// ```swift
    /// .encoreSheet(
    ///     isPresented: $showOffer,
    ///     onGranted: { entitlement in
    ///         showConfetti()
    ///         navigateToPremiumOnboarding()
    ///     },
    ///     onNotGranted: { reason in
    ///         continueWithFreeTier()
    ///     }
    /// )
    /// ```
    ///
    /// Use ``Encore/isActivePublisher(for:in:)`` for **ongoing state** (feature gating):
    ///
    /// ```swift
    /// Encore.shared.isActivePublisher(for: .pro)
    ///     .sink { isActive in
    ///         premiumButton.isHidden = isActive
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: Binding that triggers presentation when true. Automatically reset to false on completion.
    ///   - onGranted: Called when the user earns an entitlement. Use for one-time events like celebration UI or navigation.
    ///   - onNotGranted: Called when no entitlement is granted (user declined, no offers, etc). Use for flow continuation.
    @available(*, deprecated, message: "Use Encore.shared.onPurchaseRequest() and Encore.shared.onPassthrough() instead. Present with Encore.placement().show()")
    func encoreSheet(
        isPresented: Binding<Bool>,
        onGranted: ((Entitlement) -> Void)? = nil,
        onNotGranted: ((NotGrantedReason) -> Void)? = nil
    ) -> some View {
        modifier(
            EncoreSheetModifier(
                isPresented: isPresented,
                onGranted: onGranted,
                onNotGranted: onNotGranted
            )
        )
    }
}

// MARK: - Modifier Implementation

struct EncoreSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onGranted: ((Entitlement) -> Void)?
    let onNotGranted: ((NotGrantedReason) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .task(id: isPresented) {
                guard isPresented else { return }
                defer { isPresented = false }
                
                do {
                    let result = try await OfferSheetCoordinator.present()
                    switch result {
                    case .granted(let entitlement):
                        // onPurchaseRequest already fired inside OfferSheetViewModel
                        onGranted?(entitlement)
                    case .notGranted(let reason):
                        Encore.shared.passthroughHandler?(nil)
                        onNotGranted?(reason)
                    }
                } catch {
                    // Errors are logged internally by OfferSheetCoordinator
                    Logger.error(.transport(.network(error)), context: .presentOfferInitialization)
                }
            }
    }
}
