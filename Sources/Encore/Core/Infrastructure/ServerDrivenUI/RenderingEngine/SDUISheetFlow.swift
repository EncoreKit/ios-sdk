// Motion between a sheet's screens: `style.exit`, a `setState` `transition`, completion and timed actions,
// and `persistKey`. Contract: backend docs/architecture/sdui-sheet-motion.md, "Layer 3: between screens".

import SwiftUI
import UIKit

// MARK: - Checks

extension SheetMotionRules {
    /// The only actions a completion or a timer may fire: nothing that claims, selects, buys, shares or opens.
    static let flowActionTypes: Set<String> = ["setState", "setValue", "close"]

    /// Why a completion or timed action cannot fire without a tap, or nil.
    static func flowActionProblem(_ raw: SkinJSON?) -> String? {
        guard let action = raw?.object, let type = action["type"]?.string else { return "must be an action with a type" }
        guard flowActionTypes.contains(type) else { return "must be setState, setValue or close, not \(type)" }
        if type == "setState", (action["setState"]?.string ?? "").isEmpty { return "setState needs a state" }
        if type == "setValue", (action["setValueKey"]?.string ?? "").isEmpty { return "setValue needs setValueKey" }
        if type == "setValue", action["setValueValue"]?.string == nil { return "setValue needs a literal setValueValue" }
        return nil
    }

    /// Why `style.exit` (or a transition's `exit`) cannot run, or nil. Its `delay` + `duration` is at most 2 s.
    static func exitProblem(_ raw: SkinJSON) -> String? {
        guard let exit = raw.object else { return "must be an object" }
        if let pose = poseProblem(exit["to"]?.object, name: "to") { return pose }
        return blockTimingProblem(exit)
    }

    /// Why a transition's `enter` cannot run, or nil: an entrance block within the 2 s cap.
    static func transitionEnterProblem(_ raw: SkinJSON) -> String? {
        guard let enter = raw.object else { return "must be an object" }
        if let pose = poseProblem(enter["from"]?.object, name: "from") { return pose }
        return blockTimingProblem(enter)
    }

    private static func blockTimingProblem(_ block: SkinObject) -> String? {
        guard let duration = block["duration"]?.number, duration.isFinite, duration > 0 else { return "duration must be above 0" }
        if !isAbsent(block["delay"]), !isWithin(block["delay"], 0, 2) { return "delay must be a number from 0 to 2" }
        if !isAbsent(block["curve"]), !isLoopCurve(block["curve"]) { return "curve must be linear, easeIn, easeOut or easeInOut" }
        guard (block["delay"]?.number ?? 0) + duration <= 2 else { return "delay plus duration must be at most 2" }
        return nil
    }

    /// Why a `setState` `transition` cannot run, or nil.
    static func transitionProblem(_ raw: SkinJSON) -> String? {
        guard let transition = raw.object else { return "must be an object" }
        guard !isAbsent(transition["exit"]) || !isAbsent(transition["enter"]) else { return "needs an exit or an enter" }
        if !isAbsent(transition["exit"]), let problem = transition["exit"].flatMap(exitProblem) { return "exit \(problem)" }
        if !isAbsent(transition["enter"]), let problem = transition["enter"].flatMap(transitionEnterProblem) { return "enter \(problem)" }
        if !isAbsent(transition["overlap"]), !["together", "sequential"].contains(transition["overlap"]?.string ?? "") {
            return "overlap must be together or sequential"
        }
        return nil
    }

    /// Why `after` cannot fire, or nil.
    static func afterProblem(_ raw: SkinJSON) -> String? {
        guard let after = raw.object else { return "must be an object" }
        guard isWithin(after["seconds"], 0, 30) else { return "seconds must be a number from 0 to 30" }
        if let problem = flowActionProblem(after["action"]) { return "action \(problem)" }
        return nil
    }

    static func persistKeyProblem(_ raw: SkinJSON) -> String? {
        guard let key = raw.string, (1...64).contains(key.count) else { return "must be a string of 1 to 64 characters" }
        return nil
    }

    /// `pose` without a bad `offsetFraction`, warning once for it, so the rest of the pose still runs.
    static func cleanPose(_ pose: SkinObject, path: String, warn: (String) -> Void) {
        guard !isAbsent(pose["offsetFraction"]), let problem = offsetFractionProblem(pose["offsetFraction"]) else { return }
        warn("dropped \(path).offsetFraction: \(problem.replacingOccurrences(of: "offsetFraction ", with: ""))")
        pose["offsetFraction"] = nil
    }

    /// A copy of a served `enter` with each bad layer 3 key dropped on its own.
    static func cleanEnter(_ raw: SkinJSON, warn: (String) -> Void) -> SkinJSON {
        let copy = raw.deepCopy()
        guard let enter = copy.object else { return copy }
        if let from = enter["from"]?.object { cleanPose(from, path: "enter.from", warn: warn) }
        if !isAbsent(enter["onComplete"]), let problem = flowActionProblem(enter["onComplete"]) {
            warn("dropped enter.onComplete: \(problem)")
            enter["onComplete"] = nil
        }
        return copy
    }

    /// A copy of a served sheet `loop` with each bad layer 3 key dropped on its own.
    static func cleanLoop(_ raw: SkinJSON, warn: (String) -> Void) -> SkinJSON {
        let copy = raw.deepCopy()
        guard let loop = copy.object else { return copy }
        if case .array(let frames)? = loop["keyframes"] {
            for (index, frame) in frames.enumerated() {
                if let pose = frame.object { cleanPose(pose, path: "loop.keyframes[\(index)]", warn: warn) }
            }
        }
        if let reduced = loop["reducedMotion"]?.object { cleanPose(reduced, path: "loop.reducedMotion", warn: warn) }
        if !isAbsent(loop["onComplete"]) {
            if isAbsent(loop["repeatCount"]) {
                warn("dropped loop.onComplete: a loop without repeatCount never ends")
                loop["onComplete"] = nil
            } else if let problem = flowActionProblem(loop["onComplete"]) {
                warn("dropped loop.onComplete: \(problem)")
                loop["onComplete"] = nil
            }
        }
        return copy
    }

    /// A copy of a served `exit` (or transition block) with a bad `offsetFraction` dropped on its own.
    static func cleanBlock(_ raw: SkinJSON, pose key: String, path: String, warn: (String) -> Void) -> SkinJSON {
        let copy = raw.deepCopy()
        if let pose = copy.object?[key]?.object { cleanPose(pose, path: "\(path).\(key)", warn: warn) }
        return copy
    }
}

/// Logs a dropped layer 3 key, the way the other sheet motion keys warn.
func sduiFlowWarn(_ message: String) {
    Logger.warn(.presentation, "[SDUI] \(message.prefix(1).uppercased() + message.dropFirst())")
}

// MARK: - Model

/// `style.exit` or a transition's `exit`: from the element's own pose to `to`, once, when it leaves.
struct SDUIExit: Decodable {
    let to: SDUIMotionPose
    let duration: Double
    var delay: Double?
    var curve: SDUIAnimationCurve?

    /// Seconds from the `setState` to the end pose.
    var totalDuration: Double { (delay ?? 0) + duration }

    /// The exit's transform `elapsed` seconds after the `setState`; nil curve eases out, as `enter` does.
    func frame(running elapsed: TimeInterval) -> SDUILoopFrame {
        let progress = (elapsed - (delay ?? 0)) / duration
        return to.frame.scaled(by: SDUILoopFrame.eased(progress, curve ?? .easeOut))
    }
}

/// A `setState` `transition`: poses for the outermost branches it removes and adds. A class, because an
/// entrance can carry an `onComplete` action, which can carry a transition again.
final class SDUIStateTransitionSpec: Decodable {
    let exit: SDUIExit?
    let enter: SDUIEnter?
    let overlap: String?

    var sequential: Bool { overlap == "sequential" }
}

/// `after`: fire `action` once `seconds` of the sheet being on screen have passed since the element appeared.
struct SDUITimedAction: Decodable {
    let seconds: Double
    let action: SDUIAction
}

/// `persistKey`, wrapped so the style's synthesised decoder never reads a bare string for it.
struct SDUIPersistKey: Decodable, Equatable {
    let value: String
}

extension KeyedDecodingContainer {
    /// A sheet drops an exit this build cannot run with one warning; a trigger ignores the key.
    func decodeIfPresent(_ type: SDUIExit.Type, forKey key: K) throws -> SDUIExit? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let decoder = try superDecoder(forKey: key)
        if decoder.isTriggerMount { return nil }
        guard let raw = decoder.motionJSON else { return nil }
        let cleaned = SheetMotionRules.cleanBlock(raw, pose: "to", path: "exit", warn: sduiFlowWarn)
        if let problem = SheetMotionRules.exitProblem(cleaned) {
            sduiFlowWarn("dropped a sheet exit: \(problem)")
            return nil
        }
        return try? JSONDecoder().decode(SDUIExit.self, from: cleaned.serialized())
    }

    /// A bad transition drops only the transition: the `setState` still changes the screen, at once.
    func decodeIfPresent(_ type: SDUIStateTransitionSpec.Type, forKey key: K) throws -> SDUIStateTransitionSpec? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let decoder = try superDecoder(forKey: key)
        if decoder.isTriggerMount { return nil }
        guard let raw = decoder.motionJSON else { return nil }
        let copy = raw.deepCopy()
        if let exit = copy.object?["exit"]?.object?["to"]?.object { SheetMotionRules.cleanPose(exit, path: "transition.exit.to", warn: sduiFlowWarn) }
        if let enter = copy.object?["enter"]?.object?["from"]?.object { SheetMotionRules.cleanPose(enter, path: "transition.enter.from", warn: sduiFlowWarn) }
        if let problem = SheetMotionRules.transitionProblem(copy) {
            sduiFlowWarn("dropped a transition: \(problem)")
            return nil
        }
        return try? JSONDecoder().decode(SDUIStateTransitionSpec.self, from: copy.serialized())
    }

    /// The style never reads `after` or `persistKey`; the element decoder does.
    func decodeIfPresent(_ type: SDUITimedAction.Type, forKey key: K) throws -> SDUITimedAction? { nil }
    func decodeIfPresent(_ type: SDUIPersistKey.Type, forKey key: K) throws -> SDUIPersistKey? { nil }
}

/// An element payload with a style of its own.
protocol SDUIStyleHolder { var style: SDUIStyle? { get set } }
extension SDUIText: SDUIStyleHolder {}
extension SDUISystemImage: SDUIStyleHolder {}
extension SDUIAsyncImage: SDUIStyleHolder {}
extension SDUIAsyncVideo: SDUIStyleHolder {}
extension SDUIAppIcon: SDUIStyleHolder {}
extension SDUIButton: SDUIStyleHolder {}
extension SDUIStack: SDUIStyleHolder {}
extension SDUISpacer: SDUIStyleHolder {}
extension SDUIShape: SDUIStyleHolder {}
extension SDUIGradient: SDUIStyleHolder {}
extension SDUIScrollView: SDUIStyleHolder {}
extension SDUIGroup: SDUIStyleHolder {}
extension SDUITextField: SDUIStyleHolder {}
extension SDUIToggle: SDUIStyleHolder {}
extension SDUISlideButton: SDUIStyleHolder {}
extension SDUIConfetti: SDUIStyleHolder {}
extension SDUIProgress: SDUIStyleHolder {}
extension SDUIMarquee: SDUIStyleHolder {}
extension SDUIForEach: SDUIStyleHolder {}

/// The element-level layer 3 keys the element decoder reads beside the element's own properties.
enum SDUIFlowElementKey: String, CodingKey { case after, persistKey }

extension SDUIElement {
    /// Reads `after` and `persistKey` from the element's properties into its style. A bad one drops only itself.
    func withFlowKeys(_ props: KeyedDecodingContainer<SDUIFlowElementKey>) -> SDUIElement {
        var after: SDUITimedAction?
        var persistKey: SDUIPersistKey?
        if props.contains(.after), let raw = (try? props.superDecoder(forKey: .after))?.motionJSON {
            if let problem = SheetMotionRules.afterProblem(raw) {
                sduiFlowWarn("dropped after: \(problem)")
            } else {
                after = try? JSONDecoder().decode(SDUITimedAction.self, from: raw.serialized())
            }
        }
        if props.contains(.persistKey), let raw = (try? props.superDecoder(forKey: .persistKey))?.motionJSON {
            if let problem = SheetMotionRules.persistKeyProblem(raw) {
                sduiFlowWarn("dropped persistKey: \(problem)")
            } else {
                persistKey = raw.string.map(SDUIPersistKey.init)
            }
        }
        guard after != nil || persistKey != nil else { return self }
        return editingStyle(missing: "after or persistKey") { style in
            if let after { style.after = after }
            if let persistKey { style.persistKey = persistKey }
        }
    }

    /// The element with its style changed by `edit`; one with no style of its own warns once per kind.
    func editingStyle(missing what: String, _ edit: (inout SDUIStyle) -> Void) -> SDUIElement {
        if let edited = restyled(edit) { return edited }
        SDUILottieWarnings.once("flow:\(kindName)", "[SDUI] Dropped \(what): a \(kindName) has no style of its own")
        return self
    }

    /// The element with its style changed by `edit`, or nil for a kind with no style. Each kind goes through one
    /// generic step, so a frame holds one payload: a switch binding every payload overflowed a Debug decode off main.
    func restyled(_ edit: (inout SDUIStyle) -> Void) -> SDUIElement? {
        switch self {
        case .text: return Self.restyle(self, { if case .text(let e) = $0 { e } else { nil } }, SDUIElement.text, edit)
        case .systemImage: return Self.restyle(self, { if case .systemImage(let e) = $0 { e } else { nil } }, SDUIElement.systemImage, edit)
        case .asyncImage: return Self.restyle(self, { if case .asyncImage(let e) = $0 { e } else { nil } }, SDUIElement.asyncImage, edit)
        case .asyncVideo: return Self.restyle(self, { if case .asyncVideo(let e) = $0 { e } else { nil } }, SDUIElement.asyncVideo, edit)
        case .appIcon: return Self.restyle(self, { if case .appIcon(let e) = $0 { e } else { nil } }, SDUIElement.appIcon, edit)
        case .button: return Self.restyle(self, { if case .button(let e) = $0 { e } else { nil } }, SDUIElement.button, edit)
        case .vStack: return Self.restyle(self, { if case .vStack(let e) = $0 { e } else { nil } }, SDUIElement.vStack, edit)
        case .hStack: return Self.restyle(self, { if case .hStack(let e) = $0 { e } else { nil } }, SDUIElement.hStack, edit)
        case .zStack: return Self.restyle(self, { if case .zStack(let e) = $0 { e } else { nil } }, SDUIElement.zStack, edit)
        case .spacer: return Self.restyle(self, { if case .spacer(let e) = $0 { e } else { nil } }, SDUIElement.spacer, edit)
        case .shape: return Self.restyle(self, { if case .shape(let e) = $0 { e } else { nil } }, SDUIElement.shape, edit)
        case .gradient: return Self.restyle(self, { if case .gradient(let e) = $0 { e } else { nil } }, SDUIElement.gradient, edit)
        case .scrollView: return Self.restyle(self, { if case .scrollView(let e) = $0 { e } else { nil } }, SDUIElement.scrollView, edit)
        case .group: return Self.restyle(self, { if case .group(let e) = $0 { e } else { nil } }, SDUIElement.group, edit)
        case .textField: return Self.restyle(self, { if case .textField(let e) = $0 { e } else { nil } }, SDUIElement.textField, edit)
        case .toggle: return Self.restyle(self, { if case .toggle(let e) = $0 { e } else { nil } }, SDUIElement.toggle, edit)
        case .slideButton: return Self.restyle(self, { if case .slideButton(let e) = $0 { e } else { nil } }, SDUIElement.slideButton, edit)
        case .confetti: return Self.restyle(self, { if case .confetti(let e) = $0 { e } else { nil } }, SDUIElement.confetti, edit)
        case .progress: return Self.restyle(self, { if case .progress(let e) = $0 { e } else { nil } }, SDUIElement.progress, edit)
        case .marquee: return Self.restyle(self, { if case .marquee(let e) = $0 { e } else { nil } }, SDUIElement.marquee, edit)
        case .forEach, .conditional, .compactPageIndicator, .empty: return nil
        }
    }

    @inline(never)
    private static func remap<T>(_ element: SDUIElement, _ extract: (SDUIElement) -> T?, _ wrap: (T) -> SDUIElement, _ body: (inout T) -> Void) -> SDUIElement {
        guard var payload = extract(element) else { return element }
        body(&payload)
        return wrap(payload)
    }

    @inline(never)
    private static func restyle<T: SDUIStyleHolder>(
        _ element: SDUIElement, _ extract: (SDUIElement) -> T?, _ wrap: (T) -> SDUIElement, _ edit: (inout SDUIStyle) -> Void
    ) -> SDUIElement {
        guard var payload = extract(element) else { return element }
        var style = payload.style ?? SDUIStyle()
        edit(&style)
        payload.style = style
        return wrap(payload)
    }

    /// The longest drawn `style.exit` in this subtree, in seconds. A nested conditional counts only the branch
    /// `matches` picks; a kept element (`persistKey` in `kept`) never draws its exit, so its exit holds nothing.
    func longestExit(skipping kept: Set<String>, matches: (SDUICondition) -> Bool) -> TimeInterval {
        let own = style?.persistKey.map { kept.contains($0.value) } == true ? 0 : style?.exit?.totalDuration ?? 0
        let drawn: [SDUIElement]
        if case .conditional(let c) = self {
            drawn = matches(c.condition) ? [c.ifTrue] : (c.ifFalse.map { [$0] } ?? [])
        } else {
            drawn = children
        }
        return drawn.reduce(own) { max($0, $1.longestExit(skipping: kept, matches: matches)) }
    }

    /// Every `persistKey` in this subtree.
    var persistKeys: Set<String> {
        var keys = Set(style?.persistKey.map { [$0.value] } ?? [])
        for child in children { keys.formUnion(child.persistKeys) }
        return keys
    }

    /// The tree with a `persistKey` held once on each state's screen (backend `duplicateKeyProblems`): per state, a
    /// `stateEquals` conditional draws one branch, any other either, and a later repeat drops its key with one warning.
    func checkedScreenKeys(initialState: String) -> SDUIElement {
        // The rebuild recurses with large values and overflowed a background decode's stack, so skip it when no key exists.
        guard !persistKeys.isEmpty else { return self }
        var states = [initialState]
        func collect(_ e: SDUIElement) {
            if case .conditional(let c) = e { c.condition.namedStates.forEach { if !states.contains($0) { states.append($0) } } }
            e.children.forEach(collect)
        }
        collect(self)
        var element = self, warned = Set<String>()
        for state in states {
            var seen = Set<String>()
            element = element.firstPersistKeysOnly(in: state, seen: &seen, warned: &warned)
        }
        return element
    }

    private func firstPersistKeysOnly(in state: String, seen: inout Set<String>, warned: inout Set<String>) -> SDUIElement {
        var element = self
        if let key = style?.persistKey?.value {
            if seen.contains(key) {
                if warned.insert(key).inserted { sduiFlowWarn("dropped persistKey \"\(key)\": one screen holds it more than once, so the first keeps it") }
                element = element.editingStyle(missing: "persistKey") { $0.persistKey = nil }
            } else {
                seen.insert(key)
            }
        }
        if case .conditional(var conditional) = element {
            // The two branches are never drawn together, so each starts from what came before it.
            let decided = conditional.condition.decided(in: state)
            var whenTrue = seen, whenFalse = seen
            if decided != false { conditional.ifTrue = conditional.ifTrue.firstPersistKeysOnly(in: state, seen: &whenTrue, warned: &warned) }
            if decided != true { conditional.ifFalse = conditional.ifFalse?.firstPersistKeysOnly(in: state, seen: &whenFalse, warned: &warned) }
            seen = whenTrue.union(whenFalse)
            return .conditional(conditional)
        }
        return element.mappingChildren { $0.firstPersistKeysOnly(in: state, seen: &seen, warned: &warned) }
    }

    /// The element with each child, overlay and background replaced by `transform`. A forEach row template is
    /// left alone: every row draws it.
    func mappingChildren(_ transform: (SDUIElement) -> SDUIElement) -> SDUIElement {
        // One generic step per kind, as in `restyled`: a frame holding every payload overflowed a Debug decode's stack.
        let element: SDUIElement
        switch self {
        case .button: element = Self.remap(self, { if case .button(let e) = $0 { e } else { nil } }, SDUIElement.button) { $0.content = transform($0.content) }
        case .vStack: element = Self.remap(self, { if case .vStack(let e) = $0 { e } else { nil } }, SDUIElement.vStack) { $0.children = $0.children.map(transform) }
        case .hStack: element = Self.remap(self, { if case .hStack(let e) = $0 { e } else { nil } }, SDUIElement.hStack) { $0.children = $0.children.map(transform) }
        case .zStack: element = Self.remap(self, { if case .zStack(let e) = $0 { e } else { nil } }, SDUIElement.zStack) { $0.children = $0.children.map(transform) }
        case .scrollView: element = Self.remap(self, { if case .scrollView(let e) = $0 { e } else { nil } }, SDUIElement.scrollView) { $0.content = transform($0.content) }
        case .group: element = Self.remap(self, { if case .group(let e) = $0 { e } else { nil } }, SDUIElement.group) { $0.content = transform($0.content) }
        case .toggle: element = Self.remap(self, { if case .toggle(let e) = $0 { e } else { nil } }, SDUIElement.toggle) { $0.label = transform($0.label) }
        case .marquee: element = Self.remap(self, { if case .marquee(let e) = $0 { e } else { nil } }, SDUIElement.marquee) { $0.content = transform($0.content) }
        case .asyncImage: element = Self.remap(self, { if case .asyncImage(let e) = $0 { e } else { nil } }, SDUIElement.asyncImage) { $0.fallback = $0.fallback.map(transform) }
        case .conditional:
            element = Self.remap(self, { if case .conditional(let e) = $0 { e } else { nil } }, SDUIElement.conditional) {
                $0.ifTrue = transform($0.ifTrue)
                $0.ifFalse = $0.ifFalse.map(transform)
            }
        default: element = self
        }
        guard let style = element.style, style.overlay != nil || style.backgroundElement != nil else { return element }
        return element.editingStyle(missing: "an overlay") { style in
            style.overlay = style.overlay.map(transform)
            style.backgroundElement = style.backgroundElement.map(transform)
        }
    }

    /// The outermost branches a change of state from `from` to `to` removes and adds.
    func changedBranches(from: String, to: String) -> (removed: [SDUIElement], added: [SDUIElement]) {
        if case .conditional(let conditional) = self {
            let before = conditional.condition.stateResult(from), after = conditional.condition.stateResult(to)
            let branch = { (result: Bool) in result ? [conditional.ifTrue] : (conditional.ifFalse.map { [$0] } ?? []) }
            if let before, let after, before != after { return (branch(before), branch(after)) }
            // Unchanged and decided by the state alone: only the branch on screen can hold a change.
            if let before, before == after {
                let inside = branch(before).map { $0.changedBranches(from: from, to: to) }
                return (inside.flatMap(\.removed), inside.flatMap(\.added))
            }
        }
        var removed: [SDUIElement] = [], added: [SDUIElement] = []
        for child in children {
            let changed = child.changedBranches(from: from, to: to)
            removed += changed.removed
            added += changed.added
        }
        return (removed, added)
    }
}

extension SDUIConditional {
    /// A branch's own root cannot keep a `persistKey`: the branch is what arrives and leaves. Each drop warns once.
    func checkedPersistKeys() -> SDUIConditional {
        var checked = self
        checked.ifTrue = Self.checkedBranch(ifTrue)
        checked.ifFalse = ifFalse.map(Self.checkedBranch)
        return checked
    }

    private static func checkedBranch(_ branch: SDUIElement) -> SDUIElement {
        var root = branch
        if root.style?.persistKey != nil {
            sduiFlowWarn("dropped persistKey: a conditional branch's own root cannot keep one")
            root = root.editingStyle(missing: "persistKey") { $0.persistKey = nil }
        }
        return root
    }
}

extension SDUICondition {
    /// The states a `stateEquals` (or its `not`) names.
    var namedStates: [String] {
        switch self {
        case .stateEquals(let state): return [state]
        case .not(let inner): return inner.namedStates
        default: return []
        }
    }

    /// Whether `stateEquals` (or its `not`) decides this condition in `state`; nil when something else does.
    func decided(in state: String) -> Bool? {
        switch self {
        case .stateEquals(let named): return named == state
        case .not(let inner): return inner.decided(in: state).map { !$0 }
        default: return nil
        }
    }
}

extension SDUICondition {
    /// Whether the state takes part in this condition, read from its shape alone so it never changes at run time.
    var readsState: Bool {
        switch self {
        case .stateEquals: return true
        case .equals(let lhs, let rhs):
            if case .state = lhs { return true }
            if case .state = rhs { return true }
            return false
        case .not(let inner): return inner.readsState
        case .and(let all), .or(let all): return all.contains { $0.readsState }
        default: return false
        }
    }

    /// The condition's result in `state` when only the state decides it; nil when anything else could.
    func stateResult(_ state: String) -> Bool? {
        switch self {
        case .stateEquals(let name): return state == name
        case .equals(.state, .literal(let name)), .equals(.literal(let name), .state): return state == name
        case .equals(.state, .state): return true
        case .not(let inner): return inner.stateResult(state).map { !$0 }
        case .and(let all):
            let results = all.map { $0.stateResult(state) }
            if results.contains(false) { return false }
            return results.contains(nil) ? nil : true
        case .or(let any):
            let results = any.map { $0.stateResult(state) }
            if results.contains(true) { return true }
            return results.contains(nil) ? nil : false
        default: return nil
        }
    }
}

// MARK: - A running transition

/// One `setState`'s motion: when the leaving branches go and when the arriving ones finish entering, on the
/// sheet's own time (it stops while the sheet is hidden, covered or in the background).
final class SDUIStateTransition {
    let id = UUID()
    let from: String
    let to: String
    let exit: SDUIExit?
    let enter: SDUIEnter?
    /// Seconds the leaving branches stay drawn: their exits, at most 2.
    let holdEnd: TimeInterval
    /// When the arriving branches start their transition enter.
    let enterStart: TimeInterval
    /// When nothing of this transition moves any more.
    let end: TimeInterval
    /// `persistKey`s in both a leaving and an arriving branch: the same element, so it neither exits nor enters.
    let keptKeys: Set<String>
    private(set) var clock = SDUIMotionClock()
    private(set) var leavingGone = false

    static let holdCap: TimeInterval = 2

    init(from: String, to: String, spec: SDUIStateTransitionSpec?, longestExit: TimeInterval, keptKeys: Set<String>) {
        self.from = from
        self.to = to
        exit = spec?.exit
        enter = spec?.enter
        let ownExit = spec?.exit?.totalDuration ?? 0
        holdEnd = min(Self.holdCap, max(ownExit, longestExit))
        // `sequential` waits for the transition's exit and every exit in the leaving branches, at most 2 s.
        enterStart = spec?.sequential == true ? holdEnd : 0
        end = max(holdEnd, enterStart + (spec?.enter?.totalDuration ?? 0))
        self.keptKeys = keptKeys
    }

    func elapsed(at date: Date) -> TimeInterval { clock.elapsed(at: date) }
    var enterDone: Bool { clock.elapsed(at: Date()) >= enterStart + (enter?.totalDuration ?? 0) }

    func setPaused(_ paused: Bool, at now: Date) {
        if paused { clock.pause(at: now) } else { clock.resume(at: now) }
    }

    /// The next moment something changes on screen (the leaving branches go, then the end), in sheet seconds.
    var nextMilestone: TimeInterval { leavingGone ? end : holdEnd }

    func markLeavingGone() { leavingGone = true }

    /// The transform of a leaving branch root.
    func leavingFrame(at date: Date) -> SDUILoopFrame {
        exit.map { $0.frame(running: elapsed(at: date)) } ?? SDUILoopFrame()
    }

    /// The transform of an arriving branch root: its `from` pose until its start, then easing to its own.
    func arrivingFrame(at date: Date) -> SDUILoopFrame {
        enter.map { $0.frame(running: elapsed(at: date) - enterStart) } ?? SDUILoopFrame()
    }

    /// Ends at once: every pose at its end, for a second `setState` mid-transition.
    func finish() {
        leavingGone = true
        clock = SDUIMotionClock(banked: end)
    }
}

extension SDUIMotionClock {
    init(banked: TimeInterval) {
        self.init()
        resume(at: Date(timeIntervalSinceNow: -banked))
        pause(at: Date())
    }
}

/// What an element with a `persistKey` keeps across the two branches of a `setState`.
final class SDUIPersistRegistry {
    /// The loop clock, with the entrance it ran after and the loop it ran, so only an identical loop continues it.
    var motion: [String: (timeline: SDUISheetMotionTimeline, enter: SDUIEnter?, loop: String?)] = [:]
    var players: [String: (key: String, player: SDUILottiePlayer)] = [:]

    /// Forgets everything, for a new config or a closed sheet.
    func clear() {
        motion = [:]
        players = [:]
    }
}

extension SDUILoop {
    /// Everything that moves the loop, so a kept element continues its clock only under an identical loop.
    var clockSignature: String {
        String(reflecting: (duration, phaseOffset, curve, keyframes, reducedMotion, delay, repeatCount))
    }
}

// MARK: - Environment

private struct SDUIStateOverrideKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct SDUIInFlowBranchKey: EnvironmentKey { static let defaultValue = false }
private struct SDUILeavingFlowKey: EnvironmentKey { static let defaultValue: SDUIStateTransition? = nil }
private struct SDUIFlowSinkKey: EnvironmentKey { static let defaultValue: SDUIFlowActionSink? = nil }

extension EnvironmentValues {
    /// The state a leaving branch keeps drawing with, so its own conditions do not flip while it exits.
    var sduiStateOverride: String? {
        get { self[SDUIStateOverrideKey.self] }
        set { self[SDUIStateOverrideKey.self] = newValue }
    }

    /// Inside a branch that a transition moves: a nested change moves with it rather than on its own.
    var sduiInFlowBranch: Bool {
        get { self[SDUIInFlowBranchKey.self] }
        set { self[SDUIInFlowBranchKey.self] = newValue }
    }

    /// The transition a leaving branch belongs to; its elements run their exits on its clock.
    var sduiLeavingFlow: SDUIStateTransition? {
        get { self[SDUILeavingFlowKey.self] }
        set { self[SDUILeavingFlowKey.self] = newValue }
    }

    /// Where completion and timed actions go.
    var sduiFlowActions: SDUIFlowActionSink? {
        get { self[SDUIFlowSinkKey.self] }
        set { self[SDUIFlowSinkKey.self] = newValue }
    }
}

/// Fires completion and timed actions on the sheet's context, which holds the persisted element state too.
final class SDUIFlowActionSink {
    weak var context: SDUIContext?
    init(context: SDUIContext) { self.context = context }

    @MainActor func fire(_ action: SDUIAction) { context?.performTimedAction(action) }
    var registry: SDUIPersistRegistry? { context?.persisted }
}

// MARK: - Modifiers

enum SDUIFlowRole { case leaving, arriving }

/// One branch of a conditional the state decides, kept at one place in the tree so it keeps its own state
/// (entrance, loop clock, Lottie player, scroll position) while it arrives or leaves. The effect modifiers
/// stay neutral when it does not move; the ticker and the size reader exist only while it moves.
struct SDUIFlowBranch<Content: View>: View {
    let transition: SDUIStateTransition?
    let role: SDUIFlowRole?
    @ViewBuilder let content: Content
    @State private var tick = Date()
    @State private var size: CGSize = .zero
    @Environment(\.visibilityProbesPaused) private var probesPaused
    @Environment(\.sduiInFlowBranch) private var inFlowBranch
    @Environment(\.sduiStateOverride) private var stateOverride
    @Environment(\.sduiLeavingFlow) private var leavingFlow
    @Environment(\.sduiMotionPaused) private var sheetPaused

    var body: some View {
        let moving = transition.flatMap { t in role.map { (t, $0) } }
        let leaving = moving?.1 == .leaving ? moving?.0 : nil
        let now = max(tick, Date())
        let frame = moving.map { $0.1 == .leaving ? $0.0.leavingFrame(at: now) : $0.0.arrivingFrame(at: now) } ?? SDUILoopFrame()
        let waitsForSize = (frame.fx != 0 || frame.fy != 0) && size == .zero
        content
            // An offer in a leaving branch never counts again; an arriving one waits for the enter.
            .environment(\.visibilityProbesPaused, probesPaused || moving.map { Self.holdsProbes($0.0, role: $0.1, at: now) } == true)
            // Inside a moving branch a nested change moves with it, never on its own.
            .environment(\.sduiInFlowBranch, inFlowBranch || moving != nil)
            .environment(\.sduiStateOverride, leaving?.from ?? stateOverride)
            .environment(\.sduiLeavingFlow, leaving ?? leavingFlow)
            .scaleEffect(frame.scale)
            .rotationEffect(.degrees(frame.rotation))
            .offset(x: frame.x + frame.fx * size.width, y: frame.y + frame.fy * size.height)
            .opacity(waitsForSize ? 0 : frame.opacity)
            .allowsHitTesting(leaving == nil)
            .accessibilityHidden(leaving != nil)
            .modifier(SDUIFlowLeavingMark(leaving: leaving != nil))
            .background {
                if moving != nil {
                    TimelineView(.animation(minimumInterval: nil, paused: sheetPaused)) { context in
                        Color.clear.onChange(of: context.date) { tick = $0 }
                    }
                    #if DEBUG
                    .onAppear { SDUIFlowBranchDebug.tickers += 1 }
                    #endif
                    GeometryReader { proxy in
                        Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { size = $0 }
                    }
                }
            }
    }

    static func holdsProbes(_ transition: SDUIStateTransition, role: SDUIFlowRole, at date: Date) -> Bool {
        role == .leaving || transition.elapsed(at: date) < transition.enterStart + (transition.enter?.totalDuration ?? 0)
    }
}

#if DEBUG
/// Test seam: counts the tickers built, which exist only while a branch moves.
enum SDUIFlowBranchDebug { nonisolated(unsafe) static var tickers = 0 }
#endif

@available(iOS 16.0, *)
struct SDUIFlowLeavingKey: LayoutValueKey { static let defaultValue = false }

/// Tells `SDUIFlowLayout` the branch is leaving; the availability check is fixed per run, so the tree never changes.
struct SDUIFlowLeavingMark: ViewModifier {
    let leaving: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.layoutValue(key: SDUIFlowLeavingKey.self, value: leaving)
        } else {
            content
        }
    }
}

/// Lays out the branch on screen; a leaving branch keeps the size it takes for the same proposal and sits centred
/// over it, out of layout. iOS 15 has no `Layout`, so there both branches share a `ZStack` while one leaves.
@available(iOS 16.0, *)
struct SDUIFlowLayout: Layout {
    /// The widest proposal seen: a parent re-proposes only the size it chose (zero beside an `empty` branch),
    /// and the leaving branch keeps the size it had under the full one.
    func makeCache(subviews: Subviews) -> CGSize { .zero }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) -> CGSize {
        if let width = proposal.width, let height = proposal.height, width.isFinite, height.isFinite, width * height > cache.width * cache.height {
            cache = CGSize(width: width, height: height)
        }
        // With nothing else on screen the leaving branch takes the place it had.
        let inLayout = subviews.contains { !$0[SDUIFlowLeavingKey.self] } ? subviews.filter { !$0[SDUIFlowLeavingKey.self] } : Array(subviews)
        return inLayout.reduce(.zero) { size, subview in
            let fit = subview.sizeThatFits(proposal)
            return CGSize(width: max(size.width, fit.width), height: max(size.height, fit.height))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let alone = !subviews.contains { !$0[SDUIFlowLeavingKey.self] }
        for subview in subviews {
            let own = subview[SDUIFlowLeavingKey.self] && !alone && cache != .zero
            subview.place(at: centre, anchor: .center, proposal: own ? ProposedViewSize(cache) : ProposedViewSize(bounds.size))
        }
    }
}

/// Applies a motion frame, its fractional offset read from the element's own laid-out size.
struct SDUIFractionalOffset<Content: View>: View {
    let frame: SDUILoopFrame
    @ViewBuilder let content: () -> Content
    @State private var size: CGSize = .zero

    var body: some View {
        content()
            .background(GeometryReader { proxy in
                Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { size = $0 }
            })
            .scaleEffect(frame.scale)
            .rotationEffect(.degrees(frame.rotation))
            .offset(x: frame.x + frame.fx * size.width, y: frame.y + frame.fy * size.height)
            .opacity(frame.opacity)
    }
}

/// `after`: fires its action once the sheet has been on screen for `seconds` since the element appeared.
struct SDUIAfterModifier: ViewModifier {
    let after: SDUITimedAction?
    @Environment(\.sduiMotionPaused) private var sheetPaused
    @Environment(\.sduiLeavingFlow) private var leaving
    @Environment(\.sduiFlowActions) private var sink
    @State private var clock = SDUIMotionClock()
    @State private var fired = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let after {
            content
                .onAppear { if !sheetPaused { clock.resume(at: Date()) } }
                .onChange(of: sheetPaused) { paused in if paused { clock.pause(at: Date()) } else { clock.resume(at: Date()) } }
                .task(id: sheetPaused) {
                    guard !sheetPaused, !fired else { return }
                    let left = after.seconds - clock.elapsed(at: Date())
                    if left > 0 { try? await Task.sleep(nanoseconds: sduiSleepNanoseconds(left)) }
                    // Never after the element left: a leaving branch is on its way out.
                    guard !Task.isCancelled, !fired, leaving == nil else { return }
                    fired = true
                    sink?.fire(after.action)
                }
        } else {
            content
        }
    }
}
