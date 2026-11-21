// A look's presentation mode (vocab §2.11): drawn in its slot (inline, the absent key) or by the SDK
// over the screen in a popup, a half sheet or a full-screen cover, with its slot rules (2.8.0). The
// server picks the mode per look.

import Foundation

/// How Encore drew a look over the screen, outside any slot: a centred popup, a half sheet from the
/// bottom, or a full-screen cover. Encore picks it per look; your app never chooses one.
public enum PresentedMode: String, CaseIterable, Sendable, Hashable {
    case popup
    case halfSheet
    case fullScreen
}

/// A mode the SDK draws a look in outside its slot. Inline is the absence of one.
internal typealias TriggerPresentationMode = PresentedMode

/// What a presented look's slot does while and after its container (vocab §2.11 `slot`, 2.8.0).
internal struct TriggerSlotRules: Equatable, Sendable {
    enum WhilePresented: String, Sendable { case hidden, inline }
    enum AfterClose: String, Sendable { case inline, hidden }

    /// The inline look the server answers the slot with when the popup cannot or did not show.
    /// The SDK only passes it on: the server resolves it.
    var inlineLayout: String? = nil
    /// `inline` draws the companion in the slot while the container is up (mode 4).
    var whilePresented: WhilePresented = .hidden
    /// `hidden` keeps the slot empty after the container, with no inline re-ask (mode 3).
    var afterClose: AfterClose = .inline
}

/// A presented look's mode, its wait, its caps and its slot rules, as the template names them.
internal struct TriggerPresented: Equatable, Sendable {
    let mode: TriggerPresentationMode
    /// `timing.delayMs`: how long to wait once the slot is first visible.
    var delayMs: Int = 0
    /// `caps.minDaysBetween`: local days between two at a placement; only ever tightens the default.
    var minDaysBetween: Int? = nil
    /// `caps.dismissBackoffDays`: days inline only after two dismissals in a row; only ever tightens.
    var dismissBackoffDays: Int? = nil
    /// `caps.maxPerDay`: shows a day at the placement, and the day limit across placements lifted to it, up to the fixture ceiling.
    var maxPerDay: Int? = nil
    /// `caps.maxPerSession`: shows an app session, loosened up to the fixture ceiling.
    var maxPerSession: Int? = nil
    var slot = TriggerSlotRules()

    static let delayRange: ClosedRange<Double> = 0...3000
    static let minDaysBetweenRange: ClosedRange<Double> = 1...30
    static let dismissBackoffDaysRange: ClosedRange<Double> = 3...30
    static let maxPerDayRange: ClosedRange<Double> = 1...10
    static let maxPerSessionRange: ClosedRange<Double> = 1...3

    /// The sub-keys each block may hold, with their ranges.
    private static let blocks: [String: [String: ClosedRange<Double>]] = [
        "timing": ["delayMs": delayRange],
        "caps": [
            "minDaysBetween": minDaysBetweenRange, "dismissBackoffDays": dismissBackoffDaysRange,
            "maxPerDay": maxPerDayRange, "maxPerSession": maxPerSessionRange,
        ],
    ]

    /// The four keys as served (nil when absent), read the way the backend's `presentationProblems`
    /// refuses them: an unknown or written-out inline mode, timing, caps or slot on an inline look, an
    /// unknown sub-key, a number that is not whole or not in range, and a slot value outside its words.
    /// Nil success is an inline look.
    static func read(presentation: JSONValue?, timing: JSONValue?, caps: JSONValue?, slot: JSONValue? = nil) -> Result<TriggerPresented?, TriggerUnrenderable> {
        var mode: TriggerPresentationMode?
        if let presentation {
            guard case .string(let name) = presentation, let named = TriggerPresentationMode(rawValue: name) else {
                return .failure(TriggerUnrenderable(path: "presentation", detail: "not popup, halfSheet or fullScreen; inline is the absent key"))
            }
            mode = named
        }
        var numbers: [String: Int] = [:]
        for (name, block) in [("timing", timing), ("caps", caps)] {
            guard let block else { continue }
            guard mode != nil else {
                return .failure(TriggerUnrenderable(path: name, detail: "only a presented look (popup, halfSheet or fullScreen) has \(name)"))
            }
            guard case .object(let fields) = block, let allowed = blocks[name] else {
                return .failure(TriggerUnrenderable(path: name, detail: "expected an object"))
            }
            for field in fields.keys.sorted() {
                let path = "\(name).\(field)"
                guard let range = allowed[field] else {
                    return .failure(TriggerUnrenderable(path: path, detail: "not a \(name) key"))
                }
                guard case .number(let number)? = fields[field], number.isFinite, number == number.rounded() else {
                    return .failure(TriggerUnrenderable(path: path, detail: "expected a whole number"))
                }
                guard range.contains(number) else {
                    return .failure(TriggerUnrenderable(path: path, detail: "\(number) outside \(range.lowerBound)...\(range.upperBound)"))
                }
                numbers[path] = Int(number)
            }
        }
        var rules = TriggerSlotRules()
        if let slot {
            guard mode != nil else {
                return .failure(TriggerUnrenderable(path: "slot", detail: "only a presented look (popup, halfSheet or fullScreen) has slot"))
            }
            switch readSlot(slot) {
            case .success(let read): rules = read
            case .failure(let problem): return .failure(problem)
            }
        }
        guard let mode else { return .success(nil) }
        return .success(TriggerPresented(
            mode: mode, delayMs: numbers["timing.delayMs"] ?? 0,
            minDaysBetween: numbers["caps.minDaysBetween"], dismissBackoffDays: numbers["caps.dismissBackoffDays"],
            maxPerDay: numbers["caps.maxPerDay"], maxPerSession: numbers["caps.maxPerSession"], slot: rules
        ))
    }

    /// The `slot` block: `inlineLayout` a layout name, `whilePresented` hidden or inline, `afterClose` inline or hidden.
    private static func readSlot(_ slot: JSONValue) -> Result<TriggerSlotRules, TriggerUnrenderable> {
        guard case .object(let fields) = slot else { return .failure(TriggerUnrenderable(path: "slot", detail: "expected an object")) }
        var rules = TriggerSlotRules()
        for field in fields.keys.sorted() {
            let path = "slot.\(field)"
            switch field {
            case "inlineLayout":
                guard case .string(let layout)? = fields[field], !layout.isEmpty, layout.count <= 64 else {
                    return .failure(TriggerUnrenderable(path: path, detail: "expected a layout name"))
                }
                rules.inlineLayout = layout
            case "whilePresented":
                guard case .string(let word)? = fields[field], let value = TriggerSlotRules.WhilePresented(rawValue: word) else {
                    return .failure(TriggerUnrenderable(path: path, detail: "hidden or inline"))
                }
                rules.whilePresented = value
            case "afterClose":
                guard case .string(let word)? = fields[field], let value = TriggerSlotRules.AfterClose(rawValue: word) else {
                    return .failure(TriggerUnrenderable(path: path, detail: "inline or hidden"))
                }
                rules.afterClose = value
            default:
                return .failure(TriggerUnrenderable(path: path, detail: "not a slot key"))
            }
        }
        return .success(rules)
    }
}

/// The modes a request says this mount can draw (`presentations=`). It reports capability, never a
/// publisher choice, and joins the trigger cache key, so each list has its own answer.
internal struct TriggerPresentations: Hashable, Sendable {
    /// Whether a look may be drawn in the slot.
    var inline: Bool
    /// The presented modes, in wire order.
    var modes: [TriggerPresentationMode]

    /// A 2.8.0 mount: every mode where trigger looks draw at all (iOS 17), else inline only.
    static var mount: Self {
        if #available(iOS 17.0, *) { return Self(inline: true, modes: TriggerPresentationMode.allCases) }
        return inlineOnly
    }
    /// After a mount's container closed or a limit held it back: the slot's own look.
    static let inlineOnly = Self(inline: true, modes: [])
    /// The claim handle's ``EncoreClaim/present()``: it has no slot to draw in.
    static let presentedOnly = Self(inline: false, modes: TriggerPresentationMode.allCases)

    /// `inline,popup,halfSheet,fullScreen`.
    var wire: String { ((inline ? ["inline"] : []) + modes.map(\.rawValue)).joined(separator: ",") }

    /// Whether a look of `mode` (nil: inline) is one this list asked for (the SDK's last guard).
    func allows(_ mode: TriggerPresentationMode?) -> Bool {
        mode.map(modes.contains) ?? inline
    }
}
