//
//  OfferSheetViewModel.swift
//  Encore
//

import Foundation
import Combine
import UIKit

@MainActor
@available(iOS 17.0, *)
class OfferSheetViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentOfferIndex: Int? = 0
    @Published var safariWrapper: SafariURLWrapper?
    
    // MARK: - Properties
    
    let offerResponse: OfferResponse
    let userId: String
    let presentationId: String
    let placementId: String?
    let offerContext: OfferContext
    let entitlement: Entitlement
    let completionHandler: SheetDismissHandler
    
    private var impressionIds: [String: String] = [:]
    private var pendingOffer: Offer?
    private static let appStoreURLPattern = "apps.apple.com"
    private var cancellables = Set<AnyCancellable>()
    
    /// Tracks whether an offer was claimed (user completed the Safari flow)
    private(set) var offerWasClaimed: Bool = false
    
    // MARK: - SDUI Variant Tracking
    
    /// The assigned SDUI variant ID
    private(set) var variantId: String?
    
    // MARK: - Time Tracking State
    
    private var sheetOpenedAt: Date?
    private var currentOfferStartTime: Date?
    private var offerViewTimes: [String: TimeInterval] = [:]  // campaignId -> total time spent
    private var offerViewCounts: [String: Int] = [:]  // campaignId -> number of times viewed
    
    // Convenience accessor for offers
    private var offers: [Offer] { offerResponse.offerList }
    
    // MARK: - Initialization
    
    init(
        offerResponse: OfferResponse,
        userId: String,
        presentationId: String,
        placementId: String? = nil,
        offerContext: OfferContext,
        entitlement: Entitlement,
        completionHandler: SheetDismissHandler
    ) {
        self.offerResponse = offerResponse
        self.userId = userId
        self.presentationId = presentationId
        self.placementId = placementId
        self.offerContext = offerContext
        self.entitlement = entitlement
        self.completionHandler = completionHandler
        
        subscribeToLifecycle()
    }
    
    /// Set variant metadata on both self and context
    func setVariantMetadata(variantId: String?, context: SDUIContext) {
        self.variantId = variantId
        context.setVariantMetadata(variantId: variantId, presentationId: presentationId)
    }
    
    // MARK: - Lifecycle
    
    private func subscribeToLifecycle() {
        Encore.shared.lifecycle?.didBackground
            .sink { [weak self] in self?.trackOfferClose(reason: .appBackgrounded) }
            .store(in: &cancellables)
        
        Encore.shared.lifecycle?.willTerminate
            .sink { [weak self] in self?.trackOfferClose(reason: .appTerminated) }
            .store(in: &cancellables)
    }
    
    // MARK: - Offer Interaction
    
    /// Handle offer tap - starts transaction and opens Safari.
    /// Sync interface for view binding; internally manages async work.
    func handleOfferTap(_ offer: Offer) {
        guard let transactions = transactionsManager else {
            Logger.warn("❌ transactionsManager not available")
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let transactionId = try await transactions.start(userId: userId, campaignId: offer.id)
                trackOfferClaimed(offer, transactionId: transactionId)

                pendingOffer = offer
                if let urlString = offer.displayDestinationUrl {
                    var urlComponents = URLComponents(string: urlString)
                    let trackingParameters = offer.displayTrackingParameters

                    if let trackingParameters = trackingParameters {
                        if urlComponents?.queryItems == nil {
                            urlComponents?.queryItems = []
                        }
                        for parameter in trackingParameters {
                            let queryParam = URLQueryItem(name: parameter.key, value: "\(parameter.value)")
                            urlComponents?.queryItems?.append(queryParam)
                        }
                    }

                    var finalUrl = urlComponents?.url?.absoluteString ?? urlString
                    finalUrl = finalUrl.replacingOccurrences(of: "TRANSACTION_ID", with: transactionId)

                    if let url = URL(string: finalUrl) {
                        safariWrapper = SafariURLWrapper(url: url)
                    }
                }
            } catch {
                Logger.warn("❌ Failed to start transaction: \(error)")
            }
        }
    }
    
    // MARK: - Safari Dismissal Handling
    
    func handleSafariDismiss() {
        guard let offer = pendingOffer else { return }
        
        safariWrapper = nil
        let destinationUrl = offer.displayDestinationUrl ?? ""
        
        // Check if it's an App Store URL
        if destinationUrl.contains(Self.appStoreURLPattern) {
            Logger.debug("🛍️ App Store URL detected - not completing via Safari dismiss, waiting for app return")
            pendingOffer = nil
            return
        }
        
        Logger.debug("✅ Regular URL - treating Safari dismiss as credit applied")
        
        offerWasClaimed = true
        
        Logger.debug("🔄 [ENTITLEMENTS] REFRESH safariViewDismissed")
        Task { try? await entitlementsManager?.refreshEntitlements() }
        
        Logger.debug("✅ Granting entitlement (no IAP)")
        completionHandler.handleImmediate(.success(.granted( entitlement)))
        
        // Delegate purchase to host app if handler is registered
        let iapProductId = remoteConfigManager?.iapProductId ?? entitlementsManager?.userAttributes.iapProductId
        if let iapProductId {
            Task { await IAPClient.delegatePurchase(productId: iapProductId, placementId: placementId) }
        } else {
            Logger.debug("🛒 [IAP] No iapProductId — skipping purchase")
        }
        pendingOffer = nil
    }
}

// MARK: - Analytics

@available(iOS 17.0, *)
extension OfferSheetViewModel {
    
    // MARK: - Context & Tracking Helpers
    
    /// Build analytics context for the given offer, including variant metadata
    private func context(for offer: Offer, at index: Int? = nil) -> OfferAnalyticsContext {
        OfferAnalyticsContext(
            offer: offer,
            impressionId: impressionIds[offer.id] ?? "",
            offerIndex: index ?? currentOfferIndex ?? 0,
            totalOffers: offers.count,
            presentationId: presentationId,
            variantId: variantId
        )
    }
    
    /// Parsimonious tracking helper (uses AnalyticsClient's stored userId)
    private func track<E: AnalyticsEvent>(_ event: E) {
        analyticsClient?.track(event)
    }
    
    // MARK: - Time Tracking
    
    /// Called when the offer sheet appears - starts tracking sheet and first offer time
    func startTimeTracking() {
        let now = Date()
        sheetOpenedAt = now
        currentOfferStartTime = now
        
        // Track first offer view
        if let firstOffer = offers.first {
            offerViewCounts[firstOffer.id] = 1
        }
        
        Logger.debug("⏱️ [OfferSheet] Started time tracking at \(now)")
    }
    
    /// Called when the user swipes to a different offer - updates time for previous offer
    func trackOfferSwipe(from previousIndex: Int?, to newIndex: Int) {
        guard let startTime = currentOfferStartTime else { return }
        
        // Record time spent on previous offer
        if let prevIndex = previousIndex, prevIndex < offers.count {
            let previousOffer = offers[prevIndex]
            let timeSpent = Date().timeIntervalSince(startTime)
            let existingTime = offerViewTimes[previousOffer.id] ?? 0
            offerViewTimes[previousOffer.id] = existingTime + timeSpent
            
            Logger.debug("⏱️ [OfferSheet] Spent \(String(format: "%.1f", timeSpent))s on offer \(prevIndex) (\(previousOffer.advertiserName))")
        }
        
        // Increment view count for the new offer
        if newIndex < offers.count {
            let newOffer = offers[newIndex]
            let existingCount = offerViewCounts[newOffer.id] ?? 0
            offerViewCounts[newOffer.id] = existingCount + 1
        }
        
        // Start timing the new offer
        currentOfferStartTime = Date()
    }
    
    // MARK: - Impression Tracking
    
    func trackOfferImpression(at index: Int) {
        guard index < offers.count else { return }
        
        let offer = offers[index]
        let campaignId = offer.id
        
        // Skip if already logged
        if impressionIds[campaignId] != nil {
            Logger.debug("📊 [OfferSheetView] Impression already logged for campaign: \(campaignId)")
            return
        }
        
        let impressionId = UUID().uuidString
        impressionIds[campaignId] = impressionId
        
     
        let ctx = context(for: offer, at: index)
        track(OfferPresentedEvent(ctx, trigger: index == 0 ? "initial_load" : "swipe"))
    }
    
    // MARK: - Offer Event Tracking
    
    func trackOfferClaimed(_ offer: Offer, transactionId: String) {
        let ctx = context(for: offer)
        track(OfferClaimedEvent(ctx, transactionId: transactionId))
    }
    
    // MARK: - Close/Dismiss Tracking
    
    func trackOfferClose(reason: OfferDismissReason) {
        guard let sheetOpened = sheetOpenedAt else { return }
        
        let now = Date()
        let totalSheetTime = now.timeIntervalSince(sheetOpened)
        
        // Capture final offer info
        var finalCampaignId: String?
        var finalCreativeId: String?
        var finalAdvertiserName: String?
        
        // Record time for the current offer being viewed
        if let startTime = currentOfferStartTime,
           let currentIndex = currentOfferIndex,
           currentIndex < offers.count {
            let currentOffer = offers[currentIndex]
            let timeSpent = now.timeIntervalSince(startTime)
            let existingTime = offerViewTimes[currentOffer.id] ?? 0
            offerViewTimes[currentOffer.id] = existingTime + timeSpent
            
            finalCampaignId = currentOffer.id
            finalCreativeId = currentOffer.primaryCreative?.id
            finalAdvertiserName = currentOffer.advertiserName
        }
        
        // Log summary analytics event
        track(OfferSheetDismissedEvent(
            presentationId: presentationId,
            totalTime: totalSheetTime,
            reason: reason,
            totalOffers: offers.count,
            offersViewed: offerViewTimes.count,
            finalIndex: currentOfferIndex ?? 0,
            finalCampaignId: finalCampaignId,
            finalCreativeId: finalCreativeId,
            finalAdvertiserName: finalAdvertiserName,
            variantId: variantId
        ))
        
        // Log separate event for each offer's time tracking
        for (index, offer) in offers.enumerated() {
            if let timeSpent = offerViewTimes[offer.id] {
                track(OfferTimeSpentEvent(
                    offer: offer,
                    index: index,
                    timeSpent: timeSpent,
                    viewCount: offerViewCounts[offer.id] ?? 0,
                    totalOffers: offers.count,
                    sheetTime: totalSheetTime,
                    reason: reason,
                    presentationId: presentationId,
                    variantId: variantId
                ))
            }
        }
        
        Logger.debug("⏱️ [OfferSheet] Dismissed after \(String(format: "%.1f", totalSheetTime))s - viewed \(offerViewTimes.count) offers")
        for (campaignId, time) in offerViewTimes {
            if let offer = offers.first(where: { $0.id == campaignId }) {
                let viewCount = offerViewCounts[campaignId] ?? 0
                Logger.debug("  └─ \(offer.advertiserName): \(String(format: "%.1f", time))s (\(viewCount) view\(viewCount == 1 ? "" : "s"))")
            }
        }
    }
    
    // MARK: - Safari Event Tracking
    
    func handleSafariTrackingEvent(_ event: SafariTrackingEvent) {
        guard let offer = pendingOffer else { return }
        
        let ctx = context(for: offer)
        
        switch event {
        case .attemptingToOpen(let url):
            track(OfferWebviewAttemptingOpenEvent(ctx, url: url))
            
        case .didOpen(let url, let openedAt):
            track(OfferWebviewOpenedEvent(ctx, url: url, openedAt: openedAt))
            
        case .initialLoadCompleted(let url, let didLoadSuccessfully):
            if didLoadSuccessfully {
                track(OfferWebviewLoadSuccessEvent(ctx, url: url))
            } else {
                track(OfferWebviewLoadFailedEvent(ctx, url: url))
            }
            
        case .initialRedirect(let from, let to):
            track(OfferWebviewInitialRedirectEvent(ctx, from: from, to: to))
            
        case .dismissed(let timeSpentSeconds):
            track(OfferWebviewDismissedEvent(ctx, timeSpent: timeSpentSeconds))
        }
    }
}
