//
//  OfferEvents.swift
//  Encore
//
//  Analytics events for offer interactions.
//

import Foundation

// MARK: - Analytics Context

/// Shared context for offer-related analytics events.
/// Captures the current state once and reuses across multiple events.
struct OfferAnalyticsContext {
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    
    // SDUI Variant tracking
    let variantId: String?
    
    /// Create context from an Offer and current view state
    init(offer: Offer, impressionId: String, offerIndex: Int, totalOffers: Int, presentationId: String, variantId: String? = nil) {
        self.campaignId = offer.id
        self.creativeId = offer.primaryCreative?.id
        self.advertiserName = offer.advertiserName
        self.impressionId = impressionId
        self.offerIndex = offerIndex
        self.totalOffers = totalOffers
        self.presentationId = presentationId
        self.variantId = variantId
    }
    
    /// Direct initialization for legacy/custom use
    init(campaignId: String, creativeId: String?, advertiserName: String, impressionId: String, offerIndex: Int, totalOffers: Int, presentationId: String, variantId: String? = nil) {
        self.campaignId = campaignId
        self.creativeId = creativeId
        self.advertiserName = advertiserName
        self.impressionId = impressionId
        self.offerIndex = offerIndex
        self.totalOffers = totalOffers
        self.presentationId = presentationId
        self.variantId = variantId
    }
}

// MARK: - Offer Presentation Events

/// Tracked when offer presentation is triggered
struct OfferPresentationTriggeredEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_presentation_triggered"
    
    let presentationId: String
    let variantId: String?
    
    init(presentationId: String, variantId: String? = nil) {
        self.presentationId = presentationId
        self.variantId = variantId
    }
}

/// Tracked when offer presentation fails
struct OfferPresentationFailedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_presentation_failed"
    
    let reason: String
    let iosVersion: String?
    let presentationId: String
    let variantId: String?
    
    init(reason: NotGrantedReason, iosVersion: String? = nil, presentationId: String, variantId: String? = nil) {
        self.reason = reason.rawValue
        self.iosVersion = iosVersion
        self.presentationId = presentationId
        self.variantId = variantId
    }
}

/// Tracked when offer presentation succeeds
struct OfferPresentationSuccessEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_presentation_success"
    
    let presentationId: String
    let offerCount: String
    let variantId: String?
    
    init(presentationId: String, offerCount: String, variantId: String? = nil) {
        self.presentationId = presentationId
        self.offerCount = offerCount
        self.variantId = variantId
    }
}

/// Tracked when an offer is presented to the user
struct OfferPresentedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_presented"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationTrigger: String
    let presentationId: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, trigger: String) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.presentationTrigger = trigger
        self.variantId = ctx.variantId
    }
}

/// Tracked when a user claims an offer
struct OfferClaimedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_claimed"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let transactionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, transactionId: String) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.transactionId = transactionId
        self.variantId = ctx.variantId
    }
}

/// Tracked when a user declines an offer
struct OfferDeclinedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_declined"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String?
    let offerIndex: Int
    let totalOffers: Int
    let declineReason: String
    let presentationId: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, reason: String) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.declineReason = reason
        self.variantId = ctx.variantId
    }
    
    /// Legacy init for cases where impressionId may be nil
    init(campaignId: String, creativeId: String?, advertiserName: String, impressionId: String?, offerIndex: Int, totalOffers: Int, reason: String, presentationId: String, variantId: String? = nil) {
        self.campaignId = campaignId
        self.creativeId = creativeId
        self.advertiserName = advertiserName
        self.impressionId = impressionId
        self.offerIndex = offerIndex
        self.totalOffers = totalOffers
        self.declineReason = reason
        self.presentationId = presentationId
        self.variantId = variantId
    }
}

// MARK: - Dismiss Reasons

/// Reason why an offer sheet was dismissed. Used across multiple analytics events.
enum OfferDismissReason: String {
    case closeButton = "close_button"
    case swipeDismiss = "swipe_dismiss"
    case offerClaimed = "offer_claimed"
    case appBackgrounded = "app_backgrounded"
    case appTerminated = "app_terminated"
}

/// Tracked when the offer sheet is dismissed
struct OfferSheetDismissedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_sheet_dismissed"
    
    let presentationId: String
    let totalTimeSpentSeconds: Double
    let totalTimeSpentFormatted: String
    let declineReason: String
    let totalOffers: Int
    let offersViewed: Int
    let finalOfferIndex: Int
    let finalOfferCampaignId: String?
    let finalOfferCreativeId: String?
    let finalOfferAdvertiserName: String?
    let variantId: String?
    
    init(presentationId: String, totalTime: Double, reason: OfferDismissReason, totalOffers: Int, offersViewed: Int, finalIndex: Int, finalCampaignId: String?, finalCreativeId: String?, finalAdvertiserName: String?, variantId: String? = nil) {
        self.presentationId = presentationId
        self.totalTimeSpentSeconds = totalTime
        self.totalTimeSpentFormatted = String(format: "%.1fs", totalTime)
        self.declineReason = reason.rawValue
        self.totalOffers = totalOffers
        self.offersViewed = offersViewed
        self.finalOfferIndex = finalIndex
        self.finalOfferCampaignId = finalCampaignId
        self.finalOfferCreativeId = finalCreativeId
        self.finalOfferAdvertiserName = finalAdvertiserName
        self.variantId = variantId
    }
}

/// Tracked for time spent on an offer
struct OfferTimeSpentEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_time_spent"
    
    let campaignId: String
    let advertiserName: String
    let creativeId: String?
    let offerIndex: Int
    let timeSpentSeconds: Double
    let timeSpentFormatted: String
    let viewCount: Int
    let totalOffers: Int
    let totalSheetTimeSeconds: Double
    let dismissReason: String
    let presentationId: String
    let variantId: String?
    
    init(offer: Offer, index: Int, timeSpent: Double, viewCount: Int, totalOffers: Int, sheetTime: Double, reason: OfferDismissReason, presentationId: String, variantId: String? = nil) {
        self.campaignId = offer.id
        self.advertiserName = offer.advertiserName
        self.creativeId = offer.primaryCreative?.id
        self.offerIndex = index
        self.timeSpentSeconds = timeSpent
        self.timeSpentFormatted = String(format: "%.1fs", timeSpent)
        self.viewCount = viewCount
        self.totalOffers = totalOffers
        self.totalSheetTimeSeconds = sheetTime
        self.dismissReason = reason.rawValue
        self.presentationId = presentationId
        self.variantId = variantId
    }
}

/// Tracked when apply credits is clicked
struct ApplyCreditsClickedEvent: AnalyticsEvent {
    static let eventName = "sdk_apply_credits_clicked"
    
    let creditsApplied: Double
    let userId: String
    let variantId: String?
    
    init(creditsApplied: Double, userId: String, variantId: String? = nil) {
        self.creditsApplied = creditsApplied
        self.userId = userId
        self.variantId = variantId
    }
}

// MARK: - WebView Events

/// Tracked when attempting to open webview
struct OfferWebviewAttemptingOpenEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_attempting_open"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let url: String
    let urlHost: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, url: URL) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.url = url.absoluteString
        self.urlHost = url.host ?? ""
        self.variantId = ctx.variantId
    }
}

/// Tracked when webview is opened
struct OfferWebviewOpenedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_opened"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let url: String
    let urlHost: String
    let openedAt: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, url: URL, openedAt: Date) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.url = url.absoluteString
        self.urlHost = url.host ?? ""
        self.openedAt = ISO8601DateFormatter().string(from: openedAt)
        self.variantId = ctx.variantId
    }
}

/// Tracked when webview load succeeds
struct OfferWebviewLoadSuccessEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_load_success"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let url: String
    let urlHost: String
    let loadSuccess: Bool = true
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, url: URL) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.url = url.absoluteString
        self.urlHost = url.host ?? ""
        self.variantId = ctx.variantId
    }
}

/// Tracked when webview load fails
struct OfferWebviewLoadFailedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_load_failed"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let url: String
    let urlHost: String
    let loadSuccess: Bool = false
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, url: URL) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.url = url.absoluteString
        self.urlHost = url.host ?? ""
        self.variantId = ctx.variantId
    }
}

/// Tracked when webview initial redirect occurs
struct OfferWebviewInitialRedirectEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_initial_redirect"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let fromUrl: String
    let toUrl: String
    let fromHost: String
    let toHost: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, from: URL, to: URL) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.fromUrl = from.absoluteString
        self.toUrl = to.absoluteString
        self.fromHost = from.host ?? ""
        self.toHost = to.host ?? ""
        self.variantId = ctx.variantId
    }
}

/// Tracked when webview is dismissed (SwiftUI)
struct OfferWebviewDismissedEvent: AnalyticsEvent {
    static let eventName = "sdk_offer_webview_dismissed"
    
    let campaignId: String
    let creativeId: String?
    let advertiserName: String
    let impressionId: String
    let offerIndex: Int
    let totalOffers: Int
    let presentationId: String
    let timeSpentSeconds: Double
    let timeSpentFormatted: String
    let variantId: String?
    
    init(_ ctx: OfferAnalyticsContext, timeSpent: Double) {
        self.campaignId = ctx.campaignId
        self.creativeId = ctx.creativeId
        self.advertiserName = ctx.advertiserName
        self.impressionId = ctx.impressionId
        self.offerIndex = ctx.offerIndex
        self.totalOffers = ctx.totalOffers
        self.presentationId = ctx.presentationId
        self.timeSpentSeconds = timeSpent
        self.timeSpentFormatted = String(format: "%.1fs", timeSpent)
        self.variantId = ctx.variantId
    }
}
