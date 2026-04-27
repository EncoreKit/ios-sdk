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

/// Tracked when IAP purchase is being presented
struct IAPPurchasePresentingEvent: AnalyticsEvent {
    static let eventName = "sdk_iap_purchase_presenting"
    
    let productId: String
    let productName: String
    let price: String
    let type: String
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
