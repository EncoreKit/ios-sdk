// What the app knows about its own gift: locked until something in the app happens, then ready,
// then done. It changes what the look draws and how a tap behaves; events carry its status, never its progress.

import Foundation

/// The app's state for a GiftsButton, e.g. a tile that unlocks once the user did something.
/// While `locked`, a tap never opens the sheet and the look shows a hint instead.
public struct GiftsButtonHostState: Equatable, Sendable {
    public enum Status: String, Sendable, CaseIterable {
        case locked
        case ready
        case done
    }

    public let status: Status
    /// 0...1 toward unlocking; clamped, and nil for NaN or an infinite value.
    public let progress: Double?

    public init(status: Status, progress: Double? = nil) {
        self.status = status
        self.progress = progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
    }

    public static func locked(progress: Double? = nil) -> GiftsButtonHostState {
        GiftsButtonHostState(status: .locked, progress: progress)
    }

    /// Locked with progress as steps, e.g. 3 of 4 (the same as `progress: 0.75`). A total of 0 or less is no progress.
    public static func locked(completed: Int, of total: Int) -> GiftsButtonHostState {
        guard total > 0 else { return .locked() }
        return .locked(progress: Double(max(completed, 0)) / Double(total))
    }

    public static let ready = GiftsButtonHostState(status: .ready)
    public static let done = GiftsButtonHostState(status: .done)

    /// `hostPercent`: the progress as a whole percent, "0" to "100"; nil without one.
    var percent: String? {
        progress.map { String(Int(($0 * 100).rounded())) }
    }

    /// The look's host keys: `hostStatus`, and `hostPercent` when there is a progress.
    var values: [String: String] {
        var values = ["hostStatus": status.rawValue]
        values["hostPercent"] = percent
        return values
    }
}
