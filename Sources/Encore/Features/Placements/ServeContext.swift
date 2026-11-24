// What one placement tells `/offers/search` about itself (moment, placement, trigger), and the
// request `context` object built from it plus the automatic device fields. CONTRACT 2.1 to 2.3.

import Foundation

/// An Encore library component that opens a sheet; its id is `context.trigger.componentId`.
internal enum EncoreComponent: String, Sendable, Equatable {
    case giftsButton = "gifts_button"
    case encoreClaim = "encore_claim"
    case claimReminder = "claim_reminder"
}

/// How the sheet is drawn: Encore's window, or a controller the host places.
internal enum PlacementSurface: String, Sendable, Equatable {
    case fullSheet = "full_sheet"
    case embedded
}

/// The per-placement context a builder or component carries to the serve.
internal struct PlacementContext: Sendable, Equatable {
    var moment: Moment?
    var location: PlacementLocation?
    var trigger: TriggerStyle?
    var component: EncoreComponent?
    /// A user tap opened this sheet; false for an auto pop and for a code-called `show()`.
    var tapped = false
    var surface: PlacementSurface = .fullSheet
    /// Which copy the sheet's headline uses (decision g); the SDK fills it for each search.
    var headlineCopySource: String?

    /// `user` when a component tap or an app-declared trigger opened the sheet; else absent (D14).
    var initiation: String? {
        (component != nil && tapped) || trigger != nil ? "user" : nil
    }

    /// The key a reused serve must match (handle rule 3).
    var momentFingerprint: String? { moment?.fingerprint }
}

// MARK: - Wire

/// `context` on `/offers/search`. Every key is optional; nil keys are not encoded.
internal struct SearchContextPayload: Encodable, Equatable {
    struct MomentPayload: Encodable, Equatable {
        let event: String
        let value: Double?
        let label: String?
        let currency: String?
    }
    struct PlacementPayload: Encodable, Equatable {
        var location: String?
        var surface: String?
        var persistence: String?
        var author: String?
    }
    struct TriggerPayload: Encodable, Equatable {
        var surface: String?
        var author: String?
        var componentId: String?
    }
    struct DevicePayload: Encodable, Equatable {
        var model: String?
        var connectionType: String?
        var lowPowerMode: Bool?
        var networkRttMs: Int?
        var type: String?
    }

    var moment: MomentPayload?
    var initiation: String?
    var placement: PlacementPayload?
    var trigger: TriggerPayload?
    var device: DevicePayload?
    var timeZone: String?
    var appVersion: String?
    var offersRenderMs: Int?
    var headlineCopySource: String?

    init(placement context: PlacementContext?, device: DeviceSignals?, storefrontCurrency: String?, headlineCopySource: String? = nil) {
        if let context { apply(context, storefrontCurrency: storefrontCurrency) }
        if let device { apply(device) }
        self.headlineCopySource = context?.headlineCopySource ?? headlineCopySource
    }

    private mutating func apply(_ context: PlacementContext, storefrontCurrency: String?) {
        if let moment = context.moment {
            if moment.isSendable {
                let currency: String?
                if moment.hasInvalidCurrency {
                    // The amount is in some currency the SDK cannot name: never guess the locale's.
                    TriggerLog.once("moment.currency", "[INTEGRATION] .purchase currency must be a 3-letter ISO 4217 code; sent with no currency")
                    currency = nil
                } else {
                    currency = moment.event == "purchase" ? (moment.explicitCurrency ?? storefrontCurrency) : nil
                }
                // A NaN or infinite value would fail the whole request's encode: it is sent as absent.
                let value = moment.value.flatMap { $0.isFinite ? $0 : nil }
                self.moment = MomentPayload(event: moment.event, value: value, label: moment.label, currency: currency)
            }
        }
        initiation = context.initiation
        placement = PlacementPayload(
            location: context.location?.rawValue, surface: context.surface.rawValue,
            persistence: "until_dismissed", author: "encore"
        )
        if let component = context.component {
            trigger = TriggerPayload(
                surface: TriggerStyle.embedded.rawValue, author: "encore",
                componentId: ServeToken.normalize(component.rawValue, cap: ServeToken.componentIdCap)
            )
        } else if let style = context.trigger {
            trigger = TriggerPayload(surface: style.rawValue, author: "app")
        }
    }

    private mutating func apply(_ signals: DeviceSignals) {
        let device = DevicePayload(
            model: signals.model, connectionType: signals.connectionType,
            lowPowerMode: signals.lowPowerMode ? true : nil, networkRttMs: signals.networkRttMs, type: signals.type
        )
        if device != DevicePayload() { self.device = device }
        timeZone = signals.timeZone
        appVersion = signals.appVersion
        offersRenderMs = signals.offersRenderMs
    }
}

extension EncoreComponent {
    /// The component a trigger id names; nil for a trigger that is not a library component.
    init?(triggerId: String) {
        switch triggerId {
        case GiftsButtonTrigger.id: self = .giftsButton
        case ClaimReminderTrigger.id: self = .claimReminder
        case CustomClaimRules.trigger: self = .encoreClaim
        default: return nil
        }
    }
}

/// Which copy a sheet's headline uses (decision g), in the order the sheet resolves it.
internal enum HeadlineCopySource {
    static let sdkOverride = "sdk_override"
    static let config = "config"
    static let template = "template"

    static func resolve(useCase: UseCase, overrides: [String: String], uiValues: UIValues?) -> String {
        if Self.present(overrides[useCase.headlineVariable]) { return sdkOverride }
        if Self.present(OfferContext(uiValues: uiValues, useCase: useCase, servedLocale: nil).allVariables[useCase.headlineVariable]) { return config }
        return template
    }

    private static func present(_ text: String?) -> Bool {
        !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
