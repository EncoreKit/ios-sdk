// Presentation/Offers/Coordinator/OfferSheetCoordinator.swift
//
// Coordinates the offer presentation lifecycle.
// Bridge UIKit top level window management to SwiftUI.
// Entry point from Placement.show() and .encoreSheet().
//
// Async-first: The single withCheckedThrowingContinuation lives here,
// bridging UI events to async/await flow.

import UIKit
import SwiftUI

@MainActor
internal final class OfferSheetCoordinator {
    private static var active: OfferSheetCoordinator?
    private var continuation: CheckedContinuation<PresentationResult, Error>?
    private let presentationId = UUID().uuidString
    internal let placementId: String?

    // MARK: - Init

    private init(placementId: String?) {
        self.placementId = placementId
    }
    
    // MARK: - Static Entry Point (Async)
    
    /// Presents the offer sheet and returns the result.
    /// This is the primary async entry point. The continuation is encapsulated here.
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
        
        guard active == nil else {
            Logger.warn("[OfferPresentation] Already presenting, ignoring duplicate request")
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
        active = coordinator
        
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.continuation = continuation
            coordinator.start()
        }
    }
    
    // MARK: - Lifecycle
    
    private func start() {
        guard let analyticsClient = analyticsClient,
              let entitlementsManager = entitlementsManager,
              let offersManager = offersManager else {
            Logger.error(.integration(.notConfigured), context: .configuration)
            finish(.failure(.integration(.notConfigured)))
            return
        }
        
        // Load and present offers
        Task {
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
                    finish(.success(.notGranted( .noOffersAvailable)))
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
                        // Config requires IAP but product is invalid - fall back
                        Logger.warn("⚠️ [IAP] Config requires IAP but product '\(iapProductId)' not found - using fallback config")
                        sduiConfigManager?.useFallbackConfig(reason: "Invalid IAP product: \(iapProductId)")
                    }
                } else if sduiConfigManager?.requiresIAP == true {
                    // Config requires IAP but no product ID configured - fall back
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
                            presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                        }
                        return
                    }
                    
                    Logger.info("🛒 [IAP-First] Triggering IAP before showing offers")
                    let purchaseSucceeded = await IAPClient.delegatePurchase(productId: iapProductIdForPurchase, placementId: placementId)

                    if purchaseSucceeded {
                        Logger.info("✅ [IAP-First] Purchase successful - showing offers")
                        if #available(iOS 17.0, *) {
                            presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                        }
                    } else {
                        Logger.info("🚫 [IAP-First] Purchase cancelled or failed - dismissing")
                        finish(.success(.notGranted(.dismissed)))
                    }
                    return
                }
                
                if #available(iOS 17.0, *) {
                    presentOfferSheet(response: response, userId: userId, offerContext: offerContext, initialStateOverride: nil)
                }
            } catch let error as EncoreError {
                Logger.error(error, context: .fetchOfferData)
                finish(.failure(error))
            } catch {
                let wrapped = EncoreError.transport(.network(error))
                Logger.error(wrapped, context: .fetchOfferData)
                finish(.failure(wrapped))
            }
        }
    }

    @available(iOS 17.0, *)
    private func presentOfferSheet(response: OfferResponse, userId: String, offerContext: OfferContext, initialStateOverride: String?) {
        Logger.info("🎁 [OfferPresentation] Presenting offer sheet with \(response.offerCount) offers")

        let containerView = OfferSheetContainer(
            offerResponse: response,
            userId: userId,
            presentationId: presentationId,
            placementId: placementId,
            offerContext: offerContext,
            initialStateOverride: initialStateOverride,
            onCompletion: { [weak self] result in
                self?.finish(result)
            }
        )
        
        PresentationWindow.present(containerView) { [weak self] in
            self?.finish(.success(.notGranted( .dismissed)))
        }
    }
    
    // MARK: - Finish
    
    private func finish(_ result: Result<PresentationResult, EncoreError>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        Self.active = nil
        
        switch result {
        case .success(let presentationResult):
            continuation.resume(returning: presentationResult)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
