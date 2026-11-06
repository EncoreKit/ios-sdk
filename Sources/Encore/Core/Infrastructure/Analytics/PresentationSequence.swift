// Per-presentation send counter, stamped as `seq` so rows queued in one millisecond keep their order.
// Shared by `AnalyticsClient.track` and the outbox diagnostics, which bypass it; rules in the backend
// registry (`sdk_offer_presentation_triggered.md`, section `seq`).

import Foundation

internal enum PresentationSequence {

    private static let counters = Atomic(PresentationMap<Int>())

    /// The next number for `presentationId`, from 1.
    static func next(for presentationId: String) -> Int {
        var result = 0
        counters.mutate { map in
            result = (map[presentationId] ?? 0) + 1
            map[presentationId] = result
        }
        return result
    }

    /// Adds `seq` when the properties carry a non-empty `presentation_id`.
    static func stamp(_ properties: inout [String: Any]) {
        guard let presentationId = properties["presentation_id"] as? String, !presentationId.isEmpty else { return }
        properties["seq"] = next(for: presentationId)
    }

    #if DEBUG
    static func resetForTesting() {
        counters.value = PresentationMap()
    }
    #endif
}
