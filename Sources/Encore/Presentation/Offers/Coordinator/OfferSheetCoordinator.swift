// OfferSheetCoordinator.swift
//
// Coordinates the offer presentation lifecycle.
// Bridges async/await to UIKit window presentation.
// Entry point: present(placementId:) → PresentationResult.

import UIKit
import SwiftUI

@MainActor
internal final class OfferSheetCoordinator {

    // MARK: - State Machine

    /// Phase within a single presentation lifecycle.
    private enum Phase {
        case loading(task: Task<Void, Never>)
        case presenting
        case finished
    }

    /// Single source of truth — nil means no active presentation.
    /// Replaces separate `active` + `state` fields to prevent desynchronization.
    private struct ActivePresentation {
        let coordinator: OfferSheetCoordinator
        var phase: Phase
    }

    private static var current: ActivePresentation?
    private var continuation: CheckedContinuation<PresentationResult, Error>?
    private let presentationId = UUID().uuidString
    internal let placementId: String?

    // MARK: - Init

    private init(placementId: String?) {
        self.placementId = placementId
    }

    // MARK: - Entry Point

    /// Presents an offer sheet and suspends until dismissed.
    /// Only one presentation may be active at a time.
    static func present(placementId: String? = nil) async throws -> PresentationResult {
        // iOS version gate
        guard #available(iOS 17.0, *) else {
            let version = UIDevice.current.systemVersion
            Logger.debug("SwiftUI offers require iOS 17+. Current: \(version)")
            analyticsClient?.track(
                OfferPresentationFailedEvent(reason: .unsupportedOS, iosVersion: version, presentationId: UUID().uuidString)
            )
            return .notGranted( .unsupportedOS)
        }

        // Defensive: clean stale finished coordinator (should never happen with defer)
        if let c = current, case .finished = c.phase {
            Logger.warn("[Presentation] Stale coordinator detected — cleaning up")
            current = nil
        }

        guard current == nil else {
            Logger.warn("[Presentation] Already presenting, ignoring duplicate request")
            throw EncoreError.domain("Already presenting an offer sheet")
        }

        // NCL Experiment: Check cohort assignment (Ghost Trigger intercept)
        let cohort = experimentManager?.getCohort() ?? .notEnrolled

        // Log exposure for BOTH cohorts via reliable outbox (critical for NCL measurement)
        if cohort != .notEnrolled,
           let appAccountId = userManager?.appAccountId,
           let assignmentVersion = remoteConfigManager?.experiments?.ncl?.assignmentVersion,
           let outbox = Encore.shared.services?.outbox {
            outbox.enqueue(.experimentExposure(
                appAccountId: appAccountId,
                experiment: "ncl",
                cohort: cohort,
                assignmentVersion: assignmentVersion
            ))
            Logger.debug("🧪 [EXPERIMENT] Logged exposure: cohort=\(cohort.rawValue), version=\(assignmentVersion)")
        }

        // Ghost Trigger: Control group exits immediately (no UI, exposure logged)
        if cohort == .control {
            Logger.info("🧪 [EXPERIMENT] Ghost Trigger - Control cohort, no UI shown")
            analyticsClient?.track(
                OfferPresentationFailedEvent(reason: .experimentControl, presentationId: UUID().uuidString)
            )
            return .notGranted(.experimentControl)
        }

        // Treatment or notEnrolled: continue with normal presentation flow
        Logger.debug("🧪 [EXPERIMENT] Cohort: \(cohort.rawValue) - proceeding with presentation")

        let coordinator = OfferSheetCoordinator(placementId: placementId)
        defer { current = nil }

        return try await coordinator.run()
    }

    // MARK: - Lifecycle

    /// Bridges the coordinator lifecycle to async/await via a single continuation.
    private func run() async throws -> PresentationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.start()
        }
    }

    private func start() {
        guard let analyticsClient = analyticsClient,
              let entitlementsManager = entitlementsManager,
              let offersManager = offersManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            complete(.failure(.integration(.notConfigured)))
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }

            let userId = entitlementsManager.currentUserId
            let attributes = entitlementsManager.userAttributes

            // Get variant ID from remote config manager (pre-fetched on user identify).
            let variantId: String? = sduiConfigManager?.variantId
            Logger.debug("🔍 [RemoteConfig] OfferPresentation reading variantId=\(variantId ?? "nil"), hasRemoteConfig=\(remoteConfigManager?.config != nil)")

            analyticsClient.track(OfferPresentationTriggeredEvent(presentationId: presentationId))

            do {
                let response = try await offersManager.fetchOffers(userId: userId, attributes: attributes, variantId: variantId)
                guard !response.offerList.isEmpty else {
                    analyticsClient.track(
                        OfferPresentationFailedEvent(reason: .noOffersAvailable, presentationId: presentationId)
                    )
                    self.complete(.success(.notGranted( .noOffersAvailable)))
                    return
                }

                analyticsClient.track(
                    OfferPresentationSuccessEvent(
                        presentationId: presentationId,
                        offerCount: "\(response.offerCount)"
                    )
                )

                // Get IAP product ID (prefer config, fallback to user attributes for backward compat)
                let iapProductId = remoteConfigManager?.iapProductId ?? attributes.iapProductId

                // Fetch IAP product info if configured
                var iapContext: IAPContext = .empty
                if let iapProductId {
                    if let productInfo = await IAPClient.fetchProductInfo(productId: iapProductId) {
                        iapContext = IAPContext(from: productInfo)
                        Logger.debug("💰 [IAP] Fetched subscription: \(productInfo.displayPrice)\(productInfo.subscriptionPeriod ?? "")")
                    } else if sduiConfigManager?.requiresIAP == true {
                        Logger.warn("⚠️ [IAP] Config requires IAP but product '\(iapProductId)' not found - using fallback config")
                        sduiConfigManager?.useFallbackConfig(reason: "Invalid IAP product: \(iapProductId)")
                    }
                } else if sduiConfigManager?.requiresIAP == true {
                    Logger.warn("⚠️ [IAP] Config requires IAP but no iapProductId configured - using fallback config")
                    sduiConfigManager?.useFallbackConfig(reason: "No iapProductId configured")
                }

                // Create offer context combining remote config and IAP data
                let offerContext = OfferContext(
                    uiValues: remoteConfigManager?.ui?.values,
                    entitlements: remoteConfigManager?.entitlements,
                    iap: iapContext
                )

                // Check for IAP-First flow
                if sduiConfigManager?.layout?.triggerIAPFirst == true {
                    guard let iapProductIdForPurchase = iapProductId else {
                        Logger.warn("⚠️ [IAP-First] triggerIAPFirst is true but no iapProductId configured")
                        sduiConfigManager?.useFallbackConfig(reason: "No iapProductId for triggerIAPFirst")
                        if #available(iOS 17.0, *) {
                            self.presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                        }
                        return
                    }

                    Logger.info("🛒 [IAP-First] Triggering IAP before showing offers")
                    let purchaseSucceeded = await IAPClient.delegatePurchase(productId: iapProductIdForPurchase, placementId: self.placementId)

                    if purchaseSucceeded {
                        Logger.info("✅ [IAP-First] Purchase successful - showing offers")
                        if #available(iOS 17.0, *) {
                            self.presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                        }
                    } else {
                        Logger.info("🚫 [IAP-First] Purchase cancelled or failed - dismissing")
                        self.complete(.success(.notGranted(.dismissed)))
                    }
                    return
                }

                if #available(iOS 17.0, *) {
                    self.presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                }
            } catch let error as EncoreError {
                Logger.error(error, context: .fetchOfferData)
                self.complete(.failure(error))
            } catch {
                let wrapped = EncoreError.transport(.network(error))
                Logger.error(wrapped, context: .fetchOfferData)
                self.complete(.failure(wrapped))
            }
        }
        Self.current = ActivePresentation(coordinator: self, phase: .loading(task: task))
    }

    @available(iOS 17.0, *)
    private func presentOfferSheet(response: OfferResponse, userId: String, offerContext: OfferContext, initialStateOverride: String?) {
        Logger.info("🎁 [Presentation] Presenting offer sheet with \(response.offerCount) offers")

        let containerView = OfferSheetContainer(
            offerResponse: response,
            userId: userId,
            presentationId: presentationId,
            placementId: placementId,
            offerContext: offerContext,
            initialStateOverride: initialStateOverride,
            onCompletion: { [weak self] result in
                self?.complete(result)
            }
        )

        let presented = PresentationWindow.present(containerView) { [weak self] in
            self?.complete(.success(.notGranted( .dismissed)))
        }
        if presented {
            Self.current = ActivePresentation(coordinator: self, phase: .presenting)
        } else {
            Logger.error(.integration(.notConfigured), context: .presentOfferInitialization)
            complete(.failure(.integration(.notConfigured)))
        }
    }

    // MARK: - Completion

    /// Single completion path — idempotent.
    /// Handles cleanup based on current phase:
    /// - `.loading`: cancels in-flight task, no window to tear down
    /// - `.presenting`: tears down the presentation window
    /// - `.finished` / nil: no-op (already completed)
    private func complete(_ result: Result<PresentationResult, EncoreError>) {
        // Continuation is the idempotency guard — consumed exactly once.
        // This also handles the edge case where start() fails before setting current.
        guard let continuation else { return }
        self.continuation = nil

        // Phase-based cleanup (only if this coordinator owns current)
        if let active = Self.current, active.coordinator === self {
            if case .loading(let task) = active.phase { task.cancel() }
            if case .presenting = active.phase { PresentationWindow.cleanup() }
            Self.current = ActivePresentation(coordinator: self, phase: .finished)
        }

        continuation.resume(with: result)
    }

    // MARK: - Test Hooks

    /// Whether a non-finished presentation is in progress.
    static var isPresenting: Bool {
        guard let current else { return false }
        if case .finished = current.phase { return false }
        return true
    }

    #if DEBUG
    /// Force the coordinator into an active (non-idle) state for gate testing.
    static func _forcePresenting() {
        let coordinator = OfferSheetCoordinator(placementId: nil)
        let task = Task<Void, Never> { }
        current = ActivePresentation(coordinator: coordinator, phase: .loading(task: task))
    }

    /// Force-clear all state for test isolation.
    static func _forceReset() {
        current = nil
    }
    #endif
}
