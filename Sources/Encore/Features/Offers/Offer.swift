// Bundles fetched offers for the presentation layer.
// The OffersRepository handles success/error checking — this just carries data.

import Foundation

/// Note: Remote configuration is now fetched via /ui-config endpoint on identify(),
/// not from the offers response.
internal struct OfferResponse {
    let offers: [Offer]
    /// The server's answer to "may this user be promised the prize now?". Nil when
    /// the search didn't ask, or the backend predates the field: no promise.
    let publisherRewardPromise: Bool?

    init(dto: DTO.Offers.SearchResponse, publisherRewardPromise: Bool? = nil) {
        let campaigns = dto.offers.map { Campaign(dto: $0) }
        let claimable = campaigns.filter(\.isClaimable)
        if claimable.count < campaigns.count {
            Logger.warn(.offers, "Dropped \(campaigns.count - claimable.count) offer(s) with no creative and no tracking")
        }
        self.offers = claimable
        self.publisherRewardPromise = publisherRewardPromise
    }

    init(offers: [Offer], publisherRewardPromise: Bool?) {
        self.offers = offers
        self.publisherRewardPromise = publisherRewardPromise
    }

    func withPublisherRewardPromise(_ promise: Bool?) -> OfferResponse {
        OfferResponse(offers: offers, publisherRewardPromise: promise)
    }

    /// Number of offers
    var offerCount: Int { offers.count }

    /// Alias for presentation layer compatibility
    var offerList: [Offer] { offers }
}
