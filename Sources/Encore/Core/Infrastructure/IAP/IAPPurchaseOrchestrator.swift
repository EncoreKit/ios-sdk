//
//  IAPPurchaseOrchestrator.swift
//  Encore
//
//  High-level IAP purchase flow that automatically chooses between
//  introductory offer (direct purchase) and promotional offer (server-signed).
//
//  Reusable across any context that needs to trigger an IAP purchase —
//  post-offer Safari dismiss, IAP-First flow, etc.
//

import Foundation
import StoreKit

// MARK: - Result Type

enum IAPPurchaseResult {
    case purchased(Transaction)
    case cancelled
    case failed(String)
}

// MARK: - Orchestrator

@MainActor
@available(iOS 15.0, *)
struct IAPPurchaseOrchestrator {

    /// Attempts to purchase the given IAP product.
    ///
    /// Checks intro offer eligibility first:
    /// - Eligible → direct purchase (new subscriber gets free trial)
    /// - Not eligible → fetches a server-generated promotional offer signature
    ///   and purchases with that (lapsed subscriber gets win-back trial)
    static func purchase(productId: String) async -> IAPPurchaseResult {
        do {
            guard let product = try await Product.products(for: [productId]).first else {
                Logger.warn("⚠️ [IAP] Product not found: \(productId)")
                return .failed("Product not found: \(productId)")
            }

            let isEligibleForIntro = await product.subscription?.isEligibleForIntroOffer ?? false

            if isEligibleForIntro {
                return await purchaseWithIntroOffer(productId: productId)
            } else {
                let promoResult = await purchaseWithPromotionalOffer(productId: productId)
                if case .failed = promoResult {
                    Logger.info("🔄 [IAP] Promotional offer failed, falling back to direct purchase so user still sees the payment sheet")
                    return await purchaseWithIntroOffer(productId: productId)
                }
                return promoResult
            }
        } catch {
            Logger.warn("❌ [IAP] Purchase failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Intro Offer (new subscribers)

    private static func purchaseWithIntroOffer(productId: String) async -> IAPPurchaseResult {
        Logger.debug("🛒 [IAP] User eligible for intro offer, purchasing directly: \(productId)")

        do {
            if let txn = try await IAPClient.purchase(productId: productId) {
                Logger.info("✅ [IAP] Intro offer purchase successful: \(productId)")
                return .purchased(txn)
            } else {
                Logger.debug("⚠️ [IAP] Intro offer purchase cancelled: \(productId)")
                return .cancelled
            }
        } catch {
            Logger.warn("❌ [IAP] Intro offer purchase failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Promotional Offer (lapsed subscribers)

    private static func purchaseWithPromotionalOffer(productId: String) async -> IAPPurchaseResult {
        guard let repo = promoSignatureRepository else {
            Logger.warn("⚠️ [IAP] SDK not configured — cannot fetch promotional offer signature")
            return .failed("SDK not configured for promotional offers")
        }

        let sigResponse: PromoSignatureResponse
        do {
            sigResponse = try await repo.fetchSignature(productId: productId)
        } catch {
            Logger.warn("⚠️ [IAP] Failed to fetch promotional offer signature: \(error). Ensure the In-App Purchase key (.p8) and Promotional Offer ID are configured in the publisher portal.")
            return .failed("Failed to fetch promotional offer signature")
        }

        guard let nonce = UUID(uuidString: sigResponse.nonce) else {
            Logger.warn("⚠️ [IAP] Invalid nonce received from server: \(sigResponse.nonce)")
            return .failed("Invalid nonce from server")
        }

        guard let signatureData = Data(base64Encoded: sigResponse.signature) else {
            Logger.warn("⚠️ [IAP] Invalid signature received from server")
            return .failed("Invalid signature from server")
        }

        Logger.debug("🛒 [IAP] User not eligible for intro offer, using promotional offer: \(sigResponse.offerId)")

        do {
            if let txn = try await IAPClient.purchaseWithPromotionalOffer(
                productId: productId,
                offerID: sigResponse.offerId,
                keyID: sigResponse.keyId,
                nonce: nonce,
                signature: signatureData,
                timestamp: sigResponse.timestamp
            ) {
                Logger.info("✅ [IAP] Promotional offer purchase successful: \(productId), txn: \(txn.id)")
                return .purchased(txn)
            } else {
                Logger.debug("⚠️ [IAP] Promotional offer purchase cancelled or pending: \(productId)")
                return .cancelled
            }
        } catch {
            Logger.warn("❌ [IAP] Promotional offer purchase failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }
}
