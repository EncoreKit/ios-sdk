// Sources/Encore/Core/Canonical/IAP/IAPContext.swift
//
// Immutable context for IAP subscription data.
// Separated from RemoteConfig to maintain clear boundaries between
// server configuration and runtime IAP state.
//

import Foundation

/// Immutable context containing IAP subscription information.
///
/// This struct holds subscription data fetched at runtime from StoreKit.
/// It's designed to be composed with `RemoteConfig` in an `OfferContext`
/// for template variable resolution.
///
/// Thread-safe by design (immutable struct conforming to Sendable).
struct IAPContext: Sendable {
    
    /// The localized subscription price (e.g., "$4.99")
    let subscriptionPrice: String?
    
    /// The subscription product display name
    let subscriptionName: String?
    
    /// The subscription period suffix (e.g., "/month", "/year")
    let subscriptionPeriod: String?
    
    /// Whether the product has a free trial
    let hasFreeTrial: Bool
    
    /// Free trial value for template substitution (e.g., "7", "1", "3")
    let freeTrialValue: String?
    
    /// Free trial unit for template substitution (e.g., "day", "days", "month")
    let freeTrialUnit: String?
    
    /// Formatted free trial duration (e.g., "7 days", "1 month")
    let freeTrialDuration: String?
    
    /// Empty context with no IAP data
    static let empty = IAPContext(
        subscriptionPrice: nil,
        subscriptionName: nil,
        subscriptionPeriod: nil,
        hasFreeTrial: false,
        freeTrialValue: nil,
        freeTrialUnit: nil,
        freeTrialDuration: nil
    )
    
    /// Creates an IAPContext from IAPProductInfo
    init(from productInfo: IAPProductInfo?) {
        self.subscriptionPrice = productInfo?.displayPrice
        self.subscriptionName = productInfo?.displayName
        self.subscriptionPeriod = productInfo?.subscriptionPeriod
        self.hasFreeTrial = productInfo?.hasFreeTrial ?? false
        self.freeTrialValue = productInfo?.freeTrialValue
        self.freeTrialUnit = productInfo?.freeTrialUnit
        self.freeTrialDuration = productInfo?.freeTrialDuration
    }
    
    /// Creates an IAPContext with explicit values
    init(
        subscriptionPrice: String?,
        subscriptionName: String?,
        subscriptionPeriod: String?,
        hasFreeTrial: Bool = false,
        freeTrialValue: String? = nil,
        freeTrialUnit: String? = nil,
        freeTrialDuration: String? = nil
    ) {
        self.subscriptionPrice = subscriptionPrice
        self.subscriptionName = subscriptionName
        self.subscriptionPeriod = subscriptionPeriod
        self.hasFreeTrial = hasFreeTrial
        self.freeTrialValue = freeTrialValue
        self.freeTrialUnit = freeTrialUnit
        self.freeTrialDuration = freeTrialDuration
    }
}
