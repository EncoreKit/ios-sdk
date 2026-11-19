// Sources/Encore/Features/Offers/Data/OffersRepository.swift
//
// Repository for offer-related network operations.
// Wraps HTTPClient with offer-specific request/response handling.
//

import Foundation

internal struct OffersRepository: Sendable {
    private let client: HTTPClientProtocol
    private let signals: ServeSignalSource

    init(client: HTTPClientProtocol, signals: ServeSignalSource = .live) {
        self.client = client
        self.signals = signals
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
    ///   - purpose: `purpose: "prefetch"` marks a search the SDK runs before any sheet is shown.
    ///     Its result may later back the sheet the user opens with a tap, so it is a served
    ///     request like any other, not an impression.
    ///   - context: The placement's moment, location and trigger; the SDK adds the automatic fields.
    func search(
        userId: String,
        attributes: UserAttributes?,
        sdkVersion: String,
        variantId: String? = nil,
        placementId: String? = nil,
        maxPostbackTimeMs: Int? = nil,
        useCase: UseCase? = nil,
        publisherRewardDailyLimit: Int? = nil,
        purpose: String? = nil,
        context: PlacementContext? = nil
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
            maxPostbackTimeMs: maxPostbackTimeMs,
            purpose: purpose
        )

        let body = await body(base: request, publisherRewardDailyLimit: publisherRewardDailyLimit, context: context, useCase: useCase)
        Logger.debug(.offers, "Searching offers", object: request)
        warnIfNoMoment(context, placement: placementId)

        let startNs = PresentationClock.nowNs()
        let envelope: PromiseSearchResponse = try await client.request(
            path: "offers/search",
            method: "POST",
            body: body,
            query: nil
        )
        ServeTimings.recordRoundTrip(startNs: startNs)
        ImageBlurHashes.record(envelope.blurHashes)
        let dto = envelope.base

        guard dto.success else {
            let errorMessage = dto.error ?? "No offers available"
            throw EncoreError.protocol(.api(status: 400, code: "search_failed", message: errorMessage))
        }
        
        return envelope.offerResponse
    }

    /// The wire body: the generated request plus the stage 5 `context` and consent keys beside it.
    func body(base: DTO.Offers.SearchRequest, publisherRewardDailyLimit: Int?, context: PlacementContext?, useCase: UseCase? = nil) async -> PromiseSearchRequest {
        let switches = signals.switches()
        // Device fields are contextual (ruling D): gated on the device switch only, never on personalization.
        let device = switches.deviceReads ? signals.device() : nil
        let currency: String? = context?.moment?.event == "purchase" && context?.moment?.explicitCurrency == nil
            ? await signals.storefrontCurrency() : nil
        let payload = SearchContextPayload(
            placement: context, device: device, storefrontCurrency: currency,
            headlineCopySource: context?.headlineCopySource == nil ? signals.headlineCopySource(useCase) : nil
        )
        // The personalization switch is the app's own setting, not a device read, so the consent switch leaves it.
        let consent = switches.consentReads ? signals.consent() : ConsentSignals(personalization: signals.personalization())
        return PromiseSearchRequest(
            base: base, publisherRewardDailyLimit: publisherRewardDailyLimit, osVersion: device?.osVersion,
            context: payload == SearchContextPayload(placement: nil, device: nil, storefrontCurrency: nil) ? nil : payload,
            consent: consent.isEmpty ? nil : consent
        )
    }

    /// Debug builds warn once per placement when a sheet serve carries no moment (D16).
    private func warnIfNoMoment(_ context: PlacementContext?, placement: String?) {
        #if DEBUG
        guard let context, context.moment == nil else { return }
        let key = placement ?? "(unlabeled)"
        guard MomentWarnings.once.mutate({ $0.insert(key).inserted }) else { return }
        Logger.warn("[INTEGRATION] Placement \(key) served with no moment. Pass one: placement(_:).moment(_:), for example .moment(.streak(3)).")
        #endif
    }
}

#if DEBUG
internal enum MomentWarnings {
    static let once = Atomic<Set<String>>([])
}
#endif

// The prize fields ride beside the generated search types, each read on its own so
// a malformed one is dropped instead of failing the search. `sync_contract.sh` keeps
// the mode and the per-offer value out of the generated types for that reason.

internal struct PromiseSearchRequest: Encodable {
    let base: DTO.Offers.SearchRequest
    let publisherRewardDailyLimit: Int?
    /// A device read like `context.device`, but in `attributes`, where the shared device-signal schema takes it.
    var osVersion: String? = nil
    var context: SearchContextPayload? = nil
    /// Merged into `attributes`, beside the user's own attributes.
    var consent: ConsentSignals? = nil

    private enum CodingKeys: String, CodingKey { case publisherRewardDailyLimit, context, attributes }

    func encode(to encoder: Encoder) throws {
        var base = base
        let attributes = base.attributes
        base.attributes = nil
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(publisherRewardDailyLimit, forKey: .publisherRewardDailyLimit)
        try container.encodeIfPresent(context, forKey: .context)
        if attributes != nil || consent != nil || osVersion != nil {
            try container.encode(AttributesWithConsent(attributes: attributes, consent: consent, osVersion: osVersion), forKey: .attributes)
        }
    }
}

/// The user's attributes and the consent keys as one `attributes` object.
private struct AttributesWithConsent: Encodable {
    let attributes: DTO.Offers.UserAttributes?
    let consent: ConsentSignals?
    let osVersion: String?

    func encode(to encoder: Encoder) throws {
        try attributes?.encode(to: encoder)
        try consent?.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(osVersion, forKey: .osVersion)
    }

    private enum CodingKeys: String, CodingKey { case osVersion }
}

/// `/offers/search` `purpose` values.
internal enum OfferSearchPurpose {
    /// `purpose: "prefetch"` marks a search the SDK runs before any sheet is shown. Its result may
    /// later back the sheet the user opens with a tap, so it is a served request like any other,
    /// not an impression.
    static let prefetch = "prefetch"
    /// The serve a sheet opens with.
    static let show = "show"
    /// A component's serve when it appears, ahead of the tap (earliest-point serving).
    static let warm = "warm"
}

/// The search response with the prize fields read beside the generated type.
struct PromiseSearchResponse: Decodable {
    let base: DTO.Offers.SearchResponse
    let publisherRewardPromise: Bool?
    let publisherRewardMode: String?
    /// Offer id → its prize label, for the offers that carry a well-formed value.
    let publisherRewardLabels: [String: String]
    /// Image URL → BlurHash, from the hash beside each image URL; a malformed pair reads as none.
    let blurHashes: [String: String]

    private enum CodingKeys: String, CodingKey { case publisherRewardPromise, publisherRewardMode, offers }

    init(from decoder: Decoder) throws {
        base = try DTO.Offers.SearchResponse(from: decoder)
        // A malformed value is treated as absent: no promise, never a failed search.
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        publisherRewardPromise = try? container?.decodeIfPresent(Bool.self, forKey: .publisherRewardPromise)
        publisherRewardMode = try? container?.decodeIfPresent(String.self, forKey: .publisherRewardMode)
        let offers = (try? container?.decodeIfPresent([OfferRewardValue].self, forKey: .offers)) ?? []
        publisherRewardLabels = Dictionary(
            offers.compactMap { offer in offer.id.flatMap { id in offer.label.map { (id, $0) } } },
            uniquingKeysWith: { first, _ in first }
        )
        let hashed = (try? container?.decodeIfPresent([OfferImageBlurHashes].self, forKey: .offers)) ?? []
        blurHashes = hashed.reduce(into: [:]) { all, offer in all.merge(offer.hashes) { first, _ in first } }
    }
    var offerResponse: OfferResponse {
        OfferResponse(
            dto: base,
            publisherRewardPromise: publisherRewardPromise,
            publisherRewardMode: PublisherRewardMode(wire: publisherRewardMode),
            publisherRewardLabels: publisherRewardLabels
        )
    }
}

/// One offer's image hashes by URL, never throwing: the backend sends a hash beside each image URL
/// (`heroImageBlurHash`, `logoBlurHash`, `organization.logoBlurHash`, `creatives[].primaryImageBlurHash`).
internal struct OfferImageBlurHashes: Decodable {
    let hashes: [String: String]

    private enum Keys: String, CodingKey {
        case heroImageUrl, heroImageBlurHash, logoUrl, logoBlurHash, primaryImageUrl, primaryImageBlurHash, organization, creatives
    }

    init(from decoder: Decoder) throws {
        var hashes: [String: String] = [:]
        func pair(_ container: KeyedDecodingContainer<Keys>?, _ url: Keys, _ hash: Keys) {
            guard let url = try? container?.decodeIfPresent(String.self, forKey: url),
                  let hash = try? container?.decodeIfPresent(String.self, forKey: hash),
                  (6...128).contains(hash.count) else { return }
            hashes[url] = hash
        }
        let offer = try? decoder.container(keyedBy: Keys.self)
        pair(offer, .heroImageUrl, .heroImageBlurHash)
        pair(offer, .logoUrl, .logoBlurHash)
        pair(try? offer?.nestedContainer(keyedBy: Keys.self, forKey: .organization), .logoUrl, .logoBlurHash)
        if var creatives = try? offer?.nestedUnkeyedContainer(forKey: .creatives) {
            while !creatives.isAtEnd {
                guard let creative = try? creatives.nestedContainer(keyedBy: Keys.self) else { _ = try? creatives.decode(Skip.self); continue }
                pair(creative, .primaryImageUrl, .primaryImageBlurHash)
                pair(creative, .logoUrl, .logoBlurHash)
            }
        }
        self.hashes = hashes
    }

    /// Steps over an array element that is not an object.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}

/// One offer's `publisherRewardValue`, never throwing: a missing or wrong-typed
/// `label` or `amount` leaves `label` nil, which reads as no value. `amount` must be a
/// whole number in 0...Int32.max in any JSON number form (`1500.0` and `1.5e3` are 1500),
/// the same bound Android's `Int` sets, so both platforms keep and drop the same values.
private struct OfferRewardValue: Decodable {
    let id: String?
    let label: String?

    private enum CodingKeys: String, CodingKey { case id, publisherRewardValue }
    private enum ValueKeys: String, CodingKey { case amount, label }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        id = try? container?.decode(String.self, forKey: .id)
        guard let value = try? container?.nestedContainer(keyedBy: ValueKeys.self, forKey: .publisherRewardValue),
              let amount = try? value.decode(Int.self, forKey: .amount), (0...Int(Int32.max)).contains(amount),
              let raw = try? value.decode(String.self, forKey: .label) else {
            label = nil
            return
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        label = Campaign.isDisplayPropertyBlank(trimmed) ? nil : trimmed
    }
}
