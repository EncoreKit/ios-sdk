//
//  PromoSignatureRepository.swift
//  Encore
//
//  Fetches promotional offer signatures from the backend.
//  The backend uses the app's stored .p8 key to generate JWS signatures.
//

import Foundation

/// Response from the promo-signature endpoint.
struct PromoSignatureResponse: Decodable {
    let keyId: String
    let offerId: String
    let nonce: String
    let timestamp: Int
    let signature: String
}

/// Repository for fetching promotional offer signatures from the backend.
final class PromoSignatureRepository: @unchecked Sendable {
    private let client: HTTPClientProtocol
    
    init(client: HTTPClientProtocol) {
        self.client = client
    }
    
    /// Fetches a promotional offer signature for the given product.
    /// - Parameter productId: The IAP product ID to generate a signature for
    /// - Returns: A `PromoSignatureResponse` with keyId, offerId, nonce, timestamp, and base64 signature
    func fetchSignature(productId: String) async throws -> PromoSignatureResponse {
        return try await client.request(
            path: "promo-signature",
            method: "GET",
            query: ["productId": productId]
        )
    }
}
