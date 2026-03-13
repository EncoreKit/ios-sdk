// Sources/Encore/Encore.swift
//
// The public facade for the Encore SDK.
// Thin wrapper that delegates to domain managers.

import UIKit
import Combine
import StoreKit
import SwiftUI

// MARK: - Encore Protocol

/// Public API contract for the Encore SDK.
/// All methods are safe to call from any thread.
public protocol EncoreProtocol: AnyObject {
    @available(*, deprecated, message: "Use your subscription manager's entitlement listeners instead")
    var entitlementsDelegate: EncoreDelegate? { get set }
    var placements: PlacementsManager { get }

    func configure(apiKey: String, logLevel: Encore.LogLevel)
    func identify(userId: String, attributes: UserAttributes?)
    func setUserAttributes(_ attributes: UserAttributes)
    func reset()

    func placement(_ id: String?) -> any PlacementBuilderProtocol

    func isActive(_ type: Entitlement, in scope: EntitlementScope) async -> Bool
    func isActivePublisher(for type: Entitlement, in scope: EntitlementScope) -> AnyPublisher<Bool, Never>

    func revokeEntitlements() async throws
    func revokeEntitlements(onCompletion: @escaping (Result<Void, EncoreError>) -> Void)

    @discardableResult
    func onPurchaseRequest(_ handler: @escaping (PurchaseRequest) async throws -> Void) -> Self
    @discardableResult
    func onPurchaseComplete(_ handler: @escaping (StoreKit.Transaction, String) async -> Void) -> Self
    @discardableResult
    func onPassthrough(_ handler: @escaping (String?) -> Void) -> Self
}

// MARK: - Encore SDK Facade

/// Main entry point for the Encore SDK.
///
/// Access via `Encore.shared`. Configure early in app lifecycle,
/// identify users after auth, then present offers via `placement(_:).show()`.
///
/// Thread Safety: All public methods can be called from any thread.
/// UI presentation (`show()`) automatically dispatches to main thread.
public final class Encore: EncoreProtocol {
    internal static let sdkVersion: String = "1.4.37"
    internal var configuration: Configuration?
    internal var services: ServiceContainer?
    internal var lifecycle: AppLifecycle?
    
    public static let shared = Encore()
    
    /// Delegate for entitlement change notifications.
    @available(*, deprecated, message: "Use your subscription manager's entitlement listeners instead")
    public weak var entitlementsDelegate: EncoreDelegate? {
        didSet { services?.entitlements.delegate = entitlementsDelegate }
    }
    
    /// Global listener for all placement events. Instance-scoped (survives `reset()`).
    public private(set) lazy var placements = PlacementsManager()

    /// Delegate for handling purchases via 3rd party subscription managers (RevenueCat, etc.).
    /// App-level infrastructure — NOT cleared on `reset()`.
    internal var purchaseRequestHandler: ((PurchaseRequest) async throws -> Void)?

    /// Fires after a successful StoreKit fallback purchase. Use to sync with 3P managers that
    /// don't auto-detect StoreKit transactions (e.g., Adapty.reportTransaction, Qonversion.syncStoreKit2Purchases).
    /// Only fires when no onPurchaseRequest handler is set and Encore handles the purchase via native StoreKit.
    /// App-level infrastructure — NOT cleared on `reset()`.
    internal var purchaseCompleteHandler: ((StoreKit.Transaction, String) async -> Void)?

    /// Fires for all not-granted outcomes (dismiss, no offers, experiment control, unsupported OS).
    /// Signals "Encore didn't result in a purchase, run your original button logic."
    /// App-level infrastructure — NOT cleared on `reset()`.
    internal var passthroughHandler: ((String?) -> Void)?

    private init() {}
    
    // MARK: - Configuration
    
    /// Configures the SDK with your API key. Call once, early in app lifecycle.
    public func configure(apiKey: String, logLevel: LogLevel = .none) {
        guard services == nil else {
            Logger.warn("SDK already configured. Ignoring duplicate configure() call.")
            return
        }
        guard !apiKey.isEmpty else {
            Logger.error(.integration(.invalidApiKey), context: .configuration)
            return
        }
        
        let config = Configuration(apiKey: apiKey, logLevel: logLevel)
        self.configuration = config
        self.lifecycle = AppLifecycle()
        let container = ServiceContainer(configuration: config)
        self.services = container
        container.entitlements.delegate = entitlementsDelegate
        
        // Set initial userId for infrastructure (UserManager ensures userId exists)
        let initialUserId = container.user.currentUserId
        container.remoteConfigManager.fetch(userId: initialUserId, sdkVersion: Encore.sdkVersion)
        container.analytics.identifyUser(userId: initialUserId, attributes: container.user.userAttributes)
        container.errors.setUserId(initialUserId)
        container.analytics.track(
            SDKInitializedEvent(sdkVersion: Encore.sdkVersion, appBundleId: config.appBundleId),
            distinctId: config.appBundleId
        )
        Logger.info("SDK configured for \(config.environment) | apiKey: \(String(config.apiKey.prefix(20)))... | baseURL: \(config.environment.apiBaseURL)")
    }
    
    // MARK: - User Identity
    
    /// Associates a user ID with SDK events and entitlements.
    public func identify(userId: String, attributes: UserAttributes? = nil) {
        guard let userManager = userManager,
              let entitlementsManager = entitlementsManager,
              let remoteConfigManager = remoteConfigManager,
              let analyticsClient = analyticsClient,
              let errorsClient = errorsClient else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        
        let previousUserId = userManager.currentUserId
        let changed = userManager.identify(userId: userId, attributes: attributes)
        guard changed else { return }

        remoteConfigManager.fetch(userId: userId, sdkVersion: Encore.sdkVersion)
        analyticsClient.identifyUser(userId: userManager.currentUserId, attributes: userManager.userAttributes)
        errorsClient.setUserId(userManager.currentUserId)
        if previousUserId != userId {
            entitlementsManager.reset(thenRefresh: true)
        }
    }
    
    /// Merges new attributes into the current user's profile.
    public func setUserAttributes(_ attributes: UserAttributes) {
        guard let userManager = userManager,
              let analyticsClient = analyticsClient else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        
        guard let mergedAttributes = userManager.setAttributes(attributes) else { return }
        analyticsClient.identifyUser(userId: userManager.currentUserId, attributes: mergedAttributes)
    }
    
    /// Clears user data and generates a new anonymous ID. Call on logout.
    public func reset() {
        guard let userManager = userManager,
              let remoteConfigManager = remoteConfigManager,
              let analyticsClient = analyticsClient,
              let errorsClient = errorsClient,
              let entitlementsManager = entitlementsManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        
        remoteConfigManager.clearCache()
        entitlementsManager.reset()
        let newUserId = userManager.reset()

        remoteConfigManager.fetch(userId: newUserId, sdkVersion: Encore.sdkVersion)
        analyticsClient.identifyUser(userId: newUserId, attributes: UserAttributes())
        errorsClient.setUserId(newUserId)
    }
    
    // MARK: - Placements
    
    /// Creates a placement builder for presenting offers.
    public func placement(_ id: String? = nil) -> any PlacementBuilderProtocol {
        let placementId = id ?? "placement_\(UUID().uuidString.prefix(8))"
        return PlacementBuilder(id: placementId)
    }
    
    /// Static convenience for `Encore.shared.placement(_:)`.
    public static func placement(_ id: String? = nil) -> any PlacementBuilderProtocol {
        shared.placement(id)
    }

    // MARK: - Entitlement Queries
    
    /// Checks if an entitlement is active. Auto-refreshes from server if needed.
    public func isActive(_ type: Entitlement, in scope: EntitlementScope = .all) async -> Bool {
        guard let entitlementsManager = entitlementsManager else { 
            Logger.error(.integration(.notConfigured), context: .configuration)
            return false 
        }
        await entitlementsManager.smartRefresh(for: type, scope: scope, entitlements: entitlementsManager.entitlements)
        guard let entitlements = entitlementsManager.entitlements else { return false }
        return EntitlementManager.isActive(type, scope: scope, in: entitlements)
    }
    
    /// Publisher that emits when entitlement state changes.
    public func isActivePublisher(for type: Entitlement, in scope: EntitlementScope = .all) -> AnyPublisher<Bool, Never> {
        guard let manager = entitlementsManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return Just(false).eraseToAnyPublisher()
        }
        
        return manager.$entitlements
            .receive(on: DispatchQueue.main)
            .map { entitlements in
                guard let entitlements else { return false }
                return EntitlementManager.isActive(type, scope: scope, in: entitlements)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Entitlement Management
    
    /// Revokes all entitlements for the current user. Admin/debug only.
    public func revokeEntitlements() async throws {
        guard let manager = entitlementsManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            throw EncoreError.integration(.notConfigured)
        }
        try await manager.revokeEntitlements()
    }
    
    // MARK: - Presentation Delegation

    /// Registers a handler invoked when Encore's offer flow triggers a purchase.
    /// Receives a ``PurchaseRequest`` with product ID, placement, and optional promotional offer context.
    ///
    /// **Simple (most apps):**
    /// ```swift
    /// Encore.shared.onPurchaseRequest { request in
    ///     try await Purchases.shared.purchase(request.productId)
    /// }
    /// ```
    ///
    /// **With promotional offer support:**
    /// ```swift
    /// Encore.shared.onPurchaseRequest { request in
    ///     if let promoOfferId = request.promoOfferId {
    ///         let offer = try await Purchases.shared.promotionalOffer(...)
    ///         try await Purchases.shared.purchase(product, promotionalOffer: offer)
    ///     } else {
    ///         try await Purchases.shared.purchase(request.productId)
    ///     }
    /// }
    /// ```
    @discardableResult
    public func onPurchaseRequest(_ handler: @escaping (PurchaseRequest) async throws -> Void) -> Encore {
        self.purchaseRequestHandler = handler
        return self
    }

    /// Registers a callback invoked after Encore completes a native StoreKit purchase.
    /// Only fires when no `onPurchaseRequest` handler is set.
    /// Use this to sync the transaction with subscription managers that don't auto-detect
    /// StoreKit transactions (e.g., Adapty, Qonversion).
    ///
    /// ```swift
    /// Encore.shared.onPurchaseComplete { transaction, productId in
    ///     try? await Adapty.reportTransaction(transaction)
    /// }
    /// ```
    @discardableResult
    public func onPurchaseComplete(_ handler: @escaping (StoreKit.Transaction, String) async -> Void) -> Encore {
        self.purchaseCompleteHandler = handler
        return self
    }

    /// Registers a handler invoked for all not-granted outcomes (dismiss, no offers, experiment control, unsupported OS).
    /// Signals "Encore didn't result in a purchase — run your original button logic."
    ///
    /// ```swift
    /// Encore.shared.onPassthrough { placementId in
    ///     router.handleOriginalAction(for: placementId)
    /// }
    /// ```
    @discardableResult
    public func onPassthrough(_ handler: @escaping (String?) -> Void) -> Encore {
        self.passthroughHandler = handler
        return self
    }

    /// Callback variant of `revokeEntitlements()`.
    public func revokeEntitlements(onCompletion: @escaping (Result<Void, EncoreError>) -> Void) {
        Task {
            do {
                try await revokeEntitlements()
                onCompletion(.success(()))
            } catch let error as EncoreError {
                onCompletion(.failure(error))
            } catch {
                onCompletion(.failure(.transport(.network(error))))
            }
        }
    }
}
