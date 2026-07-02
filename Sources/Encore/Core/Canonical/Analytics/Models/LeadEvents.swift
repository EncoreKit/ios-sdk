//
//  LeadEvents.swift
//  Encore
//
//  Analytics events for lead capture flow.
//

import Foundation

// MARK: - Lead Capture Events

/// Tracked when a lead email is successfully captured and submitted
struct LeadCapturedEvent: AnalyticsEvent {
    static let eventName = "sdk_lead_captured"

    let email: String
    let presentationId: String
    let variantId: String?
    let campaignId: String?

    init(email: String, presentationId: String, variantId: String?, campaignId: String? = nil) {
        self.email = email
        self.presentationId = presentationId
        self.variantId = variantId
        self.campaignId = campaignId
    }
}

/// Tracked when a private relay email is detected and blocked
struct LeadPrivateRelayDetectedEvent: AnalyticsEvent {
    static let eventName = "sdk_lead_private_relay_detected"

    let presentationId: String
    let variantId: String?

    init(presentationId: String, variantId: String?) {
        self.presentationId = presentationId
        self.variantId = variantId
    }
}
