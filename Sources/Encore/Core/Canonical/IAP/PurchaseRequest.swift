//
//  PurchaseRequest.swift
//  Encore
//
//  Context passed to the `onPurchaseRequest` handler when Encore triggers a purchase.
//

import Foundation

/// Context passed to `onPurchaseRequest` when Encore's offer flow triggers a purchase.
///
/// Use this to route purchases through your subscription manager (RevenueCat, Adapty, etc.)
/// with full context including optional promotional offers.
///
/// **Simple usage (no promo offers):**
/// ```swift
/// Encore.shared.onPurchaseRequest { request in
///     try await Purchases.shared.purchase(request.productId)
/// }
/// ```
///
/// **With promotional offer support:**
/// ```swift
/// Encore.shared.onPurchaseRequest { request in
///     if let promoOfferId = request.promoOfferId {
///         let offer = try await Purchases.shared.promotionalOffer(
///             forProductDiscount: promoOfferId, product: product
///         )
///         try await Purchases.shared.purchase(product, promotionalOffer: offer)
///     } else {
///         try await Purchases.shared.purchase(request.productId)
///     }
/// }
/// ```
public struct PurchaseRequest: Sendable {
    /// The IAP product identifier to purchase (e.g., "com.app.monthly_premium").
    public let productId: String

    /// The placement that triggered this purchase, if any.
    public let placementId: String?

    /// App Store Connect promotional offer identifier, when a promotional offer
    /// should be applied to this purchase. `nil` for standard purchases.
    public let promoOfferId: String?

    public init(productId: String, placementId: String? = nil, promoOfferId: String? = nil) {
        self.productId = productId
        self.placementId = placementId
        self.promoOfferId = promoOfferId
    }
}
