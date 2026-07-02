// Sources/Encore/Data/Responses.swift
//
// Convenience response wrappers for API data.
// Minimal adapters that bundle what the presentation layer needs.
//

import Foundation

// =============================================================================
// MARK: - Offers Response
// =============================================================================

/// Bundles offers for presentation layer.
/// The OffersRepository handles success/error checking — this just carries the data.
/// Note: Remote configuration is now fetched via /ui-config endpoint on identify(),
/// not from the offers response.
internal struct OfferResponse {
    let offers: [Offer]
    
    init(dto: DTO.Offers.SearchResponse) {
        // Offers are now campaigns directly from the API
        self.offers = dto.offers.map { Campaign(dto: $0) }
    }
    
    /// Number of offers
    var offerCount: Int { offers.count }
    
    /// Alias for presentation layer compatibility
    var offerList: [Offer] { offers }
}

// MARK: - Results and Outcomes

/// Reasons why an entitlement was not granted during offer presentation.
///
/// These represent **business outcomes**, not errors. When a user dismisses
/// an offer or no offers are available, that's a valid outcome—not a failure.
///
/// ## User-Initiated Reasons
///
/// - ``userTappedClose``: User tapped the close button
/// - ``userSwipedDown``: User swiped down to dismiss
/// - ``userTappedOutside``: User tapped outside the sheet
/// - ``userCancelled``: User cancelled mid-flow
/// - ``lastOfferDeclined``: User declined the last available offer
/// - ``dismissed``: Generic dismissal (reason unknown)
///
/// ## System-Initiated Reasons
///
/// - ``noOffersAvailable``: No offers matched this user
/// - ``unsupportedOS``: iOS version doesn't support SwiftUI sheets (< iOS 17)
///
/// ## Handling Not Granted
///
/// ```swift
/// let result = try await Encore.placement().show()
///
/// switch result {
/// case .granted(let entitlement):
///     // User earned something
///     
/// case .notGranted(let reason):
///     switch reason {
///     case .userTappedClose, .userSwipedDown, .dismissed:
///         // User actively dismissed—maybe show later
///         
///     case .noOffersAvailable:
///         // Nothing to show—don't retry immediately
///         
///     case .unsupportedOS:
///         // iOS 16 or earlier—consider fallback UI
///         
///     default:
///         break
///     }
/// }
/// ```
///
/// - Note: Errors (network failures, SDK not configured) are thrown via `try/catch`,
///         not represented as a `NotGrantedReason`.
public enum NotGrantedReason: String, Equatable, Sendable {
    
    // MARK: User-Initiated
    
    /// User tapped the close/X button on the offer sheet.
    case userTappedClose = "user_tapped_close"
    
    /// User swiped down to dismiss the sheet.
    case userSwipedDown = "user_swiped_down"
    
    /// User tapped outside the sheet to dismiss it.
    case userTappedOutside = "user_tapped_outside"
    
    /// User cancelled during the offer flow.
    case userCancelled = "user_cancelled"
    
    /// User declined the last available offer in the carousel.
    case lastOfferDeclined = "last_offer_declined"
    
    /// Generic dismissal when the specific reason is unknown.
    case dismissed = "dismissed"
    
    // MARK: System-Initiated
    
    /// No offers are available for this user.
    ///
    /// This can happen when:
    /// - User doesn't match any campaign targeting criteria
    /// - All campaigns have reached their cap
    /// - User has already claimed available offers
    case noOffersAvailable = "no_offer_available"
    
    /// The user's iOS version doesn't support SwiftUI sheets.
    ///
    /// Requires iOS 17+. On earlier versions, the SDK returns this reason
    /// immediately without showing any UI.
    case unsupportedOS = "unsupported_ios"
    
    // MARK: Experiment-Initiated
    
    /// User is in the Control group of an A/B experiment.
    ///
    /// The "Ghost Trigger" was recorded but no UI was shown.
    /// This is the expected outcome for the NCL Control cohort—it means
    /// the experiment exposure was logged for measurement purposes.
    case experimentControl = "experiment_control"
}


/// The result of presenting an offer sheet to the user.
///
/// This enum represents the two possible outcomes after calling
/// ``Placement/show()``:
///
/// - **Granted**: The user completed an offer and earned an entitlement
/// - **Not Granted**: The user dismissed the sheet or no offers were available
///
/// ## Usage
///
/// ```swift
/// let result = try await Encore.placement("paywall").show()
///
/// switch result {
/// case .granted(let entitlement):
///     switch entitlement {
///     case .credit(let details):
///         print("User earned \(details.amount) credits")
///         unlockPremiumContent()
///         
///     case .freeTrial(let details):
///         print("User started a \(details.durationDays)-day trial")
///         startTrial()
///         
///     case .discount(let details):
///         print("User earned \(details.percentOff)% off")
///         applyDiscount()
///     }
///     
/// case .notGranted(let reason):
///     print("Not granted: \(reason.rawValue)")
///     // Log for analytics, maybe try again later
/// }
/// ```
///
/// - Note: This enum only covers **successful** presentation flows.
///         For **errors** (network failures, SDK not configured), the
///         ``Placement/show()`` method throws an ``EncoreError``.
public enum PresentationResult: Sendable {
    
    /// The user completed an offer and earned an entitlement.
    ///
    /// The associated ``Entitlement`` contains details about what was granted
    /// (credit amount, trial duration, discount percentage, etc.).
    case granted(Entitlement)
    
    /// The user did not earn an entitlement.
    ///
    /// The associated ``NotGrantedReason`` explains why (user dismissed,
    /// no offers available, unsupported OS, etc.).
    case notGranted(NotGrantedReason)
}

/// Legacy name for ``PresentationResult``.
@available(*, deprecated, renamed: "PresentationResult")
public typealias EncorePresentationResult = PresentationResult

// MARK: - Errors
