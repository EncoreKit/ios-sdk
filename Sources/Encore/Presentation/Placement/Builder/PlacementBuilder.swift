// Presentation/Placement/Coordinator/Placement.swift
//
// Placement builder - fluent API for presenting offers.
// Lives in Presentation/ because it coordinates UI presentation.
// Async-first: delegates directly to OfferSheetCoordinator.present() async.

import Foundation

// MARK: - Public Protocol

/// Fluent builder for presenting Encore offers.
/// Create via `Encore.placement(_:)` and call `show()` to present.
/// Safe to build from any thread. `show()` automatically presents on main thread.
public protocol PlacementBuilderProtocol {
    var id: String { get }
    func show() async throws -> PresentationResult
    func show()
    func onLoadingStateChange(_ callback: @escaping @Sendable (Bool) -> Void) -> Self

    @available(*, deprecated, message: "Use Encore.shared.onPurchaseRequest() instead")
    func onGranted(_ callback: @escaping @Sendable (Entitlement) -> Void) -> Self

    @available(*, deprecated, message: "Use Encore.shared.onPassthrough() instead")
    func onNotGranted(_ callback: @escaping @Sendable (NotGrantedReason) -> Void) -> Self
}

// MARK: - Internal Implementation

internal struct PlacementBuilder: PlacementBuilderProtocol {
    
    internal private(set) var id: String
    
    private var onGrantedCallback: (@Sendable (Entitlement) -> Void)?
    private var onNotGrantedCallback: (@Sendable (NotGrantedReason) -> Void)?
    private var onLoadingStateChangeCallback: (@Sendable (Bool) -> Void)?
    
    internal init(id: String) {
        self.id = id
    }
    
    // MARK: - Present
    
    func show() async throws -> PresentationResult {
        if Encore.shared.passthroughHandler == nil {
            Logger.warn("[INTEGRATION] onPassthrough should be set before calling show() to receive not-granted callbacks. Call Encore.shared.onPassthrough() before presenting if you require passthrough handling.")
        }

        onLoadingStateChangeCallback?(true)
        defer { onLoadingStateChangeCallback?(false) }

        return try await withNotification {
            try await OfferSheetCoordinator.present(placementId: id)
        }
    }
    
    func show() {
        Task { try? await show() }
    }

    // MARK: - Builder Methods
    
    func onLoadingStateChange(_ callback: @escaping @Sendable (Bool) -> Void) -> PlacementBuilder {
        var copy = self
        copy.onLoadingStateChangeCallback = callback
        return copy
    }
    
    @available(*, deprecated, message: "Use Encore.shared.onPurchaseRequest() instead")
    func onGranted(_ callback: @escaping @Sendable (Entitlement) -> Void) -> PlacementBuilder {
        var copy = self
        copy.onGrantedCallback = callback
        return copy
    }

    @available(*, deprecated, message: "Use Encore.shared.onPassthrough() instead")
    func onNotGranted(_ callback: @escaping @Sendable (NotGrantedReason) -> Void) -> PlacementBuilder {
        var copy = self
        copy.onNotGrantedCallback = callback
        return copy
    }
 
    // MARK: - Private
    
    private func withNotification(
        _ block: () async throws -> PresentationResult
    ) async throws -> PresentationResult {
        let result = try await block()
        switch result {
        case .granted(let entitlement):
            // onPurchaseRequest already fired inside OfferSheetViewModel (at IAPClient.purchase call sites)
            onGrantedCallback?(entitlement)
            placementsManager.notifyGranted(placementId: id, entitlement: entitlement)
        case .notGranted(let reason):
            Encore.shared.passthroughHandler?(id)
            onNotGrantedCallback?(reason)
            placementsManager.notifyNotGranted(placementId: id, reason: reason)
        }
        return result
    }
}
