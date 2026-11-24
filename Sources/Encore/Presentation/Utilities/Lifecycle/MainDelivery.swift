// Runs a notification handler on the main actor without trapping when the post comes from another thread.
// A main-thread post runs inline, so the timing stays the same as `MainActor.assumeIsolated`.

import Foundation

enum MainDelivery {
    /// Inline on the main thread; otherwise on the next main-queue turn.
    static func run(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(body) }
        }
    }
}
