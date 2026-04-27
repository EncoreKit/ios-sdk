// Sources/Encore/Core/Configuration/Remote/RemoteConfigurationManager.swift
//
// Manages remote configuration state.
// Handles latest-identity-wins coordination and exposes config to consumers.
// Storage concerns delegated to repository.

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
    
    // MARK: - Initialization
    
    init(repository: RemoteConfigurationRepository) {
        self.repository = repository
        
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
    func fetch(userId: String, sdkVersion: String) {
        Logger.debug("🔄 [RemoteConfig] Starting fetch for userId=\(userId), hasExistingConfig=\(config != nil)")
        inFlightTask?.cancel()
        inFlightTask = Task {
            let startTime = Date()
            var loadSource = "remote"
            
            do {
                let result = try await repository.fetchRemote(userId: userId, sdkVersion: sdkVersion)
                
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
        analyticsClient?.track(SDUIConfigLoadedEvent(
            variant: SDUIVariantContext(variantId: config?.ui.variantId),
            loadSource: loadSource,
            loadDurationMs: loadDurationMs
        ))
    }
}
