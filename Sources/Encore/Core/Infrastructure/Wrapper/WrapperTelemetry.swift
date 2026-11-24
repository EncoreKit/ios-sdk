// The wrapper telemetry API: a wrapper SDK (Unity, Flutter, React Native) names itself once, and reports the
// failures it catches through the SDK's own error pipeline. Same names on Android and web-sdk.

import Foundation

// MARK: - Wrapper API

@_spi(EncoreBridge)
extension Encore {
    /// Names the wrapper SDK on every later analytics event and error report. Call before `configure`.
    /// A blank `name` clears it. Safe from any thread.
    public nonisolated static func setWrapper(name: String, version: String) {
        WrapperIdentity.set(name: name, version: version)
    }

    /// Reports a failure the wrapper caught, as context `wrapper` with `where` as its error type. `where`, `code` and
    /// `message` must be fixed text with no user data; `message` stays in the local debug log and is never sent.
    /// Dropped before `configure` and past the limits in `WrapperErrorReport`. Safe from any thread.
    public nonisolated static func reportWrapperError(where site: String, message: String, code: String? = nil) {
        WrapperErrorReport.send(to: errorsClient, where: site, message: message, code: code)
    }
}

// MARK: - Identity

internal enum WrapperIdentity {
    struct Value: Sendable, Equatable {
        let name: String
        let version: String?
    }

    static let maxLength = 50

    private static let storage = Atomic<Value?>(nil)

    static var current: Value? { storage.value }

    static func set(name: String, version: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.value = name.isEmpty
            ? nil
            : Value(name: name.utf16Prefix(maxLength), version: version.isEmpty ? nil : version.utf16Prefix(maxLength))
    }

    /// `wrapper_name` and `wrapper_version`, empty when no wrapper named itself.
    static var fields: [String: String] {
        guard let value = current else { return [:] }
        var fields = ["wrapper_name": value.name]
        if let version = value.version { fields["wrapper_version"] = version }
        return fields
    }

    #if DEBUG
    static func resetForTesting() { storage.value = nil }
    #endif
}

// MARK: - Report

internal enum WrapperErrorReport {
    static let interval: TimeInterval = 60
    // The wire message: a caller's text reaches Sentry with the user id, so none of it is sent.
    static let sentMessage = "Wrapper error"
    static let maxCodeLength = 100
    // At most this many reports per interval across all pairs, well under the 20 a minute /errors takes per app
    // and IP, so a broken bridge cannot crowd out the SDK's own reports.
    static let maxSendsPerInterval = 10
    // At most this many per app session (process), so a fleet of failing sessions sends a bounded total.
    static let maxSendsPerSession = 20

    private struct Key: Hashable {
        let site: String
        let code: String?
    }

    private struct Throttle {
        var lastSent: [Key: TimeInterval] = [:]
        var recentSends: [TimeInterval] = []
        var sessionSends = 0
    }

    // Monotonic seconds, so a wall-clock change cannot stretch or skip the throttle.
    private static let throttle = Atomic(Throttle())

    /// Reports through `errors`, or drops the report when the SDK is not configured yet.
    static func send(to errors: ErrorsClient?, where site: String, message: String, code: String?) {
        guard let errors else { return }
        Logger.debug(.core, "Wrapper error at \(site): \(message)")
        guard let details = details(where: site, code: code) else { return }
        errors.report(.domain(sentMessage), context: .wrapper, details: details)
    }

    /// The report's overrides, or nil when the same `where` and `code` went out under `interval` ago,
    /// `maxSendsPerInterval` reports did, or this session already sent `maxSendsPerSession`.
    static func details(
        where site: String,
        code: String?,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> ErrorReportDetails? {
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorType = site.isEmpty ? "unknown" : site.utf16Prefix(ErrorReportLimits.errorType)
        let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.utf16Prefix(maxCodeLength)
        guard shouldSend(Key(site: errorType, code: code), now: now) else { return nil }
        return ErrorReportDetails(
            errorType: errorType,
            message: sentMessage,
            metadata: code.map { ["wrapper_code": $0] } ?? [:]
        )
    }

    private static func shouldSend(_ key: Key, now: TimeInterval) -> Bool {
        throttle.mutate { state in
            if let last = state.lastSent[key], now - last < interval { return false }
            state.recentSends.removeAll { now - $0 >= interval }
            if state.recentSends.count >= maxSendsPerInterval { return false }
            if state.sessionSends >= maxSendsPerSession { return false }
            // Only pairs sent inside the interval still throttle, so the map stays at most `maxSendsPerInterval` long.
            state.lastSent = state.lastSent.filter { now - $0.value < interval }
            state.lastSent[key] = now
            state.recentSends.append(now)
            state.sessionSends += 1
            return true
        }
    }

    #if DEBUG
    static func resetForTesting() { throttle.value = Throttle() }
    #endif
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// The first `limit` UTF-16 units with no marker, as Android's `take` and web's `slice` cut. A surrogate pair
    /// the cut would split is dropped whole, because a Swift String cannot hold half of one.
    func utf16Prefix(_ limit: Int) -> String {
        guard utf16.count > limit else { return self }
        var kept = String.UnicodeScalarView()
        var units = 0
        for scalar in unicodeScalars {
            units += scalar.utf16.count
            if units > limit { break }
            kept.append(scalar)
        }
        return String(kept)
    }
}
