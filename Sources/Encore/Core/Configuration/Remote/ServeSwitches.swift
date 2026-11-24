// The `/config` kill switches for the 2.7.x serve reads (CONTRACT 2.7) and the serve handle TTL (D7).
// Absent or malformed keys keep the defaults: reads on, earliest-point serving off (R28), TTL 300 s.

import Foundation

internal struct ServeSwitches: Sendable, Equatable, Codable {
    static let defaultHandleTtlSeconds: TimeInterval = 300

    var consentReads = true
    var deviceReads = true
    /// Off (R28): serve timing as on main. On: keyed reuse, warm on appear, debounced re-serve.
    var earliestPoint = false
    var handleTtlSeconds = ServeSwitches.defaultHandleTtlSeconds

    init() {}

    private enum Keys: String, CodingKey { case signals, serving, serveHandleTtlSeconds }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        var signals = container.nestedContainer(keyedBy: SignalKeys.self, forKey: .signals)
        try signals.encode(consentReads, forKey: .consentReads)
        try signals.encode(deviceReads, forKey: .deviceReads)
        var serving = container.nestedContainer(keyedBy: ServingKeys.self, forKey: .serving)
        try serving.encode(earliestPoint, forKey: .earliestPoint)
        try container.encode(handleTtlSeconds, forKey: .serveHandleTtlSeconds)
    }
    private enum SignalKeys: String, CodingKey { case consentReads, deviceReads }
    private enum ServingKeys: String, CodingKey { case earliestPoint }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let signals = try? container.nestedContainer(keyedBy: SignalKeys.self, forKey: .signals)
        consentReads = (try? signals?.decodeIfPresent(Bool.self, forKey: .consentReads)) ?? true
        deviceReads = (try? signals?.decodeIfPresent(Bool.self, forKey: .deviceReads)) ?? true
        let serving = try? container.nestedContainer(keyedBy: ServingKeys.self, forKey: .serving)
        earliestPoint = (try? serving?.decodeIfPresent(Bool.self, forKey: .earliestPoint)) ?? false
        // A TTL outside 1 s to the 5-minute cache is a bad value, not a policy: keep the default.
        if let ttl = try? container.decodeIfPresent(Double.self, forKey: .serveHandleTtlSeconds), (1...OffersCache.cacheTTL).contains(ttl) {
            handleTtlSeconds = ttl
        }
    }

    static let storageKey = "encore.serve_switches"

    /// Saved on each `/config`, so a switch turned off holds from the next launch's first request.
    private static let stored = Atomic(
        UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ServeSwitches.self, from: $0) } ?? ServeSwitches()
    )

    /// The switches from the last `/config`, else the defaults.
    static var current: ServeSwitches { stored.value }

    static func update(_ switches: ServeSwitches) {
        guard switches != stored.value else { return }
        stored.value = switches
        if let data = try? JSONEncoder().encode(switches) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    #if DEBUG
    static func resetForTesting() {
        stored.value = ServeSwitches()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    #endif
}
