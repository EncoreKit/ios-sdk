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
    private let transactionLinking: Bool
    private let appTransaction: AppTransactionReading
    private let runsOnSimulator: Bool
    private let syntheticId: @MainActor () -> String

    // MARK: - Init

    init(
        repository: UserRepository,
        transactionLinking: Bool = true,
        appTransaction: AppTransactionReading = StoreKitAppTransactionReader(),
        runsOnSimulator: Bool = UserManager.runsOnSimulator,
        syntheticId: @escaping @MainActor () -> String = { UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString }
    ) {
        self.repository = repository
        self.transactionLinking = transactionLinking
        self.appTransaction = appTransaction
        self.runsOnSimulator = runsOnSimulator
        self.syntheticId = syntheticId
        repository.migrateLegacyLanguage()
        Logger.debug(.user, "UserManager initialized with userId: \(repository.getUserId())")
    }
    
    // MARK: - Computed Properties
    
    var currentUserId: String {
        repository.getUserId()
    }
    
    /// Persistent person-level identifier. On iOS, backed by Apple's appTransactionID.
    /// Cross-device, cross-session, survives reinstalls. Nil on iOS <16, if unresolved,
    /// or always when `transactionLinking` is off (the gate does not rely on the storage clear).
    var appAccountId: String? {
        transactionLinking ? repository.getAppAccountId() : nil
    }

    /// The key NCL cohorts hash: the app account id, or the user id only when linking is off.
    var personKey: String? {
        transactionLinking ? appAccountId : currentUserId
    }

    /// Directly set appAccountId. Exposed for `@testable` test injection.
    func setAppAccountId(_ id: String) {
        repository.setAppAccountId(id)
    }
    
    /// Whether this process runs on a Simulator, where StoreKit's app transaction read raises a
    /// system sign-in prompt over the app when no Apple Account is signed in.
    static var runsOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Resolves appAccountId once, never prompting: a Simulator never asks StoreKit (DEBUG takes the
    /// synthetic id) and a device reads only `AppTransaction.shared` (see `StoreKitAppTransactionReader`).
    /// Linking off only removes an id an older build stored. Returns the read in flight (for tests).
    @discardableResult
    func configure() -> Task<Void, Never>? {
        guard transactionLinking else {
            repository.setAppAccountId(nil)
            return nil
        }
        guard appAccountId == nil else {
            Logger.debug(.user, "appAccountId already resolved")
            return nil
        }
        if runsOnSimulator {
            #if DEBUG
            return Task { @MainActor in self.fallbackToSyntheticId() }
            #else
            return nil
            #endif
        }
        let (reader, repository) = (appTransaction, repository)
        return Task {
            if let id = await reader.appTransactionId() {
                repository.setAppAccountId(id)
                Logger.debug(.user, "appAccountId resolved")
                return
            }
            #if DEBUG
            await self.fallbackToSyntheticId()
            #endif
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
    
    /// Whether `identify(userId)` is another signed-in user taking over: switched, never aliased.
    func replacesIdentifiedUser(with userId: String) -> Bool {
        isIdentified && userId != currentUserId
    }

    /// Identify user. Returns whether anything changed (userId or attributes).
    /// A language in `attributes` is dropped: the facade forwards it to `setLanguage`.
    @discardableResult
    func identify(userId: String, attributes: UserAttributes? = nil) -> Bool {
        let attributes = attributes?.withLanguage(nil)
        let previousUserId = currentUserId
        if replacesIdentifiedUser(with: userId) {
            Logger.debug(.user, "Signed-in user changed '\(previousUserId)' → '\(userId)': switching, no alias")
            repository.switchUser(to: userId, attributes: attributes)
            return true
        }
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
    
    #if DEBUG
    /// Synthetic fallback for Simulator and Xcode builds with no app transaction: identifierForVendor,
    /// stable per device, so NCL flows are testable locally. Never in a Release build.
    @MainActor
    private func fallbackToSyntheticId() {
        let id = syntheticId()
        repository.setAppAccountId(id)
        Logger.warn(.user, "appAccountId unavailable: using the synthetic DEBUG fallback \(id)")
    }
    #endif
}

// MARK: - App transaction

/// Reads the app transaction's id without ever prompting. The seam has no refresh on purpose.
internal protocol AppTransactionReading: Sendable {
    /// The App Store-signed app transaction's `appTransactionId`, or nil when there is none, it is
    /// unverified, or the read fails.
    func appTransactionId() async -> String?
}

/// `AppTransaction.shared` only. Apple documents that it throws when the app transaction is not
/// available or the user is not authenticated with the App Store; `AppTransaction.refresh()` is
/// the call that shows a sign-in prompt, and this SDK never makes it.
internal struct StoreKitAppTransactionReader: AppTransactionReading {
    func appTransactionId() async -> String? {
        guard #available(iOS 16.0, *) else { return nil }
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else { return nil }
            return Self.appTransactionId(in: transaction.jsonRepresentation)
        } catch {
            Logger.debug(.user, "AppTransaction.shared failed: \(error)")
            return nil
        }
    }

    /// `appTransactionId` from the transaction's JSON (the typed property needs the iOS 18.4 SDK).
    static func appTransactionId(in json: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["appTransactionId"] as? String
    }
}
