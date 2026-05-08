//
//  IAPClient.swift
//  Encore
//
//  Minimal IAP client for handling subscription purchases.
//  Infrastructure layer - wraps StoreKit.
//

import Foundation
import StoreKit

/// Product info returned by fetchProductInfo
struct IAPProductInfo {
    let id: String
    let displayName: String
    let displayPrice: String  // Localized price string (e.g., "$4.99")
    let subscriptionPeriod: String?  // e.g., "/month", "/year", "/week"

    // Free trial / introductory offer info
    let hasFreeTrial: Bool  // True if product has a free trial
    let freeTrialValue: String?  // e.g., "7", "1", "3" - for template substitution
    let freeTrialUnit: String?  // e.g., "day", "days", "week", "month" - for template substitution
    let freeTrialDuration: String?  // e.g., "7 days", "1 month" - formatted string
    /// Trial length normalized to days (week × 7, month × 30, year × 365). Sent
    /// to the backend in the lead payload so it can schedule the trial-end
    /// reminder off the authoritative StoreKit value, not a portal-typed mirror.
    let freeTrialDays: Int?
}

@MainActor
@available(iOS 15.0, *)
class IAPClient {
    
    // MARK: - Product Info
    
    /// Fetch product information without purchasing
    /// Returns product info if found, nil if product not found
    static func fetchProductInfo(productId: String) async -> IAPProductInfo? {
        do {
            Logger.debug("🛒 [IAP] Fetching product info: \(productId)")
            
            guard let product = try await Product.products(for: [productId]).first else {
                Logger.debug("❌ [IAP] Product not found: \(productId)")
                return nil
            }
            
            // Format subscription period if this is a subscription product
            let period = formatSubscriptionPeriod(product.subscription?.subscriptionPeriod)
            
            // Extract free trial information from introductory offer
            let trial = extractFreeTrialInfo(from: product)

            if trial.hasFreeTrial {
                Logger.debug("✅ [IAP] Product info fetched: \(product.displayName) - \(product.displayPrice)\(period ?? "") with \(trial.duration ?? "unknown") free trial")
            } else {
                Logger.debug("✅ [IAP] Product info fetched: \(product.displayName) - \(product.displayPrice)\(period ?? "")")
            }

            return IAPProductInfo(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                subscriptionPeriod: period,
                hasFreeTrial: trial.hasFreeTrial,
                freeTrialValue: trial.value,
                freeTrialUnit: trial.unit,
                freeTrialDuration: trial.duration,
                freeTrialDays: trial.days
            )
        } catch {
            Logger.debug("❌ [IAP] Failed to fetch product info: \(error)")
            return nil
        }
    }
    
    /// Format subscription period as a readable string (e.g., "/month", "/year")
    private static func formatSubscriptionPeriod(_ period: Product.SubscriptionPeriod?) -> String? {
        guard let period = period else { return nil }
        
        switch period.unit {
        case .day:
            return period.value == 1 ? "/day" : "/\(period.value) days"
        case .week:
            return period.value == 1 ? "/week" : "/\(period.value) weeks"
        case .month:
            return period.value == 1 ? "/month" : "/\(period.value) months"
        case .year:
            return period.value == 1 ? "/year" : "/\(period.value) years"
        @unknown default:
            return nil
        }
    }
    
    /// Free-trial context extracted from a StoreKit product's introductory offer.
    private struct TrialInfo {
        let hasFreeTrial: Bool
        let value: String?     // e.g., "7"
        let unit: String?      // e.g., "day", "days", "month"
        let duration: String?  // e.g., "7 days", "1 month"
        let days: Int?         // normalized day count (week × 7, month × 30, year × 365)

        static let none = TrialInfo(hasFreeTrial: false, value: nil, unit: nil, duration: nil, days: nil)
    }

    /// Extract free trial information from product's introductory offer.
    private static func extractFreeTrialInfo(from product: Product) -> TrialInfo {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer,
              introOffer.paymentMode == .freeTrial else {
            return .none
        }

        let period = introOffer.period
        let value = "\(period.value)"

        // Determine singular vs plural unit + day multiplier in one switch.
        // Day multipliers are approximations where months/years vary — fine
        // for reminder scheduling (fires ~1-2 days before trial end, and
        // Apple's actual end date is shown in Settings → Subscriptions).
        let unit: String
        let daysPerUnit: Int
        switch period.unit {
        case .day:
            unit = period.value == 1 ? "day" : "days"
            daysPerUnit = 1
        case .week:
            unit = period.value == 1 ? "week" : "weeks"
            daysPerUnit = 7
        case .month:
            unit = period.value == 1 ? "month" : "months"
            daysPerUnit = 30
        case .year:
            unit = period.value == 1 ? "year" : "years"
            daysPerUnit = 365
        @unknown default:
            unit = "days"
            daysPerUnit = 1
        }

        return TrialInfo(
            hasFreeTrial: true,
            value: value,
            unit: unit,
            duration: "\(value) \(unit)",
            days: period.value * daysPerUnit
        )
    }
    
    // MARK: - Promotional Offer Purchase
    
    /// Purchase a subscription with a promotional offer.
    /// Requires server-generated signature parameters (see: https://developer.apple.com/documentation/storekit/generating-a-signature-for-promotional-offers)
    static func purchaseWithPromotionalOffer(
        productId: String,
        offerID: String,
        keyID: String,
        nonce: UUID,
        signature: Data,
        timestamp: Int
    ) async throws -> Transaction? {
        Logger.debug("🛒 [IAP] Fetching product for promotional offer: \(productId), offer: \(offerID)")
        
        guard let product = try await Product.products(for: [productId]).first else {
            Logger.debug("❌ [IAP] Product not found: \(productId)")
            analyticsClient?.track(IAPProductNotFoundEvent(productId: productId))
            throw IAPError.productNotFound
        }
        
        if let promoOffers = product.subscription?.promotionalOffers {
            Logger.debug("🛒 [IAP] Available promotional offers: \(promoOffers.map { $0.id })")
        }
        
        Logger.debug("🛒 [IAP] Purchasing with promotional offer: \(offerID)")
        
        let result = try await product.purchase(options: [
            .promotionalOffer(
                offerID: offerID,
                keyID: keyID,
                nonce: nonce,
                signature: signature,
                timestamp: timestamp
            )
        ])
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            Logger.info("✅ [IAP] Promotional offer purchase successful: \(product.displayName) (offer: \(offerID))")
            
            if let observer = Encore.shared.services?.iapObserver {
                observer.linkTransaction(originalTransactionId: String(transaction.originalID))
            }
            
            return transaction
            
        case .userCancelled:
            Logger.debug("🚫 [IAP] User cancelled promotional offer purchase")
            return nil
            
        case .pending:
            Logger.debug("⏳ [IAP] Promotional offer purchase pending")
            return nil
            
        @unknown default:
            Logger.debug("❓ [IAP] Unknown promotional offer purchase result")
            return nil
        }
    }
    
    // MARK: - Delegated Purchase

    /// Delegates purchase to the host app's handler if registered.
    /// Falls back to native StoreKit purchase when no handler is set.
    /// Returns true if the purchase succeeded, false otherwise.
    static func delegatePurchase(productId: String, placementId: String?, promoOfferId: String? = nil) async -> Bool {
        let request = PurchaseRequest(productId: productId, placementId: placementId, promoOfferId: promoOfferId)

        // 1. Prefer Bool-returning handler (explicit success/cancel signal)
        if let handler = Encore.shared.purchaseRequestBoolHandler {
            analyticsClient?.track(IAPHandlerInvokedEvent(
                productId: productId,
                placementId: placementId,
                promoOfferId: promoOfferId,
                handlerKind: "bool"
            ))
            do {
                let success = try await handler(request)
                if success {
                    Encore.shared.services?.iapObserver?.reconcileTransactions()
                    Logger.info("✅ [IAP] Delegated purchase completed: \(productId)")
                } else {
                    Logger.info("🚫 [IAP] Delegated purchase cancelled: \(productId)")
                }
                return success
            } catch {
                Logger.warn("⚠️ [IAP] Purchase handler threw: \(error)")
                return false
            }
        }

        // 2. Legacy throws-based handler (success = no throw, cancel = throw)
        if let handler = Encore.shared.purchaseRequestHandler {
            analyticsClient?.track(IAPHandlerInvokedEvent(
                productId: productId,
                placementId: placementId,
                promoOfferId: promoOfferId,
                handlerKind: "void"
            ))
            do {
                try await handler(request)
                Encore.shared.services?.iapObserver?.reconcileTransactions()
                Logger.info("✅ [IAP] Delegated purchase completed: \(productId)")
                return true
            } catch {
                Logger.warn("⚠️ [IAP] Delegated purchase failed: \(error)")
                return false
            }
        }

        // 3. No handler — native StoreKit fallback
        Logger.info("🛒 [IAP] No purchaseRequestHandler set — using native StoreKit. Set onPurchaseRequest to purchase through your subscription manager.")
        do {
            let transaction = try await IAPClient.purchase(productId: productId)
            guard let transaction else { return false }
            await Encore.shared.purchaseCompleteHandler?(transaction, productId)
            return true
        } catch {
            Logger.warn("⚠️ [IAP] StoreKit fallback purchase failed: \(error)")
            return false
        }
    }


    // MARK: - Purchase
    /// Fetch and purchase a product by ID
    /// Returns transaction if successful, nil if cancelled, throws on error
    static func purchase(productId: String) async throws -> Transaction? {
        var productName = ""
        var price = ""
        var productType = ""
        
        do {
            Logger.debug("🛒 [IAP] Fetching product: \(productId)")
            
            // Fetch product from App Store
            guard let product = try await Product.products(for: [productId]).first else {
                Logger.debug("❌ [IAP] Product not found: \(productId)")
                analyticsClient?.track(IAPProductNotFoundEvent(productId: productId))
                throw IAPError.productNotFound
            }
            
            Logger.debug("🛒 [IAP] Starting purchase: \(product.displayName)")
            
            productName = product.displayName
            price = product.price.description
            productType = product.type.rawValue
            
            analyticsClient?.track(
                IAPPurchasePresentingEvent(
                    productId: productId,
                    productName: productName,
                    price: price,
                    type: productType
                )
            )
            
            // Purchase (system shows native UI)
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify and finish transaction
                let transaction = try checkVerified(verification)
                await transaction.finish()
                
                Logger.debug("✅ [IAP] Purchase successful: \(product.displayName)")
                
                // Immediate IAP link for NCL attribution (belt-and-suspenders with reconciliation)
                let originalId = String(transaction.originalID)
                if let observer = Encore.shared.services?.iapObserver {
                    observer.linkTransaction(originalTransactionId: originalId)
                }
                
                var environment: String? = nil
                if #available(iOS 17.2, *) {
                    environment = transaction.environment.rawValue
                }
                
                analyticsClient?.track(
                    IAPPurchaseSuccessEvent(
                        productId: productId,
                        productName: productName,
                        price: price,
                        type: productType,
                        transactionId: "\(transaction.id)",
                        purchaseDate: transaction.purchaseDate.description,
                        originalPurchaseDate: transaction.originalPurchaseDate.description,
                        environment: environment
                    )
                )
                
                return transaction
                
            case .userCancelled:
                Logger.debug("🚫 [IAP] User cancelled purchase")
                analyticsClient?.track(
                    IAPPurchaseFailedEvent(
                        productId: productId,
                        productName: productName,
                        price: price,
                        type: productType,
                        reason: "user_declined"
                    )
                )
                return nil
                
            case .pending:
                Logger.debug("⏳ [IAP] Purchase pending")
                analyticsClient?.track(
                    IAPPurchasePendingEvent(
                        productId: productId,
                        productName: productName,
                        price: price,
                        type: productType
                    )
                )
                return nil
                
            @unknown default:
                Logger.debug("❓ [IAP] Unknown purchase result")
                analyticsClient?.track(
                    IAPPurchaseFailedEvent(
                        productId: productId,
                        productName: productName,
                        price: price,
                        type: productType,
                        reason: "unknown"
                    )
                )
                return nil
            }
        } catch let error {
            analyticsClient?.track(
                IAPPurchaseFailedEvent(
                    productId: productId,
                    productName: productName,
                    price: price,
                    type: productType,
                    reason: "\(error)"
                )
            )
            return nil
        }
    }
    
    // MARK: - Verification
    
    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Errors

enum IAPError: Error {
    case productNotFound
    case failedVerification
}

extension IAPError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "IAP product not found"
        case .failedVerification:
            return "Transaction verification failed"
        }
    }
}
