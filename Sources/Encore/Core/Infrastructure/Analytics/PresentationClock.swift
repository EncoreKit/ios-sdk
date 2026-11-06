// When each presentation's sheet showed, so scroll settles can say how long after it they happened.
// `CLOCK_MONOTONIC` keeps counting through sleep and background, as `t_ms` requires, and works on iOS 15.

import Foundation

internal enum PresentationClock {

    private static let shownAtNs = Atomic(PresentationMap<UInt64>())

    /// Nanoseconds on the monotonic clock.
    static func nowNs() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC)
    }

    /// Marks `sdk_offer_presentation_success` for `presentationId`.
    static func markShown(_ presentationId: String, atNs: UInt64 = nowNs()) {
        shownAtNs.mutate { $0[presentationId] = atNs }
    }

    /// Whole milliseconds since the presentation showed; nil when it was never marked.
    static func elapsedMs(for presentationId: String, nowNs: UInt64 = nowNs()) -> Int? {
        guard let start = shownAtNs.value[presentationId] else { return nil }
        return nowNs > start ? Int((nowNs - start) / 1_000_000) : 0
    }

    #if DEBUG
    static func resetForTesting() {
        shownAtNs.value = PresentationMap()
    }
    #endif
}
