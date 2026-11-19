// Boundary check that a funnel event still carries the context that makes it joinable.
// A row with no impression_id, variant_id or sdk_version looks healthy until the funnel query runs.

import Foundation

/// Verifies the attribution envelope in `AnalyticsClient.track`, the one place every typed event passes.
/// A violation reports at error level and the event still ships: a partial row beats no row.
internal enum AnalyticsEnvelopeAudit {

    /// Envelope keys the analytics client owns for every event.
    static let machineKeys: Set<String> = ["sdk_version", "platform", "app_bundle_id"]

    #if DEBUG
    /// Armed by a test around its own emission, never suite-wide: an assertion on shared state
    /// takes down whichever suite emits first, and xcodebuild then blames the next test.
    nonisolated(unsafe) static var failFast = false
    #endif

    /// Every envelope key this event should carry and does not, sorted.
    static func missingKeys(
        properties: [String: Any],
        metadata: [String: String],
        required: Set<String>
    ) -> [String] {
        var missing: [String] = []

        for key in machineKeys.sorted() where isBlank(metadata[key]) {
            missing.append(key)
        }
        for key in required.sorted() where isBlank(properties[key]) {
            // Only a variant this presentation HELD and dropped is a loss. The live config is no
            // witness: a /config landing after the 2s snapshot holds a variant the sheet never had.
            if key == "variant_id", !heldVariant(for: properties["presentation_id"] as? String) { continue }
            missing.append(key)
        }
        return missing
    }

    /// Report any missing member of `required` (event properties) or of the
    /// machine-supplied metadata.
    static func check(
        eventName: String,
        properties: [String: Any],
        metadata: [String: String],
        required: Set<String>
    ) {
        let missing = missingKeys(properties: properties, metadata: metadata, required: required)
        guard !missing.isEmpty else { return }

        let message = "[ANALYTICS] \(eventName) is missing \(missing.joined(separator: ", ")) — the row cannot be joined to its impression. Emit it through the offer analytics context, or stop emitting it here."
        Logger.error(.domain(message), context: .analytics)
        #if DEBUG
        if failFast { assertionFailure(message) }
        #endif
    }

    private static let heldVariants = Atomic(PresentationMap<String>())

    /// Records the served variant every event of `presentationId` carries, frozen at the coordinator's
    /// snapshot. Nil clears it, because a retried trigger reuses its presentation id.
    static func registerHeldVariant(_ variantId: String?, for presentationId: String) {
        let held = variantId.flatMap { $0.isEmpty ? nil : $0 }
        heldVariants.mutate { $0[presentationId] = held }
    }

    private static func heldVariant(for presentationId: String?) -> Bool {
        guard let presentationId else { return false }
        return heldVariants.value[presentationId] != nil
    }

    #if DEBUG
    /// Test seam: the record outlives any one presentation by design.
    static func resetHeldVariantsForTesting() {
        heldVariants.value = PresentationMap()
    }
    #endif

    private static func isBlank(_ value: Any?) -> Bool {
        switch value {
        case .none: return true
        case let string as String: return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case is NSNull: return true
        default: return false
        }
    }
}
