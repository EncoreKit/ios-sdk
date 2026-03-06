// Sources/Encore/Core/Configuration/Remote/RemoteConfigurationRepository.swift
//
// Repository for remote configuration data access.
// Handles both network (remote) and local persistence.
// Owns semantic storage keys (what to store), delegates mechanism to KeyValueStore (how to store).

import Foundation

// MARK: - Remote Configuration Repository

/// Repository for remote configuration data access.
/// Provides explicit `getLocal()` and `fetchRemote()` methods so the Manager
/// can make informed decisions about caching and latest-identity-wins coordination.
internal struct RemoteConfigurationRepository: Sendable {
    private let client: HTTPClientProtocol
    private let storage: KeyValueStore
    
    // MARK: - Storage Keys (Repository owns the schema)
    private enum Keys {
        static let config = "encore.remote_config"
    }
    
    init(client: HTTPClientProtocol, storage: KeyValueStore) {
        self.client = client
        self.storage = storage
    }
    
    // MARK: - Local Access (Sync, Disk/Cache)
    
    /// Get configuration from local storage.
    /// Synchronous - returns immediately from cache.
    func getLocal() -> RemoteConfiguration? {
        storage.load(Keys.config)
    }
    
    /// Save configuration to local storage.
    func saveLocal(_ config: RemoteConfiguration) {
        storage.save(config, to: Keys.config)
    }
    
    /// Clear configuration from local storage.
    func clearLocal() {
        storage.remove(Keys.config)
    }
    
    // MARK: - Remote Access (Async, Network)
    
    /// Fetch configuration from remote server.
    ///
    /// Asynchronous - hits network. Does NOT auto-save to local storage;
    /// Manager controls persistence due to latest-identity-wins coordination.
    ///
    /// - Parameters:
    ///   - userId: User ID for deterministic variant assignment
    ///   - sdkVersion: SDK version for compatibility filtering
    /// - Returns: Domain model with UI, entitlements, and experiments config
    func fetchRemote(userId: String, sdkVersion: String) async throws -> RemoteConfiguration {
        let dto: DTO.RemoteConfig.ConfigResponse = try await client.request(
            path: "config",
            method: "GET",
            query: ["userId": userId, "sdkVersion": sdkVersion]
        )
        return RemoteConfiguration(from: dto)
    }
}
