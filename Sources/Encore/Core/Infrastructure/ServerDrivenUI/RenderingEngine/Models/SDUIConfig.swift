//
//  SDUIConfig.swift
//  Encore
//
//  SDUI configuration root and presentation style
//

import Foundation

// MARK: - Presentation Style

/// Presentation style for the offer sheet
enum SDUIPresentationStyle: String, Decodable {
    case sheet = "sheet"
    case fullScreenCover = "fullScreenCover"
    
    /// Default presentation style if not specified
    static var `default`: SDUIPresentationStyle { .sheet }
}

// MARK: - Config Root

struct SDUIConfig: Decodable {
    let version: String
    let root: SDUIElement
    var presentationStyle: SDUIPresentationStyle?
    var presentationDetents: [CGFloat]?
    var cornerRadius: CGFloat?
    var showDragIndicator: Bool?
    
    // NEW: State machine configuration
    /// Starting state for the UI (default: "default")
    var initialState: String?
    
    /// Initial key-value pairs for the values dictionary
    var initialValues: [String: String]?
    
    /// Text lookup maps: mapName -> valueKey -> text template
    /// Example: { "answerTitles": { "expensive": "Don't pay yet. Get ${value} ${unit}" } }
    var textMaps: [String: [String: String]]?
    
    /// State-specific presentation detents
    /// Example: { "question": [0.5], "offers": [0.57, 0.95] }
    var stateDetents: [String: [CGFloat]]?
    
    /// State-specific actions that fire on state entry
    /// Example: { "iap": { "onEnter": { "type": "triggerIAP", "onSuccessState": "thankYou" } } }
    var stateActions: [String: SDUIStateActions]?
    
    // MARK: - IAP-First Flow
    
    /// If true, trigger IAP immediately before showing any UI.
    /// On success, present the offer sheet with `initialState`.
    /// On cancel, dismiss without showing anything.
    var triggerIAPFirst: Bool?
}

// MARK: - State Actions

/// Actions that can be triggered for a state
struct SDUIStateActions: Decodable {
    /// Action to execute when entering this state
    var onEnter: SDUIAction?
}
