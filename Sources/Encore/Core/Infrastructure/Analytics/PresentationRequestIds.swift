// The `/offers/search` request id behind each presentation, stamped as `request_id` on its events.
// It is the only key the server's `sdk_offer_ranked` shares with client events (EncoreKit/backend#827),
// because `presentation_id` is minted on the device. Shared by `AnalyticsClient.track` and the outbox.

import Foundation

internal enum PresentationRequestIds {

    private static let ids = Atomic(PresentationMap<String>())

    /// Records the search that served `presentationId`. Events before this carry no request id.
    static func register(_ requestId: String?, for presentationId: String) {
        guard let requestId, !requestId.isEmpty else { return }
        ids.mutate { $0[presentationId] = requestId }
    }

    /// Adds `request_id` when the properties name a presentation with a registered search.
    static func stamp(_ properties: inout [String: Any]) {
        guard properties["request_id"] == nil,
              let presentationId = properties["presentation_id"] as? String,
              let requestId = ids.value[presentationId] else { return }
        properties["request_id"] = requestId
    }

    #if DEBUG
    static func resetForTesting() {
        ids.value = PresentationMap()
    }
    #endif
}
