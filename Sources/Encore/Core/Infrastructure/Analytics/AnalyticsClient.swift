//
//  Analytics.swift
//  Encore
//
//  Analytics client that routes events to registered sinks.
//  Stores userId for automatic event attribution.
//

import Foundation

// MARK: - Analytics Client

/// Analytics client for tracking Encore SDK events.
/// Stores userId so callers don't need to pass it for every event.
internal final class AnalyticsClient {

    // MARK: - Properties

    private let sinks: [AnalyticsSink]
    private let sdkVersion: String
    private let appBundleId: String
    private let dedupStorage: KeyValueStore?

    /// Current user ID for event attribution. Atomic for thread-safe access.
    private let userId = Atomic<String?>(nil)

    /// Snake_case keys + standardized date encoding (shared with JSONCoding)
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = JSONCoding.encoder.dateEncodingStrategy
        return encoder
    }()

    /// Events throttled to one emit per distinct_id per `dedupTTL`. The 30-day
    /// audit (Apr 2026) flagged user_identified at 16% of total event volume —
    /// pure per-session repeat noise. Mirror of the backend ingest filter.
    private static let dedupedEventNames: Set<String> = [
        UserIdentifiedEvent.eventName,
    ]

    /// Per-event dedup window. 24h matches the audit recommendation (#2).
    private static let dedupTTL: TimeInterval = 24 * 60 * 60

    private static let dedupKeyPrefix = "analytics_dedup_"

    // MARK: - Initialization

    init(sinks: [AnalyticsSink], sdkVersion: String, appBundleId: String, dedupStorage: KeyValueStore? = nil) {
        self.sinks = sinks
        self.sdkVersion = sdkVersion
        self.appBundleId = appBundleId
        self.dedupStorage = dedupStorage
    }
    
    // MARK: - Encoding Helper
    
    /// Encode any Encodable to a snake_cased dictionary
    private func encode<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? Self.encoder.encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    // MARK: - Event Tracking
    
    /// Track a typed analytics event. Uses stored userId if distinctId not provided.
    func track<T: AnalyticsEvent>(_ event: T, distinctId: String? = nil) {
        let resolvedId: String
        if let id = distinctId ?? userId.value, !id.isEmpty {
            resolvedId = id
        } else {
            resolvedId = "anonymous"
            Logger.warn("[Analytics] No distinctId or userId available — using 'anonymous'")
        }

        if shouldDedup(eventName: T.eventName, distinctId: resolvedId) {
            return
        }

        guard let properties = encode(event) else {
            Logger.error(.protocol(.decoding(EncodingError.invalidValue(event, .init(codingPath: [], debugDescription: "Failed to encode \(T.eventName)")))), context: .analytics)
            return
        }
        
        var metadata: [String: String] = [
            "platform": "ios",
            "sdk_version": sdkVersion,
            "app_bundle_id": appBundleId,
        ]
        if let appAccountId = userManager?.appAccountId {
            metadata["app_account_id"] = appAccountId
        }
        
        let envelope = EventEnvelope(
            eventName: T.eventName,
            distinctId: resolvedId,
            properties: properties,
            metadata: metadata
        )
        
        // Send to all sinks concurrently
        for sink in sinks {
            Task.detached(priority: .utility) { [sink, envelope] in
                await sink.log(event: envelope)
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Identify a user with their attributes.
    ///
    /// **Synchronous:** Ensures user profile is set up before subsequent `track()` calls.
    /// This guarantees events are properly associated with the user.
    func identifyUser(userId: String, attributes: UserAttributes) {
        // Store userId atomically for future events
        self.userId.value = userId
        
        // Encode attributes for PostHog identify
        var userProperties = encode(attributes) ?? [:]
        userProperties["user_id"] = userId
        userProperties["app_bundle_id"] = appBundleId
        
        // Call identify on sinks synchronously (establishes user profile first)
        for sink in sinks {
            sink.identify(userId: userId, userProperties: userProperties)
        }
        
        // Track the identification event
        track(UserIdentifiedEvent(userId: userId, attributes: attributes))
    }

    // MARK: - Dedup

    /// Returns true when an event should be skipped because it fired for the
    /// same distinct_id within the last `dedupTTL`. Keeps a sliding window:
    /// each kept emit resets the next-eligible time. Fail-open on any storage
    /// error — over-emit is far cheaper than dropping signal.
    private func shouldDedup(eventName: String, distinctId: String) -> Bool {
        guard let storage = dedupStorage,
              Self.dedupedEventNames.contains(eventName) else { return false }

        let key = "\(Self.dedupKeyPrefix)\(eventName)_\(distinctId)"
        let now = Date().timeIntervalSince1970

        if let last: TimeInterval = storage.load(key), now - last < Self.dedupTTL {
            return true
        }

        storage.save(now, to: key)
        return false
    }
}
