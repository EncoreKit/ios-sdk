//
//  SDUITriggerVocabulary.swift
//  Encore
//
//  Vocabulary the trigger components (GiftsButton, ClaimReminder) draw with: time-driven text and bars,
//  repeating motion, a marquee, host lists. New decode branches only; a sheet that never uses
//  these keys decodes and renders exactly as before.
//

import SwiftUI

// MARK: - Decoder flag

extension CodingUserInfoKey {
    /// Set on the decoder for a trigger mount. Tokens that exist only inside triggers decode only with it.
    static let sduiTriggerMount = CodingUserInfoKey(rawValue: "encore.sduiTriggerMount")!
}

extension Decoder {
    /// True while decoding a trigger mount's tree.
    var isTriggerMount: Bool { (userInfo[.sduiTriggerMount] as? Bool) == true }

    /// Host-fed vocabulary (host times, host lists) reads values only a trigger host supplies. In a
    /// sheet it would draw empty, so it fails to decode there, like any unknown key: the variant
    /// is invalid, never a blank element.
    func requireTriggerMount(_ what: String) throws {
        guard isTriggerMount else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "\(what) exists only in trigger mounts"))
        }
    }
}

// MARK: - G1 countdown text

/// Ticking time text: the time left until a host time key.
struct SDUICountdown: Decodable, Equatable {
    /// A host time key, e.g. `deadline`.
    let to: String
    let format: SDUICountdownFormat
    /// Unit words for `largestUnit`, usually `${hours}` / `${minutes}` / `${seconds}`.
    var units: SDUICountdownUnits?

    private enum CodingKeys: String, CodingKey { case to, format, units }

    init(to: String, format: SDUICountdownFormat, units: SDUICountdownUnits? = nil) {
        self.to = to
        self.format = format
        self.units = units
    }

    init(from decoder: Decoder) throws {
        try decoder.requireTriggerMount("countdown")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        to = try container.decode(String.self, forKey: .to)
        format = try container.decode(SDUICountdownFormat.self, forKey: .format)
        units = try container.decodeIfPresent(SDUICountdownUnits.self, forKey: .units)
    }
}

enum SDUICountdownFormat: String, Decodable, Equatable {
    /// `HH:MM:SS` / `HH:MM` (the same, without seconds; minutes floored), each `%02d`.
    case clock, hoursMinutes, hours, minutes, seconds, largestUnit
}

struct SDUICountdownUnits: Decodable, Equatable {
    var hours: String?
    var minutes: String?
    var seconds: String?
}

// MARK: - G2 progress

/// A capsule bar (or a ring) filled to a value; a time-remaining value drains once a second.
struct SDUIProgress: Decodable {
    let value: SDUIProgressValue
    var fillColor: SDUIColor?
    var trackColor: SDUIColor?
    var style: SDUIStyle?
    /// Nil is the bar.
    var shape: SDUIProgressShape?
    /// A ring's stroke; 4 when absent.
    var lineWidth: CGFloat?
    /// A ring split into this many arcs (1...12); nil or 1 is the solid ring. Ignored on a bar.
    var segments: Int?
    /// The visible gap between segments, cap end to cap end, in degrees; 12 when absent.
    var segmentGap: Double?
    /// How progress fills the segments; continuous when absent.
    var segmentFill: SDUIProgressSegmentFill?
}

enum SDUIProgressSegmentFill: String, Decodable, Equatable {
    /// Segment i fills to `p * n - i` of its arc.
    case continuous
    /// Segment i fills only once `p * n` reaches i + 1.
    case whole
}

enum SDUIProgressShape: String, Decodable, Equatable {
    case bar, ring
}

enum SDUIProgressValue: Decodable, Equatable {
    case timeRemaining(from: String, to: String)
    case literal(Double)
    /// A number the trigger host supplies (GiftsButton's `progress`).
    case host(String)

    private enum CodingKeys: String, CodingKey { case timeRemaining, literal, host }
    private struct Span: Decodable { let from: String; let to: String }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let span = try container.decodeIfPresent(Span.self, forKey: .timeRemaining) {
            try decoder.requireTriggerMount("progress timeRemaining")
            self = .timeRemaining(from: span.from, to: span.to)
        } else if let literal = try container.decodeIfPresent(Double.self, forKey: .literal) {
            self = .literal(literal)
        } else if let name = try container.decodeIfPresent(String.self, forKey: .host) {
            try decoder.requireTriggerMount("progress host")
            self = .host(name)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "progress value needs timeRemaining, literal or host"))
        }
    }
}

// MARK: - G3 loop

/// A repeating keyframe animation of the element's scale, opacity, rotation and offset.
struct SDUILoop: Decodable {
    let duration: Double
    /// Starts the loop this far (0...1) into its cycle.
    var phaseOffset: Double?
    var curve: SDUIAnimationCurve?
    let keyframes: [SDUILoopKeyframe]
    /// The pose shown under reduce motion; absent falls back per the contract.
    var reducedMotion: SDUILoopPose?
    /// Running seconds before the first cycle (a trigger tree takes it from 2.8.0).
    var delay: Double?
    /// Cycles before it holds the last keyframe; nil loops forever (a trigger tree takes it from 2.8.0).
    var repeatCount: Double?
    /// Sheets only: fired when a loop with `repeatCount` ends.
    var onComplete: SDUIAction?

    private enum CodingKeys: String, CodingKey { case duration, phaseOffset, curve, keyframes, reducedMotion, delay, repeatCount, onComplete }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        phaseOffset = try container.decodeIfPresent(Double.self, forKey: .phaseOffset)
        curve = try container.decodeIfPresent(SDUIAnimationCurve.self, forKey: .curve)
        keyframes = try container.decode([SDUILoopKeyframe].self, forKey: .keyframes)
        reducedMotion = try container.decodeIfPresent(SDUILoopPose.self, forKey: .reducedMotion)
        delay = try container.decodeIfPresent(Double.self, forKey: .delay)
        repeatCount = try container.decodeIfPresent(Double.self, forKey: .repeatCount)
        // A trigger loop has no flow to fire into: the pre-check refuses the key, the decoder never reads it.
        guard !decoder.isTriggerMount else { return }
        onComplete = try? container.decodeIfPresent(SDUIAction.self, forKey: .onComplete)
    }
}

extension SDUILoop {
    /// The loop checks (vocab-contract §3.3): positive duration, phaseOffset 0...1, two or more keyframes
    /// whose `at` run from 0 to 1 and never fall (an equal `at` holds its first keyframe).
    var isRunnable: Bool {
        guard duration.isFinite, duration > 0, (phaseOffset ?? 0) >= 0, (phaseOffset ?? 0) <= 1,
              keyframes.count >= 2, keyframes.first?.at == 0, keyframes.last?.at == 1 else { return false }
        return zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.at <= $1.at }
    }
}

extension KeyedDecodingContainer {
    /// A sheet drops a loop this build cannot run, as an older SDK drops the key, never the whole sheet.
    /// A trigger mount decodes it as before.
    func decodeIfPresent(_ type: SDUILoop.Type, forKey key: K) throws -> SDUILoop? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let decoder = try superDecoder(forKey: key)
        if decoder.isTriggerMount { return try SDUILoop(from: decoder) }
        let cleaned = decoder.motionJSON.map { SheetMotionRules.cleanLoop($0, warn: sduiFlowWarn) }
        if let problem = cleaned.map(SheetMotionRules.sheetLoopProblem) ?? "must be an object" {
            Logger.warn(.presentation, "[SDUI] Dropped a sheet loop: \(problem)")
            return nil
        }
        guard let cleaned, let loop = try? JSONDecoder().decode(SDUILoop.self, from: cleaned.serialized()), loop.isRunnable else {
            Logger.warn(.presentation, "[SDUI] Dropped a sheet loop: it does not decode")
            return nil
        }
        return loop
    }
}

struct SDUILoopKeyframe: Decodable {
    let at: Double
    var scale: CGFloat?
    var opacity: Double?
    var rotation: Double?
    var offset: SDUIOffset?
    /// Sheets only: offset in units of the element's own size; a trigger loop never draws it.
    var offsetFraction: SDUIOffset?
}

struct SDUILoopPose: Decodable {
    var scale: CGFloat?
    var opacity: Double?
    var rotation: Double?
    var offset: SDUIOffset?
    var offsetFraction: SDUIOffset?
}

fileprivate enum SDUILoopPoseKey: String, CodingKey { case at, scale, opacity, rotation, offset, offsetFraction }

fileprivate extension KeyedDecodingContainer where K == SDUILoopPoseKey {
    /// A trigger never draws `offsetFraction` and ignores it; on a sheet a bad one is dropped, never the loop.
    func offsetFraction(_ decoder: Decoder) -> SDUIOffset? {
        decoder.isTriggerMount ? nil : (try? decodeIfPresent(SDUIOffset.self, forKey: .offsetFraction)) ?? nil
    }
}

extension SDUILoopKeyframe {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SDUILoopPoseKey.self)
        at = try c.decode(Double.self, forKey: .at)
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation)
        offset = try c.decodeIfPresent(SDUIOffset.self, forKey: .offset)
        offsetFraction = c.offsetFraction(decoder)
    }
}

extension SDUILoopPose {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SDUILoopPoseKey.self)
        scale = try c.decodeIfPresent(CGFloat.self, forKey: .scale)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation)
        offset = try c.decodeIfPresent(SDUIOffset.self, forKey: .offset)
        offsetFraction = c.offsetFraction(decoder)
    }
}

// MARK: - G4 marquee

enum SDUIMarqueeAxis: String, Decodable {
    case horizontal, vertical
}

/// Content laid along an axis that scrolls on a loop when `animateWhen` holds.
struct SDUIMarquee: Decodable {
    let axis: SDUIMarqueeAxis
    let duration: Double
    var reverse: Bool?
    var spacing: CGFloat?
    var animateWhen: SDUICondition?
    var content: SDUIElement
    var style: SDUIStyle?
}

// MARK: - G8 small additions

/// Press feedback for a button.
struct SDUIPressedStyle: Decodable {
    var scale: CGFloat?
    var duration: Double?
}

enum SDUILayoutDirection: String, Decodable {
    case ltr
}

enum SDUIGradientType: String, Decodable {
    case linear, radial
}
