// Trigger motion (2.8.0): `style.enter` plays once per drawn content, then `style.loop` runs with its
// `delay` and `repeatCount`, on one clock per content that the host keeps, so a same-content refresh
// never replays the entrance and a companion drawn after the popup gets its own.

import SwiftUI

/// One drawn content's motion clock. It starts when the content is first drawn unpaused and holds
/// while the mount's motion is paused (off screen, covered, the background).
@MainActor
internal final class TriggerContentMotion {
    let key: String
    private(set) var clock = SDUIMotionClock()

    init(key: String) {
        self.key = key
    }

    func setPaused(_ paused: Bool, at now: Date) {
        if paused { clock.pause(at: now) } else { clock.resume(at: now) }
    }
}

/// The clocks of the contents one mount drew, by content key; the oldest go past ``keptKeys``.
@MainActor
internal final class TriggerMotionClocks {
    static let keptKeys = 8
    private var motions: [TriggerContentMotion] = []

    func motion(for key: String) -> TriggerContentMotion {
        if let kept = motions.first(where: { $0.key == key }) { return kept }
        let motion = TriggerContentMotion(key: key)
        motions.append(motion)
        if motions.count > Self.keptKeys { motions.removeFirst(motions.count - Self.keptKeys) }
        return motion
    }

    /// A user change: every content is new.
    func reset() {
        motions = []
    }
}

/// Where an element's motion is after `elapsed` running seconds of its content's clock.
internal enum TriggerMotionTimeline {
    /// The entrance transform, then the loop transform. The loop's clock starts when the entrance ends,
    /// waits the loop's `delay`, and holds the last keyframe once `repeatCount` cycles are done.
    static func frames(elapsed: TimeInterval, enter: SDUIEnter?, loop: SDUILoop?) -> (enter: SDUILoopFrame, loop: SDUILoopFrame) {
        let entranceEnd = enter?.totalDuration ?? 0
        let enterFrame = enter.map { elapsed >= $0.totalDuration ? SDUILoopFrame() : $0.frame(running: elapsed) } ?? SDUILoopFrame()
        let loopFrame = loop.map {
            SDUILoopFrame.at($0.progress(running: max(0, elapsed - entranceEnd)), keyframes: $0.keyframes, curve: $0.curve)
        } ?? SDUILoopFrame()
        return (enterFrame, loopFrame)
    }

    /// Running seconds until nothing moves any more; nil while a loop runs forever.
    static func settles(enter: SDUIEnter?, loop: SDUILoop?) -> TimeInterval? {
        let entranceEnd = enter?.totalDuration ?? 0
        guard let loop else { return entranceEnd }
        guard let length = loop.runningLength else { return nil }
        return entranceEnd + length
    }

    /// Under reduce motion: no entrance (its end pose), and the loop's reduced pose (vocab-contract §3.3).
    static func reducedFrames(loop: SDUILoop?) -> (enter: SDUILoopFrame, loop: SDUILoopFrame) {
        (SDUILoopFrame(), loop.map(SDUILoopModifier.reducedFrame) ?? SDUILoopFrame())
    }
}

private struct TriggerMotionSettleWait: Equatable {
    let paused: Bool
    let clock: ObjectIdentifier
}

private struct SDUITriggerMotionKey: EnvironmentKey {
    static let defaultValue: TriggerContentMotion? = nil
}

extension EnvironmentValues {
    /// The clock of the content a trigger tree draws, set by its host; nil runs each tree on its own.
    var sduiTriggerMotion: TriggerContentMotion? {
        get { self[SDUITriggerMotionKey.self] }
        set { self[SDUITriggerMotionKey.self] = newValue }
    }
}

/// `style.enter` and `style.loop` in a trigger tree, on the content's clock.
internal struct SDUITriggerMotionModifier: ViewModifier {
    let enter: SDUIEnter?
    let loop: SDUILoop?
    @Environment(\.sduiTriggerMotion) private var shared
    @Environment(\.sduiMotionPaused) private var paused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A tree drawn outside a host (the render harness) keeps its own clock.
    @State private var own = TriggerContentMotion(key: "")
    /// Nothing moves any more, so the timeline stops ticking.
    @State private var settled = false

    private var motion: TriggerContentMotion { shared ?? own }

    @ViewBuilder
    func body(content: Content) -> some View {
        if enter == nil, loop == nil {
            content
        } else if reduceMotion {
            apply(content, TriggerMotionTimeline.reducedFrames(loop: loop))
        } else {
            // Paused (off screen, under a sheet, the background): it holds its pose; before it has ever run, the from pose.
            TimelineView(.animation(minimumInterval: nil, paused: paused || settled)) { timeline in
                apply(content, TriggerMotionTimeline.frames(elapsed: motion.clock.elapsed(at: timeline.date), enter: enter, loop: loop))
            }
            .onAppear { motion.setPaused(paused, at: Date()) }
            .onChange(of: paused) { isPaused in motion.setPaused(isPaused, at: Date()) }
            // New content under the same tree (the day rolled at midnight): its clock starts now.
            .onChange(of: ObjectIdentifier(motion)) { _ in
                settled = false
                motion.setPaused(paused, at: Date())
            }
            .task(id: TriggerMotionSettleWait(paused: paused, clock: ObjectIdentifier(motion))) {
                // Runs on appear, on a pause change and on a new clock: the clock follows the pause, then this
                // wakes once the last motion ends, so a finished entrance or loop stops redrawing.
                motion.setPaused(paused, at: Date())
                guard !paused, let end = TriggerMotionTimeline.settles(enter: enter, loop: loop) else { return }
                let left = end - motion.clock.elapsed(at: Date())
                if left > 0 { try? await Task.sleep(nanoseconds: sduiSleepNanoseconds(left + 0.05)) }
                if !Task.isCancelled { settled = true }
            }
        }
    }

    private func apply(_ content: Content, _ frames: (enter: SDUILoopFrame, loop: SDUILoopFrame)) -> some View {
        content
            .scaleEffect(frames.enter.scale)
            .rotationEffect(.degrees(frames.enter.rotation))
            .offset(x: frames.enter.x, y: frames.enter.y)
            .opacity(frames.enter.opacity)
            .scaleEffect(frames.loop.scale)
            .rotationEffect(.degrees(frames.loop.rotation))
            .offset(x: frames.loop.x, y: frames.loop.y)
            .opacity(frames.loop.opacity)
    }
}
