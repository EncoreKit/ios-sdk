// Sources/Encore/Core/Configuration/Remote/RemoteConfigurationManager.swift
//
// Manages remote configuration state.
// Handles latest-identity-wins coordination and exposes config to consumers.
// Storage concerns delegated to repository.

import CryptoKit
import Foundation

/// Manages remote configuration fetched from the backend.
///
/// Single source of truth for remote configuration data.
/// - Latest-identity-wins coordination (task cancellation)
/// - Delegates storage to repository
/// - Tracks config fetch analytics
/// - Thread-safe config access via Atomic wrapper
class RemoteConfigurationManager {

    // MARK: - Properties

    private let repository: RemoteConfigurationRepository
    private let dedupStorage: KeyValueStore?

    /// In-flight fetch task. Cancelled when a new fetch is triggered.
    private var inFlightTask: Task<Void, Never>?

    /// Thread-safe cached configuration from the last successful fetch or disk load
    private let _config = Atomic<RemoteConfiguration?>(nil)

    /// Current configuration snapshot (thread-safe read)
    var config: RemoteConfiguration? { _config.value }

    // MARK: - Convenience Accessors

    var ui: UIConfiguration? { config?.ui }
    var entitlements: EntitlementConfiguration? { config?.entitlements }
    var experiments: ExperimentConfiguration? { config?.experiments }
    var iapProductId: String? { entitlements?.iapProductId }
    var usesIAPMode: Bool { entitlements?.usesIAPMode ?? false }

    // MARK: - Constants

    /// UserDefaults key for the last-emitted config-content hash. Per the
    /// 2026 analytics audit (#4), sdk_sdui_config_loaded should fire only on
    /// hash change — repeat loads of an identical config are noise.
    private static let lastEmittedHashKey = "analytics_dedup_sdui_config_loaded_hash"

    // MARK: - Initialization

    init(repository: RemoteConfigurationRepository, dedupStorage: KeyValueStore? = nil) {
        self.repository = repository
        self.dedupStorage = dedupStorage

        // Load last-known-good config from disk (instant availability)
        if let cached = repository.getLocal() {
            _config.value = cached
            Logger.info("📦 [RemoteConfig] Loaded cached config from disk: variantId=\(cached.ui.variantId ?? "nil")")
        } else {
            Logger.debug("🔍 [RemoteConfig] No cached config on disk")
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetches remote configuration. Fire-and-forget — cancels any in-flight request (latest identity wins).
    /// `language` overrides device locale on the backend when non-nil; pass
    /// `userManager.userAttributes?.language` from callers so an in-app picker
    /// is the single source of truth.
    func fetch(userId: String, sdkVersion: String, language: String? = nil) {
        Logger.debug("🔄 [RemoteConfig] Starting fetch for userId=\(userId), language=\(language ?? "device"), hasExistingConfig=\(config != nil)")
        inFlightTask?.cancel()
        inFlightTask = Task {
            let startTime = Date()
            var loadSource = "remote"

            do {
                let result = try await repository.fetchRemote(userId: userId, sdkVersion: sdkVersion, language: language)
                
                guard !Task.isCancelled else {
                    Logger.info("🔄 [RemoteConfig] Discarding stale result (newer identity)")
                    return
                }
                
                _config.value = result
                repository.saveLocal(result)
                Logger.info("✅ [RemoteConfig] Fetched: variantId=\(result.ui.variantId ?? "none")")
            } catch {
                if Task.isCancelled {
                    Logger.info("🔄 [RemoteConfig] Fetch cancelled (newer identity)")
                    return
                }
                Logger.warn("⚠️ [RemoteConfig] Fetch failed: \(error.localizedDescription)")
                loadSource = config != nil ? "cache" : "fallback"
            }
            
            // Track analytics
            let duration = Date().timeIntervalSince(startTime) * 1000
            trackConfigLoaded(loadSource: loadSource, loadDurationMs: duration)
        }
    }
    
    /// Clears all cached configuration (memory + disk). Called on user logout/reset.
    func clearCache() {
        inFlightTask?.cancel()
        inFlightTask = nil
        _config.value = nil
        repository.clearLocal()
        Logger.info("🗑️ [RemoteConfig] Cache cleared (memory + disk)")
    }
    
    // MARK: - Analytics

    private func trackConfigLoaded(loadSource: String, loadDurationMs: Double) {
        // Suppress emits when the loaded config matches what we already
        // reported. Audit (Apr 2026, #4) showed this event was firing on
        // every fetch regardless of whether the content actually changed,
        // contributing 9.6% of total event volume for zero product signal.
        if let hash = currentConfigHash(), shouldSuppressLoadedEvent(hash: hash) {
            return
        }

        analyticsClient?.track(SDUIConfigLoadedEvent(
            variant: SDUIVariantContext(variantId: config?.ui.variantId),
            loadSource: loadSource,
            loadDurationMs: loadDurationMs
        ))
    }

    /// SHA-256 of the current `RemoteConfiguration` JSON encoding. Stable
    /// across runs because we use a sorted-keys encoder. Returns nil when
    /// no config is loaded (no event to dedup against in that case).
    private func currentConfigHash() -> String? {
        guard let config = _config.value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(config) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns true when the new hash matches the last-emitted one, in which
    /// case the event is dropped. On a hash change (or first load), records
    /// the new hash and returns false. Fail-open if storage is unavailable.
    private func shouldSuppressLoadedEvent(hash: String) -> Bool {
        guard let storage = dedupStorage else { return false }
        let last: String? = storage.load(Self.lastEmittedHashKey)
        if last == hash {
            return true
        }
        storage.save(hash, to: Self.lastEmittedHashKey)
        return false
    }
}
