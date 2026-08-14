// Sources/Encore/Features/Offers/OffersManager.swift
//
// Domain logic for offer operations.
// Caching and prefetch concurrency are handled by OffersCache (actor).
//

import CryptoKit
import Foundation

// MARK: - OffersCache (actor)

/// Thread-safe offer cache with prefetch support.
/// Uses Swift actor isolation instead of manual locks — the compiler
/// enforces that all mutable state is accessed serially.
internal actor OffersCache {

    /// Cache TTL — 5 minutes.
    private static let cacheTTL: TimeInterval = 5 * 60

    /// Max concurrent image preload requests.
    private static let maxImageConcurrency = 6

    private struct CacheEntry {
        let userId: String
        let variantId: String?
        let response: OfferResponse
        let timestamp: Date
    }

    private var cache: CacheEntry?
    private var prefetchTask: Task<OfferResponse?, Never>?
    private var inFlightKey: (userId: String, variantId: String?)?

    // MARK: - Cache reads

    /// Returns cached response if fresh and matching, otherwise nil.
    func cached(userId: String, variantId: String?) -> OfferResponse? {
        guard let entry = cache,
              entry.userId == userId,
              entry.variantId == variantId,
              !isExpired(entry) else { return nil }
        Logger.debug(.offers, "Using prefetched offers (\(entry.response.offerCount) offers, age=\(ageMs(entry))ms)")
        return entry.response
    }

    /// Returns the in-flight prefetch task if it matches this request, otherwise nil.
    func inFlightTask(userId: String, variantId: String?) -> Task<OfferResponse?, Never>? {
        guard let key = inFlightKey,
              key.userId == userId,
              key.variantId == variantId,
              let task = prefetchTask,
              !task.isCancelled else { return nil }
        return task
    }

    /// Stores a response in the cache.
    func store(userId: String, variantId: String?, response: OfferResponse) {
        cache = CacheEntry(userId: userId, variantId: variantId, response: response, timestamp: Date())
    }

    // MARK: - Prefetch

    /// Fire-and-forget prefetch. Cancels any in-flight prefetch (latest identity wins).
    func startPrefetch(
        userId: String,
        attributes: UserAttributes?,
        variantId: String?,
        search: @Sendable @escaping (String, UserAttributes?, String?) async throws -> OfferResponse
    ) {
        prefetchTask?.cancel()
        inFlightKey = (userId, variantId)

        prefetchTask = Task { [weak self] in
            do {
                Logger.debug(.offers, "Prefetching offers for user: \(userId), variantId: \(variantId ?? "none")")
                let response = try await search(userId, attributes, variantId)
                guard !Task.isCancelled else {
                    Logger.debug(.offers, "Prefetch cancelled for user: \(userId)")
                    return nil
                }
                await self?.store(userId: userId, variantId: variantId, response: response)
                Logger.debug(.offers, "Prefetch complete: \(response.offerCount) offers cached")

                // Preload images in a detached task so callers aren't blocked
                Self.preloadImages(from: response)
                return response
            } catch is CancellationError {
                Logger.debug(.offers, "Prefetch cancelled for user: \(userId)")
                return nil
            } catch {
                Logger.warn(.offers, "Prefetch failed: \(error)")
                return nil
            }
        }
    }

    /// Clears cached offers and cancels in-flight prefetch.
    func clear() {
        prefetchTask?.cancel()
        prefetchTask = nil
        inFlightKey = nil
        cache = nil
        Logger.debug(.offers, "Cache cleared")
    }

    // MARK: - Private

    private func isExpired(_ entry: CacheEntry) -> Bool { ageMs(entry) > Int(Self.cacheTTL * 1000) }
    private func ageMs(_ entry: CacheEntry) -> Int { max(0, Int(Date().timeIntervalSince(entry.timestamp) * 1000)) }

    /// Every creative and logo URL a response would render.
    static func imageURLs(in response: OfferResponse) -> [URL] {
        Array(Set(
            response.offers.compactMap { offer -> [URL] in
                [offer.displayPrimaryImageUrl, offer.displayLogoUrl]
                    .compactMap { $0.flatMap { URL(string: $0) } }
            }.flatMap { $0 }
        ))
    }

    /// Preloads creative images into URLSession's shared cache (shared with AsyncImage).
    static func preloadImages(from response: OfferResponse) {
        let urls = imageURLs(in: response)
        guard !urls.isEmpty else { return }

        Task.detached(priority: .utility) {
            Logger.debug(.offers, "Preloading \(urls.count) images")
            await withTaskGroup(of: Void.self) { group in
                var launched = 0
                for url in urls {
                    if launched >= maxImageConcurrency {
                        await group.next()
                    }
                    group.addTask {
                        _ = try? await URLSession.shared.data(from: url)
                    }
                    launched += 1
                }
            }
            Logger.debug(.offers, "Image preload complete")
        }
    }
}

// MARK: - OffersManager

/// Domain logic for offer operations.
/// Coordinates between the repository (network) and cache (actor).
/// No locks, no @unchecked Sendable — thread safety is enforced by the compiler via OffersCache actor.
internal struct OffersManager: Sendable {
    private let repository: OffersRepository
    private let cache: OffersCache
    /// Where the per-use-case image-warm manifests live. Optional so tests can
    /// build a manager without one; with none, warming is simply never gated.
    private let storage: KeyValueStore?

    init(repository: OffersRepository, storage: KeyValueStore? = nil) {
        self.repository = repository
        self.cache = OffersCache()
        self.storage = storage
    }

    // MARK: - Prefetch

    /// Fire-and-forget prefetch. Cancels any in-flight prefetch (latest identity wins).
    /// Called from `configure()` so offers are warm when `show()` fires.
    func prefetch(userId: String, attributes: UserAttributes?, variantId: String? = nil) {
        let repo = repository
        Task {
            await cache.startPrefetch(
                userId: userId,
                attributes: attributes,
                variantId: variantId,
                search: { uid, attrs, vid in
                    try await repo.search(userId: uid, attributes: attrs, sdkVersion: Encore.sdkVersion, variantId: vid)
                }
            )
        }
    }

    // MARK: - Bootstrap Image Warm

    /// Warms `useCase`'s offer images into `URLCache.shared` once per device,
    /// not once per launch.
    ///
    /// Gated on a manifest of the URLs the last warm fetched: when every one of
    /// them is still in the shared cache there is nothing to warm, so the extra
    /// `/offers/search` never fires. No manifest (fresh install, or the cache
    /// was purged) means warm. Best-effort throughout: a failure just leaves
    /// the images to load organically at show time.
    func warmImagesIfNeeded(
        useCase: UseCase,
        userId: String,
        attributes: UserAttributes?,
        variantId: String?
    ) async {
        guard !userId.isEmpty else { return }
        if let manifest: [String] = storage?.load(Self.warmManifestKey(useCase, userId: userId)),
           !manifest.isEmpty,
           manifest.allSatisfy({ Self.isCached($0) }) {
            Logger.debug(.offers, "Image warm skipped for \(useCase.rawValue), already cached")
            return
        }

        do {
            let response = try await repository.search(
                userId: userId,
                attributes: attributes,
                sdkVersion: Encore.sdkVersion,
                variantId: variantId
            )
            let urls = OffersCache.imageURLs(in: response)
            OffersCache.preloadImages(from: response)
            storage?.save(urls.map(\.absoluteString), to: Self.warmManifestKey(useCase, userId: userId))
            Logger.debug(.offers, "Image warm for \(useCase.rawValue): \(urls.count) images")
        } catch {
            Logger.debug(.offers, "Image warm for \(useCase.rawValue) failed: \(error)")
        }
    }

    /// Identity-scoped (hashed, matching Android): user A's warmed set must
    /// not gate user B's warm.
    internal static func warmManifestKey(_ useCase: UseCase, userId: String) -> String {
        let user = SHA256.hash(data: Data(userId.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        return "encore.image_warm_manifest.\(useCase.rawValue).\(user)"
    }

    private static func isCached(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return URLCache.shared.cachedResponse(for: URLRequest(url: url)) != nil
    }

    // MARK: - Fetch Offers

    /// Fetches available offers for the current user.
    /// Returns cached offers if fresh, joins in-flight prefetch if matching, or fetches fresh.
    /// - Parameters:
    ///   - userId: The user identifier.
    ///   - attributes: Optional targeting attributes.
    ///   - variantId: Optional SDUI variant ID for filtering creatives by variant assignment.
    ///   - maxPostbackTimeMs: Optional filter restricting offers to campaigns whose postback
    ///     latency fits within this window. Passed for strict unlock mode.
    func fetchOffers(
        userId: String,
        attributes: UserAttributes?,
        variantId: String? = nil,
        maxPostbackTimeMs: Int? = nil
    ) async throws -> OfferResponse {
        guard !userId.isEmpty else {
            throw EncoreError.domain("userId cannot be empty")
        }

        // Cache/prefetch paths only apply to default (non-strict) fetches, since
        // maxPostbackTimeMs changes the eligible offer set.
        if maxPostbackTimeMs == nil {
            if let cached = await cache.cached(userId: userId, variantId: variantId) {
                return cached
            }

            if let task = await cache.inFlightTask(userId: userId, variantId: variantId) {
                Logger.debug(.offers, "Waiting for in-flight prefetch to complete")
                if let result = await task.value {
                    Logger.debug(.offers, "Using just-completed prefetch (\(result.offerCount) offers)")
                    return result
                }
            }
        }

        Logger.debug(.offers, "Fetching offers for user: \(userId), variantId: \(variantId ?? "none")")
        let response = try await repository.search(
            userId: userId,
            attributes: attributes,
            sdkVersion: Encore.sdkVersion,
            variantId: variantId,
            maxPostbackTimeMs: maxPostbackTimeMs
        )
        if maxPostbackTimeMs == nil {
            await cache.store(userId: userId, variantId: variantId, response: response)
        }
        Logger.info(.offers, "Received \(response.offerCount) offers")
        return response
    }

    /// Checks if there are any offers available.
    func hasOffersAvailable(userId: String, attributes: UserAttributes?, variantId: String? = nil) async -> Bool {
        do {
            let response = try await fetchOffers(userId: userId, attributes: attributes, variantId: variantId)
            return !response.offerList.isEmpty
        } catch {
            Logger.warn(.offers, "Failed to check availability: \(error)")
            return false
        }
    }

    // MARK: - Cache Management

    /// Clears cached offers. Call on reset/logout or when attributes change.
    func clearCache() {
        Task { await cache.clear() }
    }
}
