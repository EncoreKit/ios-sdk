// Sources/Encore/Core/Canonical/User/UserManager.swift
//
// Manages user identity and attributes.
// Single source of truth for "who is logged in".
// Handles business logic; delegates data operations to repository.

import Foundation
import StoreKit
import UIKit

// MARK: - User Manager

/// Domain manager for user identity.
/// - Handles business logic (validation, state transitions, side effects)
/// - Delegates data operations to repository (local + remote)
/// - Does NOT know about analytics/errors — Encore facade handles those
internal final class UserManager {
    
    private let repository: UserRepository
    
    // MARK: - Init
    
    init(repository: UserRepository) {
        self.repository = repository
        repository.migrateLegacyLanguage()
        Logger.debug(.user, "UserManager initialized with userId: \(repository.getUserId())")
    }
    
    // MARK: - Computed Properties
    
    var currentUserId: String {
        repository.getUserId()
    }
    
    /// Persistent person-level identifier. On iOS, backed by Apple's appTransactionID.
    /// Cross-device, cross-session, survives reinstalls. Nil on iOS <16 or if unresolved.
    var appAccountId: String? {
        repository.getAppAccountId()
    }
    
    /// Directly set appAccountId. Exposed for `@testable` test injection.
    func setAppAccountId(_ id: String) {
        repository.setAppAccountId(id)
    }
    
    /// Post-init async setup. Resolves persistent identifiers (e.g. appAccountId via StoreKit).
    func configure() {
        guard appAccountId == nil else { 
            Logger.debug(.user, "appAccountId is set so returning \(appAccountId)")
            return 
        }
        
        if #available(iOS 16.0, *) {
            Task {
                do {
                    let result = try await AppTransaction.shared
                    if case .verified(let appTransaction) = result,
                       let id = Self.extractAppTransactionID(from: appTransaction) {
                        repository.setAppAccountId(id)
                        Logger.debug(.user, "appAccountId resolved")
                        return
                    }
                } catch {
                    Logger.debug(.user, "AppTransaction.shared failed: \(error)")
                }
                
                #if DEBUG
                fallbackToSyntheticId()
                #endif
            }
        }
    }
    
    /// True when the current id is the app's (identify(), or an id the SDK didn't mint);
    /// false for the SDK's own anonymous id and after reset(). Gates the prize promise.
    var isIdentified: Bool {
        repository.isIdentified()
    }

    /// The user's attributes: what syncs to the server. Never holds a language.
    var userAttributes: UserAttributes {
        repository.getAttributes() ?? UserAttributes()
    }

    /// The host's language override, or nil to follow the device language.
    var language: String? {
        repository.getLanguageOverride()
    }

    /// The attributes an /offers request carries: the user's, plus the override
    /// as the explicit locale.
    var requestAttributes: UserAttributes {
        userAttributes.withLanguage(language)
    }
    
    // MARK: - Identity Operations
    
    /// Identify user. Returns whether anything changed (userId or attributes).
    /// A language in `attributes` is dropped: the facade forwards it to `setLanguage`.
    @discardableResult
    func identify(userId: String, attributes: UserAttributes? = nil) -> Bool {
        let attributes = attributes?.withLanguage(nil)
        let previousUserId = currentUserId
        let userIdChanged = previousUserId != userId
        let effectiveAttributes = attributes.map { userAttributes.merged(with: $0) } ?? userAttributes
        let attributesChanged = userAttributes != effectiveAttributes
        // Before the duplicate check: an app id shaped like the SDK's (an uppercase
        // UUID) counts only through this bit, even when re-identified with the same id.
        repository.markIdentified()

        guard userIdChanged || attributesChanged else {
            Logger.debug(.user, "Skipping duplicate identify for userId=\(userId)")
            return false
        }

        if userIdChanged {
            Logger.debug(.user, "User changed '\(previousUserId)' → '\(userId)'")
        }

        // Delegate data operation to repository (handles local + remote)
        repository.identify(currentUserId: previousUserId, newUserId: userId, attributes: attributes)

        return true
    }

    /// Merge new attributes into current. Returns merged result, or nil if nothing changed.
    /// A language in `attributes` is dropped, as in `identify`.
    @discardableResult
    func setAttributes(_ attributes: UserAttributes) -> UserAttributes? {
        let current = userAttributes
        let merged = current.merged(with: attributes.withLanguage(nil))

        guard current != merged else {
            Logger.debug(.user, "Skipping duplicate setAttributes (no changes)")
            return nil
        }

        repository.updateAttributes(merged)
        return merged
    }
    
    // MARK: - Language

    /// Sets the override to `tag` in BCP 47 form. Returns whether it changed;
    /// an invalid tag changes nothing.
    @discardableResult
    func setLanguage(_ tag: String) -> Bool {
        guard let normalized = LanguageTag.normalized(tag), normalized != language else { return false }
        repository.setLanguageOverride(normalized)
        return true
    }

    /// Drops the override. Returns whether one was set.
    @discardableResult
    func clearLanguage() -> Bool {
        guard language != nil else { return false }
        repository.setLanguageOverride(nil)
        return true
    }

    /// Reset to anonymous user. Returns new anonymous userId.
    @discardableResult
    func reset() -> String {
        repository.clearAll()
        let newUserId = repository.getUserId()
        Logger.debug(.user, "Reset to anonymous user: \(newUserId)")
        return newUserId
    }
    
    // MARK: - Private
    
    /// Extract appTransactionID from AppTransaction's JSON payload.
    /// Uses jsonRepresentation (iOS 16+) since the typed property requires Xcode 16.4+ SDK.
    // TODO: Replace with `appTransaction.appTransactionID` when minimum Xcode is 16.4+
    @available(iOS 16.0, *)
    private static func extractAppTransactionID(from appTransaction: AppTransaction) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: appTransaction.jsonRepresentation) as? [String: Any],
              let id = json["appTransactionId"] as? String else {
            return nil
        }
        return id
    }
    
    #if DEBUG
    /// Synthetic fallback for Xcode/simulator builds where AppTransaction has no appTransactionId.
    /// Uses identifierForVendor for a stable-per-device ID so NCL flows are testable locally.
    private func fallbackToSyntheticId() {
        let syntheticId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        repository.setAppAccountId(syntheticId)
        Logger.warn(.user, "appAccountId unavailable — using synthetic DEBUG fallback \(syntheticId)")
    }
    #endif
}
