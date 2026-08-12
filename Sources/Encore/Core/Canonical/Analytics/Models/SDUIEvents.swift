//
//  SDUIEvents.swift
//  Encore
//
//  Analytics events for Server-Driven UI tracking.
//  Includes config loading, state transitions, element interactions, and render performance.
//

import Foundation

// MARK: - Variant Context

/// Shared context for SDUI variant-related analytics events.
struct SDUIVariantContext {
    let variantId: String?
    
    /// Empty context for when no variant is assigned (fallback)
    static let empty = SDUIVariantContext(variantId: nil)
}

// MARK: - Config Load Events

/// Tracked when SDUI config is successfully loaded
struct SDUIConfigLoadedEvent: AnalyticsEvent {
    static let eventName = "sdk_sdui_config_loaded"
    
    let variantId: String?
    /// "cache", "remote", "fallback". Frozen cross-SDK: a rung-2 render (the
    /// persisted variant/template pair) reports "cache", and a floor render
    /// reports "fallback" with a nil variant id.
    let loadSource: String
    let loadDurationMs: Double
    let presentationId: String?
    
    init(variant: SDUIVariantContext, loadSource: String, loadDurationMs: Double, presentationId: String? = nil) {
        self.variantId = variant.variantId
        self.loadSource = loadSource
        self.loadDurationMs = loadDurationMs
        self.presentationId = presentationId
    }
}

// MARK: - State Transition Events

/// Tracked when state machine transitions between states
struct SDUIStateTransitionEvent: AnalyticsEvent {
    static let eventName = "sdk_sdui_state_transition"
    
    let variantId: String?
    let fromState: String
    let toState: String
    let presentationId: String
    let timeInPreviousStateMs: Double
    
    init(variant: SDUIVariantContext, fromState: String, toState: String, presentationId: String, timeInPreviousStateMs: Double) {
        self.variantId = variant.variantId
        self.fromState = fromState
        self.toState = toState
        self.presentationId = presentationId
        self.timeInPreviousStateMs = timeInPreviousStateMs
    }
}

/// Tracked when a value is set in the state machine
struct SDUIValueSetEvent: AnalyticsEvent {
    static let eventName = "sdk_sdui_value_set"
    
    let variantId: String?
    let key: String
    let value: String
    let presentationId: String
    
    init(variant: SDUIVariantContext, key: String, value: String, presentationId: String) {
        self.variantId = variant.variantId
        self.key = key
        self.value = value
        self.presentationId = presentationId
    }
}

// MARK: - Element Interaction Events

/// Tracked when any SDUI button is tapped
struct SDUIButtonTappedEvent: AnalyticsEvent {
    static let eventName = "sdk_sdui_button_tapped"
    
    let variantId: String?
    let actionType: String       // "close", "claimOffer", "setState", "setValue", "openUrl"
    let presentationId: String
    let currentState: String
    
    init(variant: SDUIVariantContext, actionType: String, presentationId: String, currentState: String) {
        self.variantId = variant.variantId
        self.actionType = actionType
        self.presentationId = presentationId
        self.currentState = currentState
    }
}

/// Tracked when user scrolls in an SDUI scroll view
struct SDUIScrollEvent: AnalyticsEvent {
    static let eventName = "sdk_sdui_scroll"
    
    let variantId: String?
    let scrollAxis: String       // "horizontal", "vertical"
    let scrollPosition: Int      // page/item index
    let presentationId: String
    
    init(variant: SDUIVariantContext, scrollAxis: String, scrollPosition: Int, presentationId: String) {
        self.variantId = variant.variantId
        self.scrollAxis = scrollAxis
        self.scrollPosition = scrollPosition
        self.presentationId = presentationId
    }
}

// MARK: - Render Performance Events
