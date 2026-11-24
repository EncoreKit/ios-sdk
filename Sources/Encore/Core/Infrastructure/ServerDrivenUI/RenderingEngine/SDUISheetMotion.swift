// Sheet motion: `style.enter` plays once when an element appears, then `style.loop` runs with its sheet
// keys `delay` and `repeatCount`. Contract: backend docs/architecture/sdui-sheet-motion.md.

import SwiftUI
import UIKit

// MARK: - Model

/// The checks for sheet motion, shared by the decoder and the skin so both drop the same values with
/// the same words. A port of web-sdk src/sdui/sheetMotion.ts.
enum SheetMotionRules {
    private static let curves: Set<String> = ["linear", "easeIn", "easeOut", "easeInOut"]
    private static let curveProblem = "curve must be linear, easeIn, easeOut or easeInOut"

    /// A key that is absent or JSON null, as web's `== null`.
    private static func absent(_ value: SkinJSON?) -> Bool {
        guard let value else { return true }
        if case .null = value { return true }
        return false
    }

    private static func inRange(_ value: SkinJSON?, _ low: Double, _ high: Double) -> Bool {
        guard let n = value?.number else { return false }
        return n.isFinite && n >= low && n <= high
    }

    private static func isCurve(_ value: SkinJSON?) -> Bool { value?.string.map(curves.contains) == true }

    /// Why `style.enter` cannot run, or nil.
    static func enterProblem(_ raw: SkinJSON) -> String? {
        guard let enter = raw.object else { return "must be an object" }
        if let pose = poseProblem(enter["from"]?.object, name: "from") { return pose }
        guard let duration = enter["duration"]?.number, duration.isFinite, duration > 0, duration <= 10 else {
            return "duration must be above 0 and at most 10"
        }
        if !absent(enter["delay"]), !inRange(enter["delay"], 0, 10) { return "delay must be a number from 0 to 10" }
        if !absent(enter["curve"]), !isCurve(enter["curve"]) { return curveProblem }
        return nil
    }

    /// Why a `from` or `to` pose is wrong, or nil: at least one property, each in its range.
    static func poseProblem(_ pose: SkinObject?, name: String) -> String? {
        guard let pose, ["scale", "opacity", "rotation", "offset", "offsetFraction"].contains(where: { !absent(pose[$0]) }) else {
            return "needs a \(name) pose with scale, opacity, rotation or offset"
        }
        if !absent(pose["scale"]), !inRange(pose["scale"], 0, 10) { return "\(name).scale must be a number from 0 to 10" }
        if !absent(pose["opacity"]), !inRange(pose["opacity"], 0, 1) { return "\(name).opacity must be a number from 0 to 1" }
        if !absent(pose["rotation"]), !inRange(pose["rotation"], -3600, 3600) { return "\(name).rotation must be a number from -3600 to 3600" }
        if !absent(pose["offset"]) {
            // A missing axis is 0, as for offsetFraction and on Android and web.
            guard let offset = pose["offset"]?.object,
                  ["x", "y"].allSatisfy({ absent(offset[$0]) || inRange(offset[$0], -2000, 2000) }) else {
                return "\(name).offset needs x and y from -2000 to 2000"
            }
        }
        if !absent(pose["offsetFraction"]), let problem = offsetFractionProblem(pose["offsetFraction"]) { return "\(name).\(problem)" }
        return nil
    }

    /// Why an `offsetFraction` is wrong, or nil: an object whose `x` and `y` are each -2 to 2, a missing axis 0 (as on Android and web).
    static func offsetFractionProblem(_ raw: SkinJSON?) -> String? {
        let problem = "offsetFraction needs x and y from -2 to 2"
        guard let object = raw?.object else { return problem }
        for key in ["x", "y"] where !absent(object[key]) && !inRange(object[key], -2, 2) { return problem }
        return nil
    }

    static func isAbsent(_ value: SkinJSON?) -> Bool { absent(value) }
    static func isWithin(_ value: SkinJSON?, _ low: Double, _ high: Double) -> Bool { inRange(value, low, high) }
    static func isLoopCurve(_ value: SkinJSON?) -> Bool { isCurve(value) }

    /// Why a loop's timing is wrong (trigger vocabulary section 3.3), or nil.
    static func loopTimingProblem(_ loop: SkinObject) -> String? {
        guard let duration = loop["duration"]?.number, duration.isFinite, duration > 0 else { return "needs a positive duration" }
        if !absent(loop["phaseOffset"]), !inRange(loop["phaseOffset"], 0, 1) { return "phaseOffset must be 0..1" }
        guard case .array(let frames)? = loop["keyframes"], frames.count >= 2 else { return "needs at least two keyframes" }
        let ats = frames.map { frame -> Double in
            guard let at = frame.object?["at"]?.number, at.isFinite else { return .nan }
            return at
        }
        guard ats.first == 0, ats.last == 1 else { return "keyframes must run from at 0 to at 1" }
        // An equal `at` is a zero-length segment that holds its first keyframe; only a fall is refused.
        for index in 1..<ats.count where !(ats[index] >= ats[index - 1]) { return "keyframes must ascend" }
        return nil
    }

    /// Why a sheet's `style.loop` cannot run, or nil: section 3.3 plus `delay` and `repeatCount`.
    static func sheetLoopProblem(_ raw: SkinJSON) -> String? {
        guard let loop = raw.object else { return "must be an object" }
        if !absent(loop["curve"]), !isCurve(loop["curve"]) { return curveProblem }
        if let timing = loopTimingProblem(loop) { return timing }
        // A served loop arrives with these already cleaned; a skin's bad keyframe drops the loop, as on Android and web.
        if case .array(let frames)? = loop["keyframes"] {
            for frame in frames where !absent(frame.object?["offsetFraction"]) {
                if offsetFractionProblem(frame.object?["offsetFraction"]) != nil { return "keyframe offsetFraction needs x and y from -2 to 2" }
            }
        }
        // The backend's MOTION_RANGE.loopDuration: app code passes values no check on the server has seen.
        if let duration = loop["duration"]?.number, duration > 120 { return "duration must be at most 120" }
        if !absent(loop["delay"]), !inRange(loop["delay"], 0, 30) { return "delay must be a number from 0 to 30" }
        if !absent(loop["repeatCount"]) {
            guard inRange(loop["repeatCount"], 1, 1000), let count = loop["repeatCount"]?.number, count.rounded() == count else {
                return "repeatCount must be a whole number from 1 to 1000"
            }
        }
        return nil
    }

    private static let slotBindings: [String: SDUICreativeBinding] = [
        "offerLogoImage": .offerLogoImage, "offerHeroImage": .offerHeroImage, "offerPrimaryCreative": .offerPrimaryCreative,
    ]

    /// The valid slots of `animation.images`, and why each other one was dropped.
    static func imageSlots(_ raw: SkinJSON) -> (slots: [String: SDUIAnimationImageSlot], problems: [String]) {
        guard let object = raw.object else { return ([:], ["images must be an object"]) }
        var slots: [String: SDUIAnimationImageSlot] = [:]
        var problems: [String] = []
        for (key, value) in object.entries {
            guard (1...64).contains(key.count) else { problems.append("images key \"\(key)\" must be 1 to 64 characters"); continue }
            guard let slot = value.object else { problems.append("images.\(key) must be an object"); continue }
            guard inRange(slot["offer"], 0, 9), let offer = slot["offer"]?.number, offer.rounded() == offer else {
                problems.append("images.\(key).offer must be a whole number from 0 to 9"); continue
            }
            guard let binding = slot["urlBinding"]?.string.flatMap({ slotBindings[$0] }) else {
                problems.append("images.\(key).urlBinding must be offerLogoImage, offerHeroImage or offerPrimaryCreative"); continue
            }
            slots[key] = SDUIAnimationImageSlot(offer: Int(offer), binding: binding)
        }
        return (slots, problems)
    }

    /// Why the flags of an `animation` object are wrong, or nil. The caller checks the URLs.
    static func animationFlagsProblem(_ raw: SkinObject) -> String? {
        for key in ["loop", "autoplay"] where !absent(raw[key]) {
            guard case .bool? = raw[key] else { return "\(key) must be true or false" }
        }
        return nil
    }
}

// MARK: - Model

/// A pose an entrance starts from; a property left out holds the element's own value.
struct SDUIMotionPose: Decodable {
    var scale: CGFloat?
    var opacity: Double?
    var rotation: Double?
    var offset: SDUIOffset?
    /// In units of the element's own width and height, added to `offset`.
    var offsetFraction: SDUIOffset?

    var frame: SDUILoopFrame {
        SDUILoopFrame.pose(SDUILoopPose(scale: scale, opacity: opacity, rotation: rotation, offset: offset, offsetFraction: offsetFraction))
    }
}

/// `style.enter`: the element moves from `from` to its own pose once, when it first appears.
struct SDUIEnter: Decodable {
    let from: SDUIMotionPose
    let duration: Double
    var delay: Double?
    var curve: SDUIAnimationCurve?
    /// Fired when the entrance ends (by its time, whether or not it could play).
    var onComplete: SDUIAction?

    /// Running seconds from appearing to the end pose.
    var totalDuration: Double { (delay ?? 0) + duration }

    /// The entrance's transform `elapsed` running seconds after the element appeared.
    func frame(running elapsed: TimeInterval) -> SDUILoopFrame {
        let progress = (elapsed - (delay ?? 0)) / duration
        return from.frame.scaled(by: 1 - SDUILoopFrame.eased(progress, curve ?? .easeOut))
    }
}

extension Decoder {
    /// The value at this decoder as JSON, for the shared motion checks; nil when it is not JSON.
    var motionJSON: SkinJSON? { (try? JSONValue(from: self)).map(SkinJSON.init) }
}

extension KeyedDecodingContainer {
    /// A sheet drops an entrance this build cannot run with one warning, never the sheet. A trigger
    /// tree's entrance passed the strict pre-check already (2.8.0), so it decodes as written.
    func decodeIfPresent(_ type: SDUIEnter.Type, forKey key: K) throws -> SDUIEnter? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let decoder = try superDecoder(forKey: key)
        if decoder.isTriggerMount { return try SDUIEnter(from: decoder) }
        let cleaned = decoder.motionJSON.map { SheetMotionRules.cleanEnter($0, warn: sduiFlowWarn) }
        let problem = cleaned.map(SheetMotionRules.enterProblem) ?? "must be an object"
        if let problem {
            Logger.warn(.presentation, "[SDUI] Dropped a sheet enter: \(problem)")
            return nil
        }
        guard let cleaned, let enter = try? JSONDecoder().decode(SDUIEnter.self, from: cleaned.serialized()) else {
            Logger.warn(.presentation, "[SDUI] Dropped a sheet enter: it does not decode")
            return nil
        }
        return enter
    }
}

extension SDUILoop {
    /// Where the loop sits after `elapsed` running seconds of its own clock: the progress-0 pose
    /// through `delay`, then cycles from `phaseOffset`, holding 1 once `repeatCount` cycles are done.
    func progress(running elapsed: TimeInterval) -> Double {
        let cycles = (phaseOffset ?? 0) + max(0, elapsed - (delay ?? 0)) / duration
        if let repeatCount, cycles >= repeatCount { return 1 }
        return cycles - cycles.rounded(.down)
    }

    /// Running seconds of its own clock until it holds its last pose; nil for a loop that runs forever.
    var runningLength: TimeInterval? {
        repeatCount.map { (delay ?? 0) + max(0, $0 - (phaseOffset ?? 0)) * duration }
    }
}

// MARK: - Timeline

/// One element's motion clocks. The element appears when the sheet is first seen (on screen, app active).
/// The entrance runs on the sheet's time: only the sheet hidden or covered, or the background, stops it, and
/// that jumps it to its end pose. The loop starts where the entrance ended and counts only time in view.
struct SDUISheetMotionTimeline: Equatable {
    /// Time the sheet has been seen since the element appeared.
    private(set) var clock = SDUIMotionClock()
    private(set) var appeared = false
    /// Sheet time at which a pause cut the entrance short.
    private(set) var enterCutAt: TimeInterval?
    /// Sheet-time spans the element spent out of view, and the one it is in now.
    private(set) var hidden: [ClosedRange<TimeInterval>] = []
    private(set) var hiddenSince: TimeInterval?

    /// The sheet's pause and whether the element is in view (nil until its first layout, counted as in view).
    mutating func update(sheetPaused: Bool, inView: Bool?, at now: Date, enter: SDUIEnter?) {
        if !appeared {
            guard !sheetPaused else { return }
            appeared = true
        }
        let seen = clock.elapsed(at: now)
        if sheetPaused {
            clock.pause(at: now)
            if let enter, enterCutAt == nil, seen < enter.totalDuration { enterCutAt = seen }
        } else {
            clock.resume(at: now)
        }
        if inView == false {
            if hiddenSince == nil { hiddenSince = seen }
        } else if let since = hiddenSince {
            hidden.append(since...max(since, seen))
            hiddenSince = nil
        }
    }

    /// Sheet time at which the loop's clock starts.
    func loopStart(_ enter: SDUIEnter?) -> TimeInterval {
        guard let enter else { return 0 }
        return enterCutAt ?? enter.totalDuration
    }

    /// The loop's running time at sheet time `seen`: after the entrance, less the time out of view.
    func loopRunning(at seen: TimeInterval, enter: SDUIEnter?) -> TimeInterval {
        let start = loopStart(enter)
        guard seen > start else { return 0 }
        let spans = hidden + (hiddenSince.map { [$0...max($0, seen)] } ?? [])
        let away = spans.reduce(0) { $0 + max(0, min($1.upperBound, seen) - max($1.lowerBound, start)) }
        return max(0, seen - start - away)
    }

    /// The entrance transform and the loop transform at `date`, applied in that order.
    func frames(at date: Date, enter: SDUIEnter?, loop: SDUILoop?) -> (enter: SDUILoopFrame, loop: SDUILoopFrame) {
        let seen = appeared ? clock.elapsed(at: date) : 0
        let enterFrame = enter.map { enterCutAt == nil ? $0.frame(running: seen) : SDUILoopFrame() } ?? SDUILoopFrame()
        let loopFrame = loop.map {
            SDUILoopFrame.at($0.progress(running: loopRunning(at: seen, enter: enter)), keyframes: $0.keyframes, curve: $0.curve)
        } ?? SDUILoopFrame()
        return (enterFrame, loopFrame)
    }

    /// Seconds left until nothing moves any more, if the element stays seen and in view; nil while a loop runs
    /// forever or waits out of view.
    func remaining(at date: Date, enter: SDUIEnter?, loop: SDUILoop?) -> TimeInterval? {
        let seen = appeared ? clock.elapsed(at: date) : 0
        let enterLeft = max(0, loopStart(enter) - seen)
        guard let loop else { return enterLeft }
        guard let length = loop.runningLength, hiddenSince == nil else { return nil }
        return enterLeft + max(0, length - loopRunning(at: seen, enter: enter))
    }

    /// Sheet seconds left until a finite loop's `onComplete` fires, nil for a loop that runs forever. It counts
    /// sheet time, never the in-view pause, as Android and web do; a carried clock keeps its sheet time.
    func completionLeft(at date: Date, enter: SDUIEnter?, loop: SDUILoop) -> TimeInterval? {
        guard let length = loop.runningLength else { return nil }
        let seen = appeared ? clock.elapsed(at: date) : 0
        return max(0, loopStart(enter) + length - seen)
    }

    /// Under reduce motion: no entrance, and the loop's reduced pose (vocab-contract §3.3).
    static func reducedFrames(loop: SDUILoop?) -> (enter: SDUILoopFrame, loop: SDUILoopFrame) {
        (SDUILoopFrame(), loop.map(SDUILoopModifier.reducedFrame) ?? SDUILoopFrame())
    }

    /// Settled: the end pose of the entrance and the last keyframe of a finished loop.
    static func settledFrames(enter: SDUIEnter?, loop: SDUILoop?) -> (enter: SDUILoopFrame, loop: SDUILoopFrame) {
        (SDUILoopFrame(), loop.map { SDUILoopFrame.at(1, keyframes: $0.keyframes, curve: $0.curve) } ?? SDUILoopFrame())
    }
}

extension SDUIMotionClock {
    /// Running seconds so far.
    func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

// MARK: - Modifiers

/// `style.enter` and `style.loop`. A trigger tree runs them on its content's clock (``SDUITriggerMotionModifier``);
/// a sheet adds an exit, a kept element's clock and a pause while the element is out of view.
struct SDUIMotionModifier: ViewModifier {
    let enter: SDUIEnter?
    let loop: SDUILoop?
    var exit: SDUIExit? = nil
    var persistKey: String? = nil
    @Environment(\.sduiTriggerTree) private var triggerTree

    @ViewBuilder
    func body(content: Content) -> some View {
        if enter == nil, loop == nil, exit == nil, persistKey == nil {
            content
        } else if triggerTree {
            content.modifier(SDUITriggerMotionModifier(enter: enter, loop: loop))
        } else {
            content.modifier(SDUISheetMotionModifier(enter: enter, loop: loop, exit: exit, persistKey: persistKey))
        }
    }
}

struct SDUISheetMotionModifier: ViewModifier {
    let enter: SDUIEnter?
    let loop: SDUILoop?
    var exit: SDUIExit? = nil
    var persistKey: String? = nil
    @Environment(\.sduiMotionPaused) private var sheetPaused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visibilityProbesPaused) private var probesPaused
    @Environment(\.sduiLeavingFlow) private var leaving
    @Environment(\.sduiFlowActions) private var sink
    /// Nil until the first layout reports where the element is.
    @State private var inView: Bool?
    @State private var timeline = SDUISheetMotionTimeline()
    /// The entrance has ended (run out, or cut by a pause), so offers inside it may count as seen.
    @State private var entranceOver = false
    /// Nothing moves any more, so the timeline stops ticking.
    @State private var settled = false
    /// Each completion fires at most once per appearance.
    @State private var firedEnter = false
    @State private var firedLoop = false
    /// A kept element arriving: its own entrance never plays, and an adopted loop clock ran after `keptEnter`.
    @State private var skippedEntrance = false
    @State private var keptEnter: SDUIEnter?
    /// Sheet seconds since this copy appeared, for a skipped entrance's `onComplete`.
    @State private var shown = SDUIMotionClock()

    /// The entrance the timeline runs: none of its own for a kept element.
    private var clockEnter: SDUIEnter? { skippedEntrance ? keptEnter : enter }

    /// Nothing visible moves: the sheet is not seen, or the element is out of view.
    private var paused: Bool { sheetPaused || inView == false }

    /// Kept across the two branches of a `setState`: the copy in the leaving branch is not drawn and does not exit.
    private var keptWhileLeaving: Bool { persistKey.map { leaving?.keptKeys.contains($0) == true } ?? false }

    func body(content: Content) -> some View {
        // One structure in every mode, so settling or a reduce motion change never rebuilds the content.
        TimelineView(.animation(minimumInterval: nil, paused: (paused || settled || reduceMotion) && leaving == nil)) { context in
            let frames = frames(at: context.date)
            // An offer impression inside counts only once the entrance has ended: the offer is not seen before.
            SDUIFractionalOffset(frame: frames.exit) {
                SDUIFractionalOffset(frame: frames.loop) {
                    SDUIFractionalOffset(frame: frames.enter) {
                        content.environment(\.visibilityProbesPaused, probesPaused || entering)
                    }
                }
            }
            .opacity(keptWhileLeaving ? 0 : 1)
        }
        // Outside the motion transforms: an offset reaches a geometry reader inside it, and an entrance
        // that starts off screen is not an element scrolled out of view.
        .modifier(SDUIInViewProbe(inView: $inView))
        .onAppear {
            adoptPersisted()
            update(SDUIMotionInputs(sheetPaused: sheetPaused, inView: inView))
        }
        .onChange(of: SDUIMotionInputs(sheetPaused: sheetPaused, inView: inView)) { update($0) }
        .task(id: SDUIEntranceWait(appeared: timeline.appeared, sheetPaused: sheetPaused)) {
            // Wakes when the entrance runs out, on the sheet's time; a pause ends it in `update`. Its
            // `onComplete` waits for the same time even when the entrance could not play.
            guard let enter, timeline.appeared, !sheetPaused, !entranceOver || (enter.onComplete != nil && !firedEnter) else { return }
            let left = enter.totalDuration - (skippedEntrance ? shown : timeline.clock).elapsed(at: Date())
            if left > 0 { try? await Task.sleep(nanoseconds: sduiSleepNanoseconds(left)) }
            guard !Task.isCancelled else { return }
            entranceOver = true
            persist()
            if let action = enter.onComplete, !firedEnter, leaving == nil {
                firedEnter = true
                sink?.fire(action)
            }
        }
        .task(id: SDUILoopWait(appeared: timeline.appeared, paused: sheetPaused)) {
            // A loop with `repeatCount` fires its `onComplete` once its running time is over on the sheet's time;
            // the in-view pause holds only the drawn loop.
            guard let loop, let action = loop.onComplete, !firedLoop, timeline.appeared, !sheetPaused else { return }
            while !Task.isCancelled {
                guard let left = timeline.completionLeft(at: Date(), enter: clockEnter, loop: loop) else { return }
                if left <= 0.01 { break }
                try? await Task.sleep(nanoseconds: sduiSleepNanoseconds(left))
            }
            guard !Task.isCancelled, !firedLoop, leaving == nil else { return }
            firedLoop = true
            sink?.fire(action)
        }
        .task(id: paused) {
            // Wakes once the last motion ends, so a finished entrance or loop stops redrawing.
            guard !paused, let remaining = timeline.remaining(at: Date(), enter: clockEnter, loop: loop) else { return }
            try? await Task.sleep(nanoseconds: sduiSleepNanoseconds(remaining + 0.05))
            if !Task.isCancelled { settled = true }
        }
    }

    private func update(_ inputs: SDUIMotionInputs) {
        var next = timeline
        next.update(sheetPaused: inputs.sheetPaused, inView: inputs.inView, at: Date(), enter: clockEnter)
        timeline = next
        if inputs.sheetPaused { shown.pause(at: Date()) } else { shown.resume(at: Date()) }
        if next.enterCutAt != nil { entranceOver = true }
        persist()
        #if DEBUG
        Self.timelineObserver?(next)
        Self.copyObserver?(next, leaving != nil)
        #endif
    }

    /// An element with a `persistKey` that was already on screen skips its own entrance, and keeps the loop
    /// clock only under an identical loop. Its own `enter.onComplete` still fires after the entrance's time.
    private func adoptPersisted() {
        guard let persistKey, sink?.context?.stateTransition?.keptKeys.contains(persistKey) == true,
              let kept = sink?.registry?.motion[persistKey] else { return }
        skippedEntrance = true
        entranceOver = true
        if let loop, kept.loop == loop.clockSignature {
            timeline = kept.timeline
            keptEnter = kept.enter
        }
    }

    private func persist() {
        guard let persistKey, let registry = sink?.registry, !keptWhileLeaving else { return }
        registry.motion[persistKey] = (timeline, clockEnter, loop?.clockSignature)
    }

    private var entering: Bool { Self.holdsImpressions(enter: enter, reduceMotion: reduceMotion, entranceOver: entranceOver) }

    /// True while an entrance is still to end: no entrance, or Reduce Motion, has none.
    static func holdsImpressions(enter: SDUIEnter?, reduceMotion: Bool, entranceOver: Bool) -> Bool {
        enter != nil && !reduceMotion && !entranceOver
    }

    #if DEBUG
    /// Test seam: sees each element's timeline after every pause or view change.
    nonisolated(unsafe) static var timelineObserver: ((SDUISheetMotionTimeline) -> Void)?
    /// Test seam: the same, with whether the copy reporting is in a leaving branch.
    nonisolated(unsafe) static var copyObserver: ((SDUISheetMotionTimeline, Bool) -> Void)?
    #endif

    private func frames(at date: Date) -> (enter: SDUILoopFrame, loop: SDUILoopFrame, exit: SDUILoopFrame) {
        let exitFrame = Self.exitFrame(exit, leaving: leaving, reduceMotion: reduceMotion, kept: keptWhileLeaving, at: date)
        if reduceMotion { let reduced = SDUISheetMotionTimeline.reducedFrames(loop: loop); return (reduced.enter, reduced.loop, exitFrame) }
        if settled { let end = SDUISheetMotionTimeline.settledFrames(enter: clockEnter, loop: loop); return (end.enter, end.loop, exitFrame) }
        let running = timeline.frames(at: date, enter: clockEnter, loop: loop)
        return (running.enter, running.loop, exitFrame)
    }

    /// The exit pose while a `setState` removes the element's branch; none for a kept element or under Reduce Motion.
    static func exitFrame(_ exit: SDUIExit?, leaving: SDUIStateTransition?, reduceMotion: Bool, kept: Bool, at date: Date) -> SDUILoopFrame {
        guard let exit, let leaving, !reduceMotion, !kept else { return SDUILoopFrame() }
        return exit.frame(running: leaving.elapsed(at: date))
    }
}

struct SDUILoopWait: Equatable {
    let appeared: Bool
    let paused: Bool
}

struct SDUIEntranceWait: Equatable {
    let appeared: Bool
    let sheetPaused: Bool
}

struct SDUIMotionInputs: Equatable {
    let sheetPaused: Bool
    let inView: Bool?
}

/// Reports whether any of the element's laid-out box is inside the window (and the host's visible
/// bounds). Measured before motion transforms, so an entrance that starts off screen still counts.
struct SDUIInViewProbe: ViewModifier {
    @Binding var inView: Bool?
    @Environment(\.visibilityBounds) private var visibleBounds

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { update(proxy.frame(in: .global), visibleBounds) }
                    .onChange(of: proxy.frame(in: .global)) { update($0, visibleBounds) }
                    // The new value: the closure still sees the previous bounds.
                    .onChange(of: visibleBounds) { update(proxy.frame(in: .global), $0) }
            }
        )
    }

    private func update(_ frame: CGRect, _ bounds: CGRect?) {
        let visible = VisibilityGeometry.intersects(frame, window: VisibilityGeometry.activeWindowBounds, bounds: bounds)
        if inView != visible { inView = visible }
    }
}

/// Nanoseconds to sleep for `seconds`, clamped to a day: `UInt64(...)` traps past UInt64.max, and a longer wait
/// is woken by a pause or a new appearance long before it ends.
func sduiSleepNanoseconds(_ seconds: TimeInterval) -> UInt64 {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return UInt64(min(seconds, 86_400) * 1_000_000_000)
}
