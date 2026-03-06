import Foundation

/// Global callback registry for placement events. Supports fluent chaining.
public final class PlacementsManager {
    private var onGrantedCallback: ((String, Entitlement) -> Void)?
    private var onNotGrantedCallback: ((String, NotGrantedReason) -> Void)?
    
    internal init() {}
    
    /// Register a callback for when any placement grants an entitlement.
    @available(*, deprecated, message: "Use Encore.shared.onPurchaseRequest() and Encore.shared.onPassthrough() instead")
    @discardableResult
    public func onGranted(_ callback: @escaping (String, Entitlement) -> Void) -> PlacementsManager {
        self.onGrantedCallback = callback
        return self
    }

    /// Register a callback for when any placement does not grant.
    @available(*, deprecated, message: "Use Encore.shared.onPurchaseRequest() and Encore.shared.onPassthrough() instead")
    @discardableResult
    public func onNotGranted(_ callback: @escaping (String, NotGrantedReason) -> Void) -> PlacementsManager {
        self.onNotGrantedCallback = callback
        return self
    }
    
    // MARK: - Internal
    
    internal func notifyGranted(placementId: String, entitlement: Entitlement) {
        Logger.debug("🎯 [PLACEMENTS] '\(placementId)' granted: \(entitlement)")
        onGrantedCallback?(placementId, entitlement)
    }
    
    internal func notifyNotGranted(placementId: String, reason: NotGrantedReason) {
        Logger.debug("🎯 [PLACEMENTS] '\(placementId)' not granted: \(reason)")
        onNotGrantedCallback?(placementId, reason)
    }
}
