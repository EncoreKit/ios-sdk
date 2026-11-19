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
/// Main-actor isolated: call from UI code (button actions, `.task`) — every
/// method is synchronous or `await`-able from there, and results land on main
/// by construction.
@MainActor
public protocol EncoreProtocol: AnyObject {
    /// Controls whether the claim CTA on offer cards is tappable.
    var isClaimEnabled: Bool { get set }

    /// Turns the SDK on or off for this launch. Not persisted: every launch starts on.
    var isEnabled: Bool { get set }

    func configure(apiKey: String, purchaseController: EncorePurchaseController?, options: Encore.Options)
    func identify(userId: String, attributes: UserAttributes?)
    func setUserAttributes(_ attributes: UserAttributes)
    func reset()

    func placement(_ id: String?) -> any PlacementBuilderProtocol

    var outcomes: AsyncStream<PlacementOutcome> { get }

    func isActive(_ type: Entitlement, in scope: EntitlementScope) async -> Bool
    func isActivePublisher(for type: Entitlement, in scope: EntitlementScope) -> AnyPublisher<Bool, Never>

    func revokeEntitlements() async throws
    func revokeEntitlements(onCompletion: @escaping (Result<Void, EncoreError>) -> Void)

    /// Serves Encore's copy in `tag` (BCP 47, e.g. "pt-BR") until cleared, whatever the device language.
    func setLanguage(_ tag: String)

    /// Removes a host-set language so copy follows the device language again.
    func clearLanguage()
}

/// Requirements with defaults, so host conformers written before 2.3.0
/// (test doubles) keep compiling.
public extension EncoreProtocol {
    /// Default: always on, and setting it does nothing. `Encore` implements the real switch.
    var isEnabled: Bool {
        get { true }
        set {}
    }

    /// Default: no-op. `Encore` implements the real set.
    func setLanguage(_ tag: String) {}

    /// Default: no-op. `Encore` implements the real clear.
    func clearLanguage() {}
}

// MARK: - Encore SDK Facade

/// Main entry point for the Encore SDK.
///
/// Access via `Encore.shared`. Configure early in app lifecycle,
/// identify users after auth, then present offers via `placement(_:).moment(_:).show()`.
///
/// Thread Safety: The facade is `@MainActor` — invoke from a main-actor
/// context (SwiftUI button action, `.task`, UIKit handler). Off-main
/// invocation of `show()` would order the sheet arbitrarily against your
/// progressing app UI.
@MainActor
public final class Encore: EncoreProtocol {
    internal static let sdkVersion: String = "2.7.0"
    // Write-once references (assigned in configure(), read pervasively from
    // nonisolated accessors). Safe: Swift reference assignment is atomic and
    // these never change after configuration.
    nonisolated(unsafe) internal var configuration: Configuration?
    nonisolated(unsafe) internal var services: ServiceContainer?
    nonisolated(unsafe) internal var lifecycle: AppLifecycle?

    public static let shared = Encore()

    /// Whether this device can present Encore offers at all — the SDK's iOS 17
    /// floor. Read it BEFORE you commit a surface to a placement: on `false`,
    /// `show()` resolves `.notPresented(.unsupportedOS)` without any UI, so the
    /// host should fall through to its own. Configuration-independent, so it is
    /// safe to read before `configure()`.
    ///
    /// ```swift
    /// guard Encore.isSupported else { showOwnPaywall(); return }
    /// let result = await Encore.placement("paywall_decline").show()
    /// ```
    public nonisolated static var isSupported: Bool {
        if #available(iOS 17.0, *) { true } else { false }
    }

    /// Controls whether the claim CTA on offer cards is tappable.
    /// Set to `false` to gray out and disable the claim button. Runtime-mutable
    /// (not an `Options` field) so hosts can gate claims mid-session, an open sheet included.
    public var isClaimEnabled: Bool = true {
        didSet { claimEnabledChanges.send(isClaimEnabled) }
    }

    /// Every change to `isClaimEnabled`, so an open sheet follows it.
    internal let claimEnabledChanges = PassthroughSubject<Bool, Never>()

    /// Turns the SDK on or off for this launch. Off: no events, no requests, no timers, `show()` resolves
    /// `.notPresented(.disabled)` and triggers draw nothing; a sheet already open finishes. Not persisted:
    /// every launch starts on, so set it at each launch, before or after `configure()`.
    public var isEnabled: Bool {
        get { SDKSwitch.isOn }
        set {
            guard newValue != SDKSwitch.isOn else { return }
            SDKSwitch.isOn = newValue
            Logger.info(.configuration, "SDK turned \(newValue ? "on" : "off")")
            if newValue { turnedOn() } else { turnedOff() }
            // Mounted triggers run their gate again (nothing while off, their offers once on). A regate,
            // not a new person: what they already counted (an impression, the one automatic open) stays.
            NotificationCenter.default.post(name: .encoreTriggerHeldOffersChanged, object: nil)
        }
    }

    /// Purchase mechanism: your ``EncorePurchaseController`` that runs real purchases
    /// through your subscription manager and returns a normalized ``EncorePurchaseResult``.
    /// Set via `configure(apiKey:purchaseController:options:)`. Strong reference (Encore retains it).
    /// Survives `reset()` — build-time wiring, not user state.
    internal var purchaseController: EncorePurchaseController?

    /// Re-prefetches offers for the current user.
    /// Sequenced behind the in-flight /config fetch so the warm-up carries the
    /// variant the server just resolved, not the previous cache (see the same
    /// note in configure()).
    ///
    /// No longer clears the cache first: the cache key carries the identity and
    /// the two attributes `/offers/search` reads functionally, so a change that
    /// moves the offer set misses on its own, and one that cannot (any other
    /// attribute) reuses the set the SDK already holds instead of buying it again.
    private func refetchOffers() {
        Task { [weak self] in
            guard let self, let services = self.services else { return }
            await services.remoteConfigManager.awaitInFlightFetch()
            // Turned off while the config was in flight: no refetch (its search would be refused anyway).
            guard SDKSwitch.isOn else { return }
            #if DEBUG
            Encore.refetchStepObserverForTesting?("offers")
            #endif
            services.offers.prefetch(
                userId: services.user.currentUserId,
                attributes: services.user.requestAttributes,
                variantId: services.remoteConfigManager.ui?.variantId,
                useCase: .reduceChurn
            )
            // Same warm-up as configure() — see the note there.
            if let productId = services.remoteConfigManager.iapProductId {
                _ = await IAPClient.fetchProductInfo(productId: productId)
            }
            guard SDKSwitch.isOn else { return }
            #if DEBUG
            Encore.refetchStepObserverForTesting?("images")
            #endif
            await Self.warmEnabledUseCases(services, userId: services.user.currentUserId)
        }
    }

    /// The launch `/config` fetch and warm-ups, held until the app first becomes active, so a
    /// background launch fetches nothing. They read the current user, so an identify() first is covered.
    internal func scheduleLaunchWarmUp(_ container: ServiceContainer) {
        container.foregroundGate.runWhenOpen { [weak container] in
            // Turned off before the app was first active: the next turn-on warms instead.
            guard let container, SDKSwitch.isOn else { return }
            container.remoteConfigManager.fetch(
                userId: container.user.currentUserId,
                sdkVersion: Encore.sdkVersion,
                language: container.user.language
            )
            // Behind the fetch above: the cached variant id can filter every campaign out server-side.
            Task { [weak container] in
                guard let container else { return }
                await container.remoteConfigManager.awaitInFlightFetch()
                // Turned off while the config was in flight: warm nothing (the StoreKit lookup skips the transport gate).
                guard SDKSwitch.isOn else { return }
                #if DEBUG
                Encore.launchWarmObserverForTesting?()
                #endif
                container.offers.prefetch(
                    userId: container.user.currentUserId,
                    attributes: container.user.requestAttributes,
                    variantId: container.remoteConfigManager.ui?.variantId,
                    useCase: .reduceChurn
                )
                // Warm StoreKit's product cache off the tap path, where a cold lookup was the whole tail.
                if let productId = container.remoteConfigManager.iapProductId {
                    _ = await IAPClient.fetchProductInfo(productId: productId)
                }
                guard SDKSwitch.isOn else { return }
                // Image warm for every other enabled use case, disk gated, so about once per device.
                await Self.warmEnabledUseCases(container, userId: container.user.currentUserId)
            }
        }
    }

    /// Disk-gated image warm for every enabled use case beyond churn, whose
    /// images ride the offers prefetch above. Concurrent per use case; runs
    /// after configure's fetch and again on the identify-time refetch, the
    /// same single path.
    private nonisolated static func warmEnabledUseCases(_ container: ServiceContainer, userId: String) async {
        await withTaskGroup(of: Void.self) { group in
            for useCase in UseCase.allCases where useCase != .reduceChurn {
                guard let ui = container.remoteConfigManager.ui(for: useCase) else { continue }
                group.addTask {
                    await container.offers.warmImagesIfNeeded(
                        useCase: useCase,
                        userId: userId,
                        attributes: container.user.requestAttributes,
                        variantId: ui.variantId
                    )
                }
            }
        }
    }

    private init() {}
    
    // MARK: - Configuration

    /// Configures the SDK with your API key. Call once, early in app lifecycle.
    /// Pass your ``EncorePurchaseController`` if your app sells a product through
    /// Encore offers; with no controller, the SDK never attempts a purchase.
    public func configure(
        apiKey: String,
        purchaseController: EncorePurchaseController? = nil,
        options: Options = .init()
    ) {
        if let purchaseController {
            self.purchaseController = purchaseController
        }
        guard services == nil else {
            Logger.warn("SDK already configured. Ignoring duplicate configure() call.")
            if let purchaseController {
                Logger.info(.iap, "PurchaseController registered: \(type(of: purchaseController))")
            }
            return
        }
        guard !apiKey.isEmpty else {
            Logger.error(.integration(.invalidApiKey), context: .configuration)
            return
        }

        // Before the launch warm-up below, so its search already carries the setting and the connection type.
        if let personalization = options.personalization { Personalization.set(personalization) }
        _ = ConnectionMonitor.shared

        let config = Configuration(
            apiKey: apiKey,
            logLevel: options.logLevel,
            unlock: options.unlock,
            transactionLinking: options.transactionLinking
        )
        self.configuration = config
        self.lifecycle = AppLifecycle()
        let container = ServiceContainer(configuration: config)
        self.services = container
        #if DEBUG
        // The demo app's tester controls for its Gifts to Reminder screen; none in a release build.
        ClaimLogDebugCommands.install()
        TriggerDebugStrings.install()
        #endif
        LegacyPrizeCount.remove()
        CompletedCampaigns.removeLegacyList()
        // Late strict-unlock verification: refresh grants, then surface on outcomes.
        container.strictUnlockReconciler.onVerified = { [weak self] transactionId in
            try? await entitlementsManager?.refreshEntitlements()
            // A user switch during the refresh cancels the pass: the outcome is not this user's.
            guard !Task.isCancelled else { return }
            self?.yieldOutcome(.strictUnlockVerified(transactionId: transactionId))
        }

        // Set initial userId for infrastructure (UserManager ensures userId exists)
        let initialUserId = container.user.currentUserId
        container.errors.setUserId(initialUserId)
        if isEnabled {
            start(container)
        } else {
            // Local state only; the first turn-on starts what configure() would have.
            container.analytics.identifyUser(userId: initialUserId, attributes: container.user.userAttributes)
            Logger.info(.configuration, "SDK is off: configured without starting")
        }
        Logger.info(.configuration, "SDK configured for \(config.environment) (via \(config.environmentSource)) | apiKey: \(String(config.apiKey.prefix(8)))... | baseURL: \(config.environment.apiBaseURL)")
        // An EncoreClaim made before configure loads now.
        NotificationCenter.default.post(name: .encoreDidConfigure, object: nil)
        if let purchaseController {
            Logger.info(.iap, "PurchaseController registered: \(type(of: purchaseController))")
        }
    }

    /// Everything configure() starts: reconciliation, the launch warm-up, `sdk_initialized` and the daily active.
    /// `announce` is false on a turn-on after configure() ran while off: nothing dropped while off is replayed.
    private func start(_ container: ServiceContainer, announce: Bool = true) {
        container.hasStarted = true
        container.strictUnlockReconciler.start()
        scheduleLaunchWarmUp(container)
        if let lifecycle {
            let launchedInBackground = ForegroundGate.launchedInBackground
            Logger.debug(.configuration, "Launch warm-up \(launchedInBackground ? "held until the app is first active" : "starting now")")
            container.foregroundGate.start(launchedInBackground: launchedInBackground, didForeground: lifecycle.didForeground)
        } else {
            container.foregroundGate.open()
        }
        container.analytics.identifyUser(userId: container.user.currentUserId, attributes: container.user.userAttributes)
        // No explicit distinctId: `sdk_initialized` resolves the same user id as
        // every other event. The bundle id stays on the event as `app_bundle_id`.
        if announce {
            container.analytics.track(
                SDKInitializedEvent(sdkVersion: Encore.sdkVersion, appBundleId: container.configuration.appBundleId)
            )
        }
        // Counted on every start; sent only once the app is in front, so a background launch is not a visit.
        container.dailyActive.recordLaunch()
        container.dailyActive.start(didForeground: lifecycle?.didForeground)
        container.foregroundGate.runWhenOpen { [weak container] in container?.dailyActive.emitIfDue() }
    }

    private func turnedOn() {
        guard let services else { return }
        // What waited on disk goes out first, on every turn-on (the outbox never started if configure() ran off).
        services.outbox.resume()
        services.iapObserver?.reconcileTransactions()
        // A refresh refused while off (an identify() wipes them) would otherwise wait for the next foreground.
        Task { [entitlements = services.entitlements] in try? await entitlements.refreshEntitlements() }
        guard services.hasStarted else { return start(services, announce: false) }
        services.strictUnlockReconciler.kick()
        // Warmed again so the next show() opens fast. It waits only for the app's first activation of this
        // launch: after that the gate stays open, so a turn-on from the background warms and sends today's
        // daily active at once.
        scheduleLaunchWarmUp(services)
        sendDailyActiveIfOpen()
        analyticsClient?.identifyUser(userId: services.user.currentUserId, attributes: services.user.userAttributes)
    }

    private func turnedOff() {
        services?.outbox.stop()
        services?.strictUnlockReconciler.pause()
    }

    /// Whether a host call may refetch now: the SDK is on and the app has been active since launch.
    private var mayFetch: Bool { isEnabled && (services?.foregroundGate.isOpen ?? true) }

    // MARK: - User Identity
    
    /// Associates a user ID with SDK events and entitlements.
    public func identify(userId: String, attributes: UserAttributes? = nil) {
        // An empty id would otherwise PERSIST: "" is non-nil, so it defeats
        // the anonymous fallback and every event's distinct_id becomes "" —
        // collapsing the publisher's whole install base into one identity.
        guard !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.warn("[INTEGRATION] identify called with an empty userId — ignored; keeping the previous identity. Pass a real user id, or call reset() to return to anonymous.")
            return
        }
        guard let userManager = userManager,
              let entitlementsManager = entitlementsManager,
              let remoteConfigManager = remoteConfigManager,
              let analyticsClient = analyticsClient,
              let errorsClient = errorsClient else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        
        let previousUserId = userManager.currentUserId
        let wasAnonymous = !userManager.isIdentified
        let switching = userManager.replacesIdentifiedUser(with: userId)
        let languageChanged = attributes.map { forwardLegacyLanguage($0, to: userManager) } ?? false
        if switching {
            Logger.warn("[INTEGRATION] identify() named a different user while one was signed in, without reset(): switched users and cleared the previous user's local state. Call reset() on logout.")
            clearLocalUserState()
        }
        let changed = userManager.identify(userId: userId, attributes: attributes)
        // An anonymous user's claims follow them when they identify, as the server moves them.
        if wasAnonymous { ClaimLog.shared.carryOver(from: previousUserId, to: userId) }
        // The anonymous user's Gifts Button tally follows them to their first identify (their own
        // anonymous id included); anyone else's goes.
        if !switching, wasAnonymous || previousUserId != userId { GiftsButtonTally.live.identified(from: previousUserId, as: userId) }
        guard changed || languageChanged else { return }
        // Same user and language, new attributes: the cached offers were searched with the old ones
        // (the cache key holds only country and language). Cleared first, so the refetch and the
        // triggers' re-check search fresh.
        let targetingChanged = previousUserId == userId && !languageChanged && changed
        if targetingChanged { services?.offers.clearCache() }

        // Before the app first becomes active, the held launch warm-up fetches for this user.
        if mayFetch {
            remoteConfigManager.fetch(
                userId: userId,
                sdkVersion: Encore.sdkVersion,
                language: userManager.language
            )
            if previousUserId != userId || attributes != nil {
                refetchOffers()
            }
        }
        if switching {
            entitlementsManager.reset(thenRefresh: true)
            // A strict claim stays with its owner; this user's own, if any, resumes.
            strictUnlockReconciler?.identityChanged(from: previousUserId)
        } else if previousUserId != userId {
            // identify() links the previous id into this one, so its completed
            // campaigns and pending strict claim move too. The server carries its own records.
            completedCampaigns.carryOver(from: previousUserId, to: userId)
            entitlementsManager.reset(thenRefresh: true)
            strictUnlockReconciler?.carryOver(from: previousUserId, to: userId)
        }
        if previousUserId != userId || languageChanged {
            // Mounted triggers drop their cached variants and start over for the new user or language.
            TriggerIdentityChange.post()
        } else if targetingChanged {
            // Same user and language, new attributes: the offers a trigger found may differ.
            NotificationCenter.default.post(name: .encoreOfferTargetingDidChange, object: nil)
        }
        analyticsClient.identifyUser(userId: userManager.currentUserId, attributes: userManager.userAttributes)
        errorsClient.setUserId(userManager.currentUserId)
        if previousUserId != userId { sendDailyActiveIfOpen() }
    }

    /// The heartbeat counts users, so a new user in front gets theirs today.
    private func sendDailyActiveIfOpen() {
        guard let services, isEnabled, services.foregroundGate.isOpen else { return }
        services.dailyActive.emitIfDue()
    }
    
    /// The per-user state reset() and a change of signed-in user both clear. A switch keeps the
    /// outbox and the previous user's claim log and strict claim, which are keyed to them.
    private func clearLocalUserState() {
        remoteConfigManager?.clearCache()
        sduiConfigManager?.clearForcedFallback()
        // In-flight fetches for the previous user are cancelled and never cached.
        services?.offers.clearCache()
        ClaimStatusCheck.shared.clear()
        ReminderWindowStore.shared.clear()
        TriggerNotShownRecords.clear()
        GiftsButtonTally.live.clear()
    }

    /// Merges new attributes into the current user's profile.
    public func setUserAttributes(_ attributes: UserAttributes) {
        guard let userManager = userManager,
              let analyticsClient = analyticsClient else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }

        let languageChanged = forwardLegacyLanguage(attributes, to: userManager)
        let merged = userManager.setAttributes(attributes)
        if languageChanged {
            applyLanguage(userManager)  // identifies with the merged attributes too
        } else if let merged {
            analyticsClient.identifyUser(userId: userManager.currentUserId, attributes: merged)
            // The offers a mounted trigger found may differ for the new attributes: drop the sets
            // searched with the old ones first, so the re-check searches fresh.
            services?.offers.clearCache()
            NotificationCenter.default.post(name: .encoreOfferTargetingDidChange, object: nil)
        }
    }

    // MARK: - Language

    /// Serves Encore's copy in `tag` (BCP 47, e.g. "pt-BR" or "fr") instead of the
    /// device language. Kept on the device until ``clearLanguage()``, across launches
    /// and `reset()`; never sent to Encore as a user attribute. Call after `configure`.
    public func setLanguage(_ tag: String) {
        guard let userManager = userManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        if setLanguageTag(tag, on: userManager) {
            applyLanguage(userManager)
        }
    }

    /// Removes a language set with ``setLanguage(_:)`` so copy follows the device
    /// language again. Keeps the user and every attribute.
    public func clearLanguage() {
        guard let userManager = userManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        if userManager.clearLanguage() {
            applyLanguage(userManager)
        }
    }

    /// How many times the `UserAttributes.language` deprecation was logged this launch (at most 1).
    internal static var legacyLanguageWarnings = 0

    /// Stores a valid tag as the override. Returns whether it changed.
    private func setLanguageTag(_ tag: String, on userManager: UserManager) -> Bool {
        guard LanguageTag.normalized(tag) != nil else {
            Logger.warn("[INTEGRATION] setLanguage got \"\(tag)\", which is not a BCP 47 language tag; ignored, keeping \(userManager.language ?? "the device language"). Pass a language code, optionally with a region, such as \"fr\" or \"pt-BR\".")
            return false
        }
        return userManager.setLanguage(tag)
    }

    /// A deprecated `UserAttributes.language` becomes the override. Returns whether it changed.
    /// One warning per launch covers it, an unreadable tag included.
    private func forwardLegacyLanguage(_ attributes: UserAttributes, to userManager: UserManager) -> Bool {
        guard let tag = attributes.languageTag else { return false }
        if Self.legacyLanguageWarnings == 0 {
            Self.legacyLanguageWarnings += 1
            Logger.warn("[INTEGRATION] UserAttributes.language is deprecated and no longer sent as an attribute; it now calls setLanguage(_:), and a value that is not a language tag is ignored. Call Encore.shared.setLanguage(\"\(tag)\") instead.")
        }
        guard let normalized = LanguageTag.normalizedLegacy(tag) else { return false }
        return userManager.setLanguage(normalized)
    }

    /// Refetches /config and offers in the current language and re-identifies,
    /// so the next presentation and its events follow it.
    private func applyLanguage(_ userManager: UserManager) {
        if mayFetch {
            remoteConfigManager?.fetch(userId: userManager.currentUserId, sdkVersion: Encore.sdkVersion, language: userManager.language)
            refetchOffers()
        }
        // Triggers start over for the new language whatever the gate: each loads on its own appearance.
        TriggerIdentityChange.post()
        analyticsClient?.identifyUser(userId: userManager.currentUserId, attributes: userManager.userAttributes)
    }

    /// Clears user data and generates a new anonymous ID. Call on logout.
    ///
    /// The registered ``EncorePurchaseController`` and purchase-complete
    /// handler survive reset — they're build-time wiring, not user state.
    public func reset() {
        guard let userManager = userManager,
              let remoteConfigManager = remoteConfigManager,
              let analyticsClient = analyticsClient,
              let errorsClient = errorsClient,
              let entitlementsManager = entitlementsManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        
        clearLocalUserState()
        entitlementsManager.reset()
        // A pending strict claim must not follow the next user, nor may the claim log.
        strictUnlockReconciler?.clearPending()
        ClaimLog.shared.clear(userId: userManager.currentUserId)
        let newUserId = userManager.reset()
        TriggerIdentityChange.post()

        // The language override is the app's, not the user's: it survives reset.
        if mayFetch {
            remoteConfigManager.fetch(
                userId: newUserId,
                sdkVersion: Encore.sdkVersion,
                language: userManager.language
            )
        }
        analyticsClient.identifyUser(userId: newUserId, attributes: UserAttributes())
        errorsClient.setUserId(newUserId)
        sendDailyActiveIfOpen()
    }
    
    // MARK: - Publisher Reward

    /// The daily limit Encore's server applies to a placement's ``PublisherReward``.
    /// A property rather than a `configure` option, so prebuilt bridges keep
    /// linking; set it any time before `show()`. Survives `reset()`.
    public var publisherRewardPolicy = PublisherRewardPolicy()

    /// Campaigns the server said each user already completed, hidden from their lists on this device.
    internal var completedCampaigns = CompletedCampaigns()

    // MARK: - Outcomes Stream

    /// Active outcome-stream subscribers. A bare AsyncStream is
    /// single-consumer, so each `outcomes` access registers its own
    /// continuation and every event fans out to all of them.
    private var outcomeContinuations: [UUID: AsyncStream<PlacementOutcome>.Continuation] = [:]

    /// Every resolved placement outcome — plus late events like cross-launch
    /// strict-unlock verification — as an async sequence.
    ///
    /// Each access returns an independent stream, so any number of observers
    /// can listen concurrently. This is the observation channel; use the
    /// value returned by `show()` for control flow at the callsite.
    ///
    /// ```swift
    /// Task {
    ///     for await outcome in Encore.shared.outcomes {
    ///         appState.apply(outcome)
    ///     }
    /// }
    /// ```
    public var outcomes: AsyncStream<PlacementOutcome> {
        AsyncStream { continuation in
            let id = UUID()
            outcomeContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in
                    self?.outcomeContinuations[id] = nil
                }
            }
        }
    }

    /// Fan an event out to every active `outcomes` subscriber.
    internal func yieldOutcome(_ outcome: PlacementOutcome) {
        for continuation in outcomeContinuations.values {
            continuation.yield(outcome)
        }
    }

    // MARK: - Placements

    /// The instance form of ``Encore/placement(_:)``, kept for `EncoreProtocol` and 2.x callers.
    @available(*, deprecated, message: "Use the type-level call: Encore.placement(_:). Removed in 3.0.")
    public func placement(_ id: String? = nil) -> any PlacementBuilderProtocol {
        makePlacementBuilder(id)
    }

    internal func applyPersonalization(_ enabled: Bool) {
        guard Personalization.current != enabled else { return }
        Personalization.set(enabled)
        // A held set was served under the old setting: mounted triggers serve again.
        guard let offers = services?.offers else { return }
        Task {
            await offers.clearCacheNow()
            TriggerHeldOffers.changed()
        }
    }

    /// The concrete builder behind `placement(_:)`, for SDK-internal callers.
    internal func makePlacementBuilder(_ id: String?) -> PlacementBuilder {
        // The generated id is LOCAL identity only (the outcomes stream, the
        // host's PurchaseRequest) — it never goes on the wire (2026-08-14
        // reversal): analytics and /offers/search carry only a publisher-chosen
        // label, absent otherwise. The server folds absence into '(unlabeled)'
        // at read time, and presentation_id correlates a presentation's events.
        PlacementBuilder(
            id: id ?? "placement_\(UUID().uuidString.prefix(8))",
            label: PlacementLabel.sanitized(id)
        )
    }

    /// Warm the offer set for `placementLabel` so the sheet opens without a
    /// network round trip. Reuses a set already held (see `OffersCache.cacheTTL`).
    ///
    /// `useCase` is the use case the builder will present under. The warm must
    /// resolve the variant for THAT use case — `show()` reads
    /// `variantId(for: useCase)`, and the variant is part of the cache key, so
    /// warming under the churn default filled a set a reward presentation
    /// could never hit whenever the two variants differ.
    internal func prefetchOffers(placementLabel: String?, useCase: UseCase = .reduceChurn, context: PlacementContext? = nil) {
        guard services != nil else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            return
        }
        // Off: nothing is warmed; the next turn-on warms the launch set again.
        guard isEnabled else { return }
        // A warm requested in the background waits for the app to become active, like the launch one,
        // and checks the switch again then: turned off while it was held, it never starts.
        services?.foregroundGate.runWhenOpen { [weak self] in
            guard SDKSwitch.isOn else { return }
            self?.startPrefetch(placementLabel: placementLabel, useCase: useCase, context: context)
        }
    }

    private func startPrefetch(placementLabel: String?, useCase: UseCase, context: PlacementContext?) {
        #if DEBUG
        Self.prefetchObserverForTesting?(placementLabel, useCase)
        #endif
        Task { [weak self] in
            guard let self, let services = self.services else { return }
            // Same sequencing as configure(): warming ahead of the /config
            // answer ships a variant the server may be about to replace.
            await services.remoteConfigManager.awaitInFlightFetch()
            // Resolve this use case's config the same way show() will (the
            // availability ladder, then `variantId(for:)`). For an enabled use
            // case the config is already cached and this returns immediately;
            // otherwise it moves the one-time lazy /config fetch off the tap
            // path, which is exactly where a warm-up wants it.
            await services.remoteConfigManager.loadConfig(
                for: useCase,
                userId: services.user.currentUserId,
                sdkVersion: Encore.sdkVersion,
                language: services.user.language
            )
            // Turned off while the config loaded: the warm stops here.
            guard SDKSwitch.isOn else { return }
            services.offers.prefetch(
                userId: services.user.currentUserId,
                attributes: services.user.requestAttributes,
                variantId: services.sduiConfigManager.variantId(for: useCase),
                placementId: placementLabel,
                useCase: useCase,
                cachePlacementId: services.remoteConfigManager.cachePlacement(for: placementLabel),
                context: context,
                purpose: OfferSearchPurpose.prefetch
            )
        }
    }

    #if DEBUG
    /// Test seam: observes every warm `prefetchOffers` dispatches, with the
    /// label and use case it was asked to resolve. Fired synchronously so
    /// wiring tests need no async coordination.
    internal static var prefetchObserverForTesting: ((String?, UseCase) -> Void)?
    /// Test seam: fires when the launch warm-up gets past its config wait and starts warming.
    nonisolated(unsafe) internal static var launchWarmObserverForTesting: (() -> Void)?
    /// Test seam: fires as the identify or language refetch passes each switch check ("offers", then "images").
    nonisolated(unsafe) internal static var refetchStepObserverForTesting: ((String) -> Void)?
    #endif
    
    /// Creates a placement builder for presenting offers. Chain `.moment(_:)` to say why you show it now.
    public static func placement(_ id: String? = nil) -> any PlacementBuilderProtocol {
        shared.makePlacementBuilder(id)
    }

    /// Turns personalization off (or back on), as your app's own setting says. Saved on the device,
    /// per device, so the next launch's first request already carries it.
    public static func setPersonalization(_ enabled: Bool) {
        shared.applyPersonalization(enabled)
    }

    // MARK: - Entitlement Queries
    
    /// Checks if an entitlement is active. Auto-refreshes from server if needed, except while `isEnabled` is false.
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

// MARK: - Options

extension Encore {
    /// Configuration options for the Encore SDK.
    public struct Options: Sendable {
        /// Logging verbosity level.
        public var logLevel: LogLevel

        /// Controls when the SDK grants entitlements after an offer flow.
        public var unlock: UnlockMode

        /// Scans StoreKit history and links each `originalTransactionID` for lift measurement, and
        /// reads Apple's app transaction id as the person key. Set `false` to stop every store read:
        /// no history scan, no uploads, no app transaction id on events; NCL cohorts then hash the user id.
        public var transactionLinking: Bool

        /// Your app's personalization switch for this user, applied before the first request of the launch.
        /// Nil keeps the value last set; a value is saved as `setPersonalization(_:)` saves it.
        public var personalization: Bool?

        @_disfavoredOverload
        public init(
            logLevel: LogLevel = .none,
            unlock: UnlockMode = .optimistic,
            transactionLinking: Bool = true,
            personalization: Bool? = nil
        ) {
            self.logLevel = logLevel
            self.unlock = unlock
            self.transactionLinking = transactionLinking
            self.personalization = personalization
        }

        /// The 2.6.0 signature with its defaults, kept so binaries built against it still link (library evolution).
        public init(logLevel: LogLevel = .none, unlock: UnlockMode = .optimistic, transactionLinking: Bool = true) {
            self.init(logLevel: logLevel, unlock: unlock, transactionLinking: transactionLinking, personalization: nil)
        }
    }
}
