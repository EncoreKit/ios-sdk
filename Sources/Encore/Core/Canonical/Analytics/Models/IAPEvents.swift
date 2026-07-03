//
//  IAPEvents.swift
//  Encore
//
//  Analytics events for In-App Purchase interactions.
//

import Foundation

// MARK: - IAP Events

/// Tracked when IAP product is not found
struct IAPProductNotFoundEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_product_not_found"
    
    let productId: String
}

/// Tracked when the IAP product is about to be presented to the user.
///
/// `trigger` distinguishes how the presentation surfaces:
///   - `"native"` — Encore is invoking StoreKit directly; the system
///     payment sheet is about to render.
///   - `"delegated_to_handler"` — the publisher set
///     `Encore.shared.onPurchaseRequest`, so we're handing off the
///     productId and product info; whatever the publisher's handler
///     shows next (StoreKit sheet via RevenueCat/Adapty, custom UI,
///     etc.) is outside our visibility, but we still emit the
///     presented event with the resolved product info so the backend
///     knows what was displayed.
struct IAPPurchasePresentingEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_presenting"

    let productId: String
    let productName: String
    let price: String
    let type: String
    let trigger: String
}

/// Tracked when IAP purchase succeeds
struct IAPPurchaseSuccessEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_success"
    
    // Base properties
    let productId: String
    let productName: String
    let price: String
    let type: String
    // Success-specific
    let transactionId: String
    let purchaseDate: String
    let originalPurchaseDate: String
    let environment: String?
}

/// Tracked when IAP purchase fails
struct IAPPurchaseFailedEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_failed"
    
    // Base properties
    let productId: String
    let productName: String
    let price: String
    let type: String
    // Failure-specific
    let reason: String
}

/// Tracked when IAP purchase is pending
struct IAPPurchasePendingEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_pending"

    let productId: String
    let productName: String
    let price: String
    let type: String
}

/// Tracked when a host-app purchase handler is invoked via
/// `Encore.shared.onPurchaseRequest`. Fires from `IAPClient.delegatePurchase`
/// exactly once per delegation attempt, regardless of outcome.
///
/// Fills the pre-existing observability gap where apps using subscription
/// managers (RevenueCat, Adapty, Qonversion) never emitted a "we tried to
/// invoke the IAP" signal — unlike the native StoreKit fallback which fires
/// `IAPPurchasePresentingEvent`. Paired with downstream backend events
/// (ASSN v2) this closes end-to-end attribution for delegated purchase flows.
struct IAPHandlerInvokedEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_handler_invoked"

    let productId: String
    let placementId: String?
    let promoOfferId: String?
    /// `"bool"` for the preferred `onPurchaseRequest async throws -> Bool`
    /// overload; `"void"` for the legacy `async throws -> Void` overload
    /// retained for backwards compat. Useful when debugging reports from
    /// publishers mid-migration between the two.
    let handlerKind: String
}
