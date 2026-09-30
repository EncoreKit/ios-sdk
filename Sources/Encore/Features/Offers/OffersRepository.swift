// Sources/Encore/Features/Offers/Data/OffersRepository.swift
//
// Repository for offer-related network operations.
// Wraps HTTPClient with offer-specific request/response handling.
//

import Foundation

internal struct OffersRepository: Sendable {
    private let client: HTTPClientProtocol
    
    init(client: HTTPClientProtocol) {
        self.client = client
    }
    
    // MARK: - Search Offers
    
    /// Searches for available offers for a user
    /// - Parameters:
    ///   - userId: The user identifier
    ///   - attributes: Optional targeting attributes
    ///   - sdkVersion: SDK version string
    ///   - variantId: Optional SDUI variant ID for filtering creatives
    ///   - placementId: Publisher-supplied placement label. Stamped onto the
    ///     backend's `sdk_offer_requested` event so publisher analytics can break
    ///     the funnel out by placement. Pass it through `PlacementLabel.sanitized`.
    ///   - maxPostbackTimeMs: Optional filter to restrict offers to campaigns with postback latency
    ///     below this threshold (ms). Omit for no filtering (optimistic default).
    ///   - useCase: The surface being filled. The server resolves the variant from it
    ///     only when no `variantId` is sent; absent means churn, as today.
    ///   - publisherRewardDailyLimit: Asks the server whether the prize may be promised
    ///     (`publisherRewardPromise` on the response). Send only for an identified user with a prize.
    func search(
        userId: String,
        attributes: UserAttributes?,
        sdkVersion: String,
        variantId: String? = nil,
        placementId: String? = nil,
        maxPostbackTimeMs: Int? = nil,
        useCase: UseCase? = nil,
        publisherRewardDailyLimit: Int? = nil
    ) async throws -> OfferResponse {
        let request = DTO.Offers.SearchRequest(
            userId: userId,
            attributes: attributes?.asDTO,
            limit: 50,
            offset: 0,
            sdkVersion: sdkVersion,
            platform: .ios,
            variantId: variantId,
            placementId: placementId,
            useCase: useCase.flatMap { DTO.Offers.SearchRequest.useCasePayload(rawValue: $0.rawValue) },
            maxPostbackTimeMs: maxPostbackTimeMs
        )

        Logger.debug(.offers, "Searching offers", object: request)
        
        let envelope: PromiseSearchResponse = try await client.request(
            path: "offers/search",
            method: "POST",
            body: PromiseSearchRequest(base: request, publisherRewardDailyLimit: publisherRewardDailyLimit),
            query: nil
        )
        let dto = envelope.base

        guard dto.success else {
            let errorMessage = dto.error ?? "No offers available"
            throw EncoreError.protocol(.api(status: 400, code: "search_failed", message: errorMessage))
        }
        
        return OfferResponse(dto: dto, publisherRewardPromise: envelope.publisherRewardPromise)
    }
}

// The two prize-promise fields ride beside the generated search types until the
// backend adds them to the contract; the next `make sync-contract` replaces these.

private struct PromiseSearchRequest: Encodable {
    let base: DTO.Offers.SearchRequest
    let publisherRewardDailyLimit: Int?

    private enum CodingKeys: String, CodingKey { case publisherRewardDailyLimit }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(publisherRewardDailyLimit, forKey: .publisherRewardDailyLimit)
    }
}

private struct PromiseSearchResponse: Decodable {
    let base: DTO.Offers.SearchResponse
    let publisherRewardPromise: Bool?

    private enum CodingKeys: String, CodingKey { case publisherRewardPromise }

    init(from decoder: Decoder) throws {
        base = try DTO.Offers.SearchResponse(from: decoder)
        // A malformed value is treated as absent: no promise, never a failed search.
        publisherRewardPromise = try? decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent(Bool.self, forKey: .publisherRewardPromise)
    }
}
