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
    
    /// Current user ID for event attribution. Atomic for thread-safe access.
    private let userId = Atomic<String?>(nil)

    /// Snake_case keys + standardized date encoding (shared with JSONCoding)
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = JSONCoding.encoder.dateEncodingStrategy
        return encoder
    }()
    
    // MARK: - Initialization
    
    init(sinks: [AnalyticsSink], sdkVersion: String, appBundleId: String) {
        self.sinks = sinks
        self.sdkVersion = sdkVersion
        self.appBundleId = appBundleId
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
}
