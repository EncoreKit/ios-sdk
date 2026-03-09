// Sources/Encore/Features/Offers/OffersManager.swift
//
// Domain logic for offer operations.
// Pure business logic - no UI or analytics dependencies.
//

import Foundation

/// Manager for offer-related domain logic.
/// Wraps OffersRepository with validation and domain rules.
internal struct OffersManager: Sendable {
    private let repository: OffersRepository
    
    init(repository: OffersRepository) {
        self.repository = repository
    }
    
    // MARK: - Fetch Offers
    
    /// Fetches available offers for the current user.
    /// - Parameters:
    ///   - userId: The user identifier.
    ///   - attributes: Optional targeting attributes.
    ///   - variantId: Optional SDUI variant ID for filtering creatives by variant assignment.
    /// - Returns: The offer response containing available offers.
    /// - Throws: `EncoreError` if fetching fails.
    func fetchOffers(userId: String, attributes: UserAttributes?, variantId: String? = nil) async throws -> OfferResponse {
        guard !userId.isEmpty else {
            throw EncoreError.domain("userId cannot be empty")
        }
        
        Logger.debug("[OFFERS] Fetching offers for user: \(userId), variantId: \(variantId ?? "none")")
        
        let response = try await repository.search(
            userId: userId,
            attributes: attributes,
            sdkVersion: Encore.sdkVersion,
            variantId: variantId
        )
        
        Logger.info("[OFFERS] Received \(response.offerCount) offers")
        return response
    }
    
    /// Checks if there are any offers available.
    func hasOffersAvailable(userId: String, attributes: UserAttributes?, variantId: String? = nil) async -> Bool {
        do {
            let response = try await fetchOffers(userId: userId, attributes: attributes, variantId: variantId)
            return !response.offerList.isEmpty
        } catch {
            Logger.warn("[OFFERS] Failed to check availability: \(error)")
            return false
        }
    }
}
