// The daily activity signal: `sdk_daily_active` once per user per UTC day. Only the device's first one
// that day carries `previous_day_launches`. Contract: docs/architecture/analytics-funnel.md.

import Combine
import CryptoKit
import Foundation

internal final class DailyActiveHeartbeat: @unchecked Sendable {

    /// Users are stored as SHA-256 hashes: ids can be emails. Any older shape decodes with what it has.
    private struct State: Codable, Equatable {
        var sentDay: String?
        var sentUserHashes: [String] = []
        var launchDay: String?
        var launchCount = 0
        var previousLaunchCount: Int?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sentDay = try c.decodeIfPresent(String.self, forKey: .sentDay)
            sentUserHashes = try c.decodeIfPresent([String].self, forKey: .sentUserHashes) ?? []
            launchDay = try c.decodeIfPresent(String.self, forKey: .launchDay)
            launchCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
            previousLaunchCount = try c.decodeIfPresent(Int.self, forKey: .previousLaunchCount)
        }
    }

    static let key = "com.encore.dailyActive"
    #if DEBUG
    nonisolated(unsafe) static var sentObserverForTesting: ((String) -> Void)?
    #endif

    private let storage: KeyValueStore
    private let userId: () -> String
    private let send: (DailyActiveEvent, _ userId: String) -> Bool
    private let now: () -> Date
    private let lock = NSLock()
    private var foregrounds: AnyCancellable?

    init(storage: KeyValueStore, userId: @escaping () -> String, send: @escaping (DailyActiveEvent, String) -> Bool, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.userId = userId
        self.send = send
        self.now = now
    }

    /// Counts one `configure()` on today's UTC day; a new day keeps the last day's count as the previous one.
    func recordLaunch() {
        let today = Self.utcDay(now())
        update { state in
            if state.launchDay == today {
                state.launchCount += 1
                return
            }
            state.previousLaunchCount = state.launchDay == nil ? nil : state.launchCount
            state.launchDay = today
            state.launchCount = 1
        }
    }

    /// Calls `emitIfDue` on every later foreground.
    func start(didForeground: PassthroughSubject<Void, Never>?) {
        foregrounds = didForeground?.sink { [weak self] in self?.emitIfDue() }
    }

    /// Sends when no heartbeat was sent for the current user on today's UTC day.
    /// A user counts as sent only when `send` succeeds; it runs under the lock so two callers never both send.
    func emitIfDue() {
        let today = Self.utcDay(now())
        let user = userId()
        let userHash = Self.hash(user)
        update { state in
            if state.sentDay != today {
                state.sentDay = today
                state.sentUserHashes = []
            }
            guard !state.sentUserHashes.contains(userHash) else { return }
            // Only the device's first event of the day carries the count, so a per-user sum never repeats it.
            let previous = state.sentUserHashes.isEmpty ? Self.previousDayLaunches(state, today: today) : nil
            guard send(DailyActiveEvent(previousDayLaunches: previous), user) else { return }
            state.sentUserHashes.append(userHash)
            #if DEBUG
            Self.sentObserverForTesting?(user)
            #endif
        }
    }

    private static func hash(_ userId: String) -> String {
        SHA256.hash(data: Data(userId.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A foreground after midnight with no configure yet: the last day's count is the previous day's.
    private static func previousDayLaunches(_ state: State, today: String) -> Int? {
        state.launchDay == today ? state.previousLaunchCount : state.launchDay.map { _ in state.launchCount }
    }

    private func update<R>(_ change: (inout State) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        let stored: State? = storage.load(Self.key)
        var state = stored ?? State()
        let result = change(&state)
        if state != stored { storage.save(state, to: Self.key) }
        return result
    }

    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
