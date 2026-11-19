// Campaigns the server refused a claim on as already completed (409). Hides them
// before the server's own exclusion reaches a cached list. A Yes never writes here.

import Foundation

final class CompletedCampaigns: @unchecked Sendable {
    static let storeKey = "com.encore.completedCampaigns"
    /// The 2.4 list, which a Yes wrote too. Its entries cannot be told apart, so `configure` removes it.
    static let legacyStoreKey = "com.encore.selfReportedCampaigns"

    static func removeLegacyList(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyStoreKey)
    }

    private let store: RawDataStore
    private let lock = NSLock()
    private var loaded: [String: [String]]?

    init(store: RawDataStore = UserDefaultsStore()) {
        self.store = store
    }

    func add(campaignId: String, userId: String) {
        var added = false
        mutate { all in
            var ids = all[userId] ?? []
            if !ids.contains(campaignId) { ids.append(campaignId); added = true }
            all[userId] = ids
        }
        // The campaign leaves every sheet at once: mounted triggers re-gate.
        if added { TriggerHeldOffers.changed() }
    }

    func contains(campaignId: String, userId: String) -> Bool {
        withSet { $0[userId]?.contains(campaignId) == true }
    }

    /// Moves `from`'s campaigns onto `to`, as identify() links the two ids.
    func carryOver(from oldUserId: String, to newUserId: String) {
        guard oldUserId != newUserId else { return }
        mutate { all in
            guard let old = all.removeValue(forKey: oldUserId) else { return }
            var merged = all[newUserId] ?? []
            for id in old where !merged.contains(id) { merged.append(id) }
            all[newUserId] = merged
        }
    }

    /// `response` without the campaigns `userId` already completed.
    func excluding(from response: OfferResponse, userId: String) -> OfferResponse {
        let done = Set(withSet { $0[userId] ?? [] })
        guard !done.isEmpty else { return response }
        return response.withOffers(response.offers.filter { !done.contains($0.id) })
    }

    // MARK: Storage

    private func withSet<T>(_ body: ([String: [String]]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(read())
    }

    private func mutate(_ change: (inout [String: [String]]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var all = read()
        change(&all)
        loaded = all
        do {
            try store.setRawData(try JSONEncoder().encode(all), forKey: Self.storeKey)
        } catch {
            Logger.warn(.offers, "Failed to save completed campaigns; kept for this session only: \(error)")
        }
    }

    /// An unreadable record reads as empty and is replaced on the next write:
    /// the server already hides these campaigns, so nothing is lost but speed.
    private func read() -> [String: [String]] {
        if let loaded { return loaded }
        let decoded = (try? store.rawData(forKey: Self.storeKey)).flatMap { $0 }
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        loaded = decoded
        return decoded
    }
}
