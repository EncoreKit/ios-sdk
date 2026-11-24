// Why the app shows a placement now, and where it sits: the context the ranker reads at serve time.
// Wire shapes: docs/architecture/serve-context.md.

import Foundation

/// Why your app shows Encore now. Pass it with `placement(_:).moment(_:)`.
public enum Moment: Sendable, Equatable {
    /// Consecutive active periods, such as a 7-day streak.
    case streak(Int)
    /// Progress reached, such as a level.
    case milestone(Int)
    /// Days since the user was last active.
    case lapse(days: Int)
    /// Paywall exits this session.
    case paywallAbandon(Int)
    /// A purchase amount. The SDK sends the device locale's currency; pass `currency` (ISO 4217) only for another one.
    case purchase(amount: Double, currency: String? = nil)
    /// An action with no level, such as a saved photo. `count` is your own lifetime count, if you keep one.
    case action(String, count: Int? = nil)
    /// Anything else, named by your app.
    case custom(String, value: Double? = nil)
}

/// Where a placement sits in your app.
public enum PlacementLocation: String, Sendable, Equatable, CaseIterable {
    case home
    case settings
    case results
    case inFlow = "in_flow"
    case notification
    case email
    case custom
}

/// Your own launcher that opened the sheet. Pass it with `.trigger(_:)`.
public enum TriggerStyle: String, Sendable, Equatable, CaseIterable {
    /// The launcher sits inside a screen, popup or sheet that shows other content, such as a button in a celebration popup.
    case embedded
    /// The launcher is the whole UI that appears, such as a toast, a drop-down notice or a floating badge.
    case standalone
}

// MARK: - Wire

extension Moment {
    /// `context.moment.event`.
    var event: String {
        switch self {
        case .streak: return "streak"
        case .milestone: return "milestone"
        case .lapse: return "lapse"
        case .paywallAbandon: return "paywall_abandon"
        case .purchase: return "purchase"
        case .action: return "action"
        case .custom: return "custom"
        }
    }

    /// `context.moment.value`, in the event's own unit; nil sends no key.
    var value: Double? {
        switch self {
        case .streak(let n), .milestone(let n), .lapse(days: let n), .paywallAbandon(let n): return Double(n)
        case .purchase(let amount, _): return amount
        case .action(_, let count): return count.map(Double.init)
        case .custom(_, let value): return value
        }
    }

    /// `context.moment.label`, normalized; only `action` and `custom` carry one.
    var label: String? {
        switch self {
        case .action(let name, _), .custom(let name, _): return ServeToken.normalize(name, cap: ServeToken.labelCap)
        default: return nil
        }
    }

    /// The developer's ISO 4217 code, uppercased, or nil when none was passed.
    var explicitCurrency: String? {
        guard case .purchase(_, let currency?) = self else { return nil }
        return currency.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// A passed currency that is not 3 letters: the moment is sent with no currency (CONTRACT 1 rule 12).
    var hasInvalidCurrency: Bool {
        guard let code = explicitCurrency else { return false }
        return !(code.count == 3 && code.allSatisfy { $0.isASCII && $0.isLetter })
    }

    /// False for an action or custom moment whose name normalizes to nothing: it is dropped whole.
    var isSendable: Bool { !(event == "action" || event == "custom") || label != nil }

    /// Same event, label and value: the serve for one moment is reusable for another with this key.
    var fingerprint: String {
        [event, label ?? "", value.map { String($0) } ?? "", explicitCurrency ?? ""].joined(separator: "|")
    }
}

/// The token rule of core `normalizeToken` (CONTRACT rule 13). The server applies it again.
internal enum ServeToken {
    static let labelCap = 32
    static let componentIdCap = 64

    /// camelCase to snake_case, lowercase, any other character to `_`, repeats collapsed, trimmed to `cap`.
    /// Nil only when nothing is left.
    static func normalize(_ raw: String, cap: Int) -> String? {
        var snake = raw.replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
        snake = snake.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
        // Per Unicode scalar, as core: every scalar outside a-z and 0-9 becomes `_` ("Cafe\u{301}s" gives "cafe_s").
        let underscore: Unicode.Scalar = "_"
        let mapped = String(String.UnicodeScalarView(snake.lowercased().unicodeScalars.map {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) ? $0 : underscore
        }))
        let collapsed = mapped.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let capped = String(trimmed.prefix(cap)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return capped.isEmpty ? nil : capped
    }
}
