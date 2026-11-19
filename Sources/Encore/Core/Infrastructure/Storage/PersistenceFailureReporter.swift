// Reports a disk write failure to Sentry once per app session per cause, for every store that writes.
// A full disk fails each write in a burst, so one report per write turns a device state into thousands.

import Foundation

/// One ledger, keyed by store and cause, so each store reports a disk failure once per session.
internal enum PersistenceFailureReporter {

    private static let reported = Atomic<Set<String>>([])

    /// Reports the first failure of each cause per `context`, and logs repeats as warnings. Before
    /// `configure()` nothing can send, so the cause stays unreported until a reporter exists.
    static func report(
        _ error: Error,
        context: ErrorContext,
        source: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let key = "\(context.rawValue)|\(failureKey(error))"
        let isFirst = errorsClient == nil || reported.mutate { $0.insert(key).inserted }
        if isFirst {
            // The caller's location, so Sentry names the store that failed rather than this helper.
            Logger.error(.transport(.persistence(error)), context: context, file: file, line: line, function: function)
        } else {
            Logger.warn(Logger.concern(for: context), "\(source): write failed again, already reported this session: \(error.localizedDescription)")
        }
    }

    /// `domain#code/underlying`: Foundation reports ENOTDIR, EIO and EROFS all as Cocoa 512, so the cause
    /// is only in `NSUnderlyingErrorKey`.
    private static func failureKey(_ error: Error) -> String {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return "\(nsError.domain)#\(nsError.code)/\(underlying.map { "\($0.domain)#\($0.code)" } ?? "-")"
    }

    #if DEBUG
    /// Test seam: the ledger outlives any one store by design.
    static func resetForTesting() {
        reported.value = []
    }
    #endif
}
