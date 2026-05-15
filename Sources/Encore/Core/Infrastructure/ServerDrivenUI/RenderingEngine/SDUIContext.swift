//
//  SDUIContext.swift
//  Encore
//
//  Runtime context for Server-Driven UI - state management, data binding, analytics
//

import SwiftUI

// MARK: - Context for Dynamic Data

class SDUIContext: ObservableObject {
    let offers: [Offer]
    @Published var currentIndex: Int?
    let offerContext: OfferContext
    var onAction: (SDUIAction, Offer?) -> Void
    var onOfferVisible: ((Int) -> Void)?
    
    // Generic state machine
    @Published var currentState: String = "default"
    @Published var values: [String: String] = [:]
    
    // Text lookup maps from config (mapName -> valueKey -> text)
    var textMaps: [String: [String: String]] = [:]
    
    // State-specific presentation detents
    var stateDetents: [String: [CGFloat]] = [:]
    var defaultDetents: [CGFloat]?
    
    // State-specific actions (onEnter, etc.)
    var stateActions: [String: SDUIStateActions] = [:]

    /// When false, claimOffer buttons are disabled and grayed out
    @Published var isClaimEnabled: Bool = true

    // MARK: - Variant Tracking
    
    /// The assigned SDUI variant ID
    var variantId: String?
    
    /// The presentation ID for this session
    var presentationId: String?
    
    /// Timestamp when the current state was entered (for state transition timing)
    private var stateEnteredAt: Date = Date()
    
    /// Count of state transitions in this session
    private(set) var stateTransitionCount: Int = 0
    
    /// Count of offers claimed in this session
    private(set) var offersClaimed: Int = 0
    
    /// Returns the variant context for analytics events
    var variantContext: SDUIVariantContext {
        SDUIVariantContext(
            variantId: variantId
        )
    }
    
    init(
        offers: [Offer],
        currentIndex: Int? = 0,
        offerContext: OfferContext,
        onAction: @escaping (SDUIAction, Offer?) -> Void
    ) {
        self.offers = offers
        self.currentIndex = currentIndex
        self.offerContext = offerContext
        self.onAction = onAction
    }
    
    /// Initialize state machine from config
    /// - Parameter config: The SDUI configuration to initialize from
    /// - Returns: The onEnter action for the initial state, if any
    @discardableResult
    func initializeFromConfig(_ config: SDUIConfig) -> SDUIAction? {
        if let initialState = config.initialState {
            self.currentState = initialState
        }
        if let initialValues = config.initialValues {
            self.values = initialValues
        }
        // Pre-populate selection values from the first offer so templates
        // like ${selectedAdvertiserName} resolve on first render without
        // requiring a user tap. Skips analytics — this is system setup, not
        // a user action.
        if config.autoSelectFirstOffer == true, let first = offers.first {
            writeSelectionValues(for: first, primaryKey: "selectedOfferId")
        }
        if let textMaps = config.textMaps {
            self.textMaps = textMaps
        }
        if let stateDetents = config.stateDetents {
            self.stateDetents = stateDetents
        }
        if let stateActions = config.stateActions {
            self.stateActions = stateActions
        }
        self.defaultDetents = config.presentationDetents
        self.stateEnteredAt = Date()
        
        // Return onEnter action for initial state if it exists
        return stateActions[currentState]?.onEnter
    }
    
    /// Set variant metadata from config manager
    func setVariantMetadata(variantId: String?, presentationId: String?) {
        self.variantId = variantId
        self.presentationId = presentationId
    }
    
    /// Get detents for the current state, falling back to default detents
    func currentDetents() -> [CGFloat]? {
        return stateDetents[currentState] ?? defaultDetents
    }
    
    var currentOffer: Offer? {
        guard let index = currentIndex, offers.indices.contains(index) else { return nil }
        return offers[index]
    }
    
    func resolveText(_ binding: SDUITextBinding) -> String {
        switch binding {
        case .offerAdvertiserName:
            return currentOffer?.advertiserName ?? ""
        case .offerDescription:
            return currentOffer?.creativeAdvertiserDescription ?? ""
        case .offerCtaText:
            return currentOffer?.displayCtaText ?? "Get"
        case .titleText:
            return offerContext.titleText ?? "Get 1 month"
        case .accentTitleText:
            return offerContext.accentTitleText ?? " for free"
        case .subtitleText:
            return offerContext.subtitleText ?? "Claim an exclusive offer and get free access to all features"
        }
    }
    
    func resolveCreativeUrl(_ binding: SDUICreativeBinding, for offer: Offer? = nil) -> String? {
        let targetOffer = offer ?? currentOffer
        switch binding {
        case .offerPrimaryCreative:
            return targetOffer?.displayPrimaryImageUrl
        case .offerLogoImage:
            return targetOffer?.displayLogoUrl
        }
    }
    
    /// Creates a TemplateText that resolves `${variableName}` placeholders.
    /// All properties on `offerContext` (RemoteConfig + IAPContext) are available as placeholders.
    ///
    /// Examples:
    /// - `"Get ${trialValue} ${trialUnit} of ${appName}"` → "Get 1 month of Tinder Plus"
    /// - `"Get ${trialValue} ${trialUnit} of ${appName}"` → "Get 1 month of Tinder Plus" (using aliases)
    /// - `"${accentTitleText}"` → " for free"
    /// - `"Subscribe - ${subscriptionPrice}/month"` → "Subscribe - $4.99/month" (from IAP product info)
    /// - `"Try ${trialDuration} free"` → "Try 7 days free" (from IAP free trial offer)
    /// - `"Get ${trialValue} ${trialUnit} free trial"` → "Get 7 days free trial" (IAP trial overrides native config)
    ///
    /// Note: When IAP has a free trial, `${value}` and `${unit}` use the trial duration from StoreKit,
    /// overriding any native entitlement configuration. If no IAP trial exists, they fall back to
    /// native entitlement values.
    func templateText(_ text: String) -> TemplateText {
        TemplateText(text, context: offerContext)
    }
    
    /// Resolves template placeholders in the given text.
    ///
    /// Resolution order: `offerContext.allVariables` first (remote config +
    /// IAP data), then falls back to `context.values` (state machine values
    /// like `selectedAdvertiserName`). This lets variant authors write
    /// `${selectedAdvertiserName}` in bottom-copy text and have it update
    /// dynamically when the user taps a different offer card.
    func resolveTemplateText(_ text: String) -> String {
        let firstPass = templateText(text).resolved
        // Most templates resolve fully on the first pass; bail before a
        // second O(|values|) scan unless ${...} tokens actually remain.
        guard firstPass.contains("${") else { return firstPass }

        var result = firstPass
        for (key, value) in values {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }
    
    // MARK: - State Machine Methods
    
    /// Resolve text from a text map based on a stored value
    /// - Parameters:
    ///   - mapKey: The name of the text map to use (e.g., "answerTitles")
    ///   - valueKey: The key in the values dictionary to look up (defaults to mapKey if not specified)
    /// - Returns: The resolved text with template placeholders substituted, or nil if not found
    func resolveTextMap(mapKey: String, valueKey: String? = nil) -> String? {
        let lookupKey = valueKey ?? mapKey
        guard let storedValue = values[lookupKey],
              let map = textMaps[mapKey],
              let text = map[storedValue] else {
            return nil
        }
        return resolveTemplateText(text)
    }
    
    /// Set the current state with analytics tracking
    /// Transition to a new state
    /// - Parameter newState: The state to transition to
    /// - Returns: The onEnter action for the new state, if any
    @discardableResult
    func setState(_ newState: String) -> SDUIAction? {
        let previousState = currentState
        let timeInPreviousState = Date().timeIntervalSince(stateEnteredAt) * 1000 // Convert to ms
        
        currentState = newState
        stateEnteredAt = Date()
        stateTransitionCount += 1
        
        // `SDUIStateTransitionEvent` is the canonical screen-view signal — it
        // carries `fromState`, `toState`, and `timeInPreviousStateMs`, which
        // lets downstream funnel analysis filter on `variantId` and derive the
        // screen-viewed event without a duplicate.
        trackStateTransition(from: previousState, to: newState, timeInPreviousStateMs: timeInPreviousState)

        return stateActions[newState]?.onEnter
    }
    
    /// Set a value in the values dictionary with analytics tracking
    func setValue(key: String, value: String) {
        values[key] = value

        // Track value set
        trackValueSet(key: key, value: value)
    }

    /// User-initiated offer selection. Emits a single `SDUIValueSetEvent`
    /// on the primary key (carries the campaignId — the one fact analytics
    /// needs to answer "which offer did the user pick"). The three
    /// derivative fields (advertiserName, logoUrl, description) are
    /// template-rendering conveniences — written directly to `values` so
    /// `${selectedAdvertiserName}` etc. resolve, but not instrumented; the
    /// campaignId on the primary event is enough to join them downstream.
    func selectOffer(_ offer: Offer, primaryKey: String = "selectedOfferId") {
        setValue(key: primaryKey, value: offer.id)
        values["selectedAdvertiserName"] = offer.organization.name
        if let logoUrl = offer.displayLogoUrl {
            values["selectedOfferLogoUrl"] = logoUrl
        }
        if let desc = offer.creativeAdvertiserDescription {
            values["selectedOfferDescription"] = desc
        }
    }

    /// Direct writes without analytics. Used by `initializeFromConfig` to
    /// pre-seed selection state before `presentationId` is even set.
    private func writeSelectionValues(for offer: Offer, primaryKey: String) {
        values[primaryKey] = offer.id
        values["selectedAdvertiserName"] = offer.organization.name
        if let logoUrl = offer.displayLogoUrl {
            values["selectedOfferLogoUrl"] = logoUrl
        }
        if let desc = offer.creativeAdvertiserDescription {
            values["selectedOfferDescription"] = desc
        }
    }
    
    /// Get a value from the values dictionary
    func getValue(key: String) -> String? {
        return values[key]
    }
    
    /// Check if the current state matches the given state
    func isState(_ state: String) -> Bool {
        return currentState == state
    }
    
    /// Check if a value equals a specific value
    func valueEquals(key: String, value: String) -> Bool {
        return values[key] == value
    }
    
    /// Check if a value exists for the given key
    func hasValue(key: String) -> Bool {
        return values[key] != nil
    }
    
    /// Increment the offers claimed counter
    func incrementOffersClaimed() {
        offersClaimed += 1
    }
    
    // MARK: - Analytics Tracking Methods
    
    /// Track a state transition event
    private func trackStateTransition(from: String, to: String, timeInPreviousStateMs: Double) {
        guard let presentationId = presentationId else { return }
        
        let event = SDUIStateTransitionEvent(
            variant: variantContext,
            fromState: from,
            toState: to,
            presentationId: presentationId,
            timeInPreviousStateMs: timeInPreviousStateMs
        )
        analyticsClient?.track(event)
    }
    
    /// Track a value set event
    private func trackValueSet(key: String, value: String) {
        guard let presentationId = presentationId else { return }
        
        let event = SDUIValueSetEvent(
            variant: variantContext,
            key: key,
            value: value,
            presentationId: presentationId
        )
        analyticsClient?.track(event)
    }
    
    /// Track a button tap event
    func trackButtonTap(actionType: SDUIActionType) {
        guard let presentationId = presentationId else { return }
        
        let event = SDUIButtonTappedEvent(
            variant: variantContext,
            actionType: actionType.rawValue,
            presentationId: presentationId,
            currentState: currentState
        )
        analyticsClient?.track(event)
    }
    
    /// Track a scroll event
    func trackScroll(axis: SDUIScrollAxis, position: Int) {
        guard let presentationId = presentationId else { return }
        
        let event = SDUIScrollEvent(
            variant: variantContext,
            scrollAxis: axis.rawValue,
            scrollPosition: position,
            presentationId: presentationId
        )
        analyticsClient?.track(event)
    }

    // MARK: - Appearance

    /// Current app appearance, built once from the session's immutable
    /// `UIValues`. Use this from imperative renderer paths
    /// (`SDUIElementRenderer`) where SwiftUI's `@Environment(\.sduiAppearance)`
    /// isn't available. `ViewModifier`s continue reading from the environment
    /// for consistency and to pick up any env-level overrides.
    lazy var appearance: Appearance = Appearance(from: offerContext.uiValues)

    /// Resolves an optional `SDUIColor` against the current appearance.
    /// Convenience wrapper for terse call sites:
    /// `context.resolveColor(config.color) ?? fallback`.
    func resolveColor(_ color: SDUIColor?) -> Color? {
        color?.resolved(in: appearance)
    }
}
