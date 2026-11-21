// The device limits on a presented trigger look (vocab §2.11, shared fixture
// trigger-presentation-limits.json): how often a container may cover the screen. The check and its
// transitions are pure; the store keeps them per placement on the device, in local days.

import Foundation
import Darwin

/// A limit that held a presented look back, as `sdk_trigger_eligible_not_shown` names it (`presentation_limit`).
internal enum TriggerPresentationLimit: String, CaseIterable, Sendable {
    case background
    case sheetUp = "sheet_up"
    case firstSession = "first_session"
    case dismissBackoff = "dismiss_backoff"
    case placementDay = "placement_day"
    case session
    case day

    /// The order the limits are checked in: the first that holds is the one reported.
    static let order: [Self] = [.background, .sheetUp, .firstSession, .dismissBackoff, .placementDay, .session, .day]

    /// A limit that clears by itself (the app comes back, the sheet closes): a mount whose slot stays
    /// visible waits it out and sends nothing. The others fall the slot back to inline.
    var isTransient: Bool { self == .background || self == .sheetUp }
}

internal enum TriggerPresentationLimits {
    struct Defaults: Equatable {
        var minDaysBetween = 1
        var dismissBackoffDays = 3
        var perSession = 1
        var perDay = 2
        var firstSessionSeconds = 30
        var dismissalsForBackoff = 2

        static let standard = Defaults()
    }

    /// The most a look's `caps.maxPerDay` and `caps.maxPerSession` may loosen to (the fixture's `ceilings`).
    static let maxPerDayCeiling = 10
    static let maxPerSessionCeiling = 3

    /// A look's `caps`: `minDaysBetween` and `dismissBackoffDays` only ever tighten the defaults;
    /// `maxPerDay` and `maxPerSession` loosen them up to the ceilings (2.8.0).
    struct Caps: Equatable, Sendable {
        var minDaysBetween: Int?
        var dismissBackoffDays: Int?
        var maxPerDay: Int?
        var maxPerSession: Int?

        static let none = Caps(minDaysBetween: nil, dismissBackoffDays: nil)

        init(minDaysBetween: Int?, dismissBackoffDays: Int?, maxPerDay: Int? = nil, maxPerSession: Int? = nil) {
            self.minDaysBetween = minDaysBetween
            self.dismissBackoffDays = dismissBackoffDays
            self.maxPerDay = maxPerDay
            self.maxPerSession = maxPerSession
        }

        init(_ presented: TriggerPresented) {
            self.init(
                minDaysBetween: presented.minDaysBetween, dismissBackoffDays: presented.dismissBackoffDays,
                maxPerDay: presented.maxPerDay, maxPerSession: presented.maxPerSession
            )
        }

        var minDays: Int { max(Defaults.standard.minDaysBetween, minDaysBetween ?? 0) }
        var backoffDays: Int { max(Defaults.standard.dismissBackoffDays, dismissBackoffDays ?? 0) }
        /// Shows on one local day at the placement: 1, or the look's `maxPerDay` up to the ceiling.
        var perPlacementDay: Int { min(max(1, maxPerDay ?? 0), maxPerDayCeiling) }
        /// Shows a day across placements: the default, lifted to the look's `maxPerDay` up to the ceiling.
        var perDay: Int { min(max(Defaults.standard.perDay, maxPerDay ?? 0), maxPerDayCeiling) }
        /// Shows an app session: the default, lifted to the look's `maxPerSession` up to the ceiling.
        var perSession: Int { min(max(Defaults.standard.perSession, maxPerSession ?? 0), maxPerSessionCeiling) }
    }

    /// One placement's record. Days are local-day indexes.
    struct PlacementRecord: Codable, Equatable, Sendable {
        var lastShownDay: Int? = nil
        var backoffUntilDay: Int? = nil
        var consecutiveDismissals = 0
        /// Shows on `lastShownDay`, for a look's `maxPerDay`.
        var dayShown = 0

        init(lastShownDay: Int? = nil, backoffUntilDay: Int? = nil, consecutiveDismissals: Int = 0, dayShown: Int? = nil) {
            self.lastShownDay = lastShownDay
            self.backoffUntilDay = backoffUntilDay
            self.consecutiveDismissals = consecutiveDismissals
            self.dayShown = dayShown ?? (lastShownDay == nil ? 0 : 1)
        }

        private enum CodingKeys: String, CodingKey { case lastShownDay, backoffUntilDay, consecutiveDismissals, dayShown }

        /// A record written before the count existed (the earlier 2.8.0 drafts) showed once on its day.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let last = try container.decodeIfPresent(Int.self, forKey: .lastShownDay)
            self.init(
                lastShownDay: last,
                backoffUntilDay: try container.decodeIfPresent(Int.self, forKey: .backoffUntilDay),
                consecutiveDismissals: try container.decodeIfPresent(Int.self, forKey: .consecutiveDismissals) ?? 0,
                dayShown: try container.decodeIfPresent(Int.self, forKey: .dayShown)
            )
        }
    }

    /// Everything a check reads. `secondsIntoFirstSession` is nil outside the app's first session.
    struct State: Equatable {
        let day: Int
        let secondsIntoFirstSession: Double?
        let foreground: Bool
        let sheetUp: Bool
        let sessionShown: Int
        let dayShown: Int
        let placement: PlacementRecord
    }

    enum Event: String {
        case dismiss
        case tap
    }

    /// The longest backoff a look's `caps.dismissBackoffDays` may set.
    static let maxBackoffDays = Int(TriggerPresented.dismissBackoffDaysRange.upperBound)

    /// The first limit that holds, in ``TriggerPresentationLimit/order``; nil allows it.
    static func check(_ state: State, caps: Caps) -> TriggerPresentationLimit? {
        let defaults = Defaults.standard
        for limit in TriggerPresentationLimit.order {
            let holds: Bool
            switch limit {
            case .background: holds = !state.foreground
            case .sheetUp: holds = state.sheetUp
            case .firstSession: holds = state.secondsIntoFirstSession.map { $0 < Double(defaults.firstSessionSeconds) } ?? false
            // A record from a clock that ran ahead never holds for good: a backoff past the longest a
            // look may ask for, or a show "in the future", is stale.
            case .dismissBackoff: holds = state.placement.backoffUntilDay.map { state.day < $0 && $0 - state.day <= maxBackoffDays } ?? false
            // The same day holds once the look's shows for a day are spent; the days after, until minDaysBetween.
            case .placementDay:
                holds = state.placement.lastShownDay.map { last in
                    state.day == last ? state.placement.dayShown >= caps.perPlacementDay : (0..<caps.minDays).contains(state.day - last)
                } ?? false
            case .session: holds = state.sessionShown >= caps.perSession
            case .day: holds = state.dayShown >= caps.perDay
            }
            if holds { return limit }
        }
        return nil
    }

    /// A tap resets the dismissal count; the second dismissal in a row backs the placement off.
    static func apply(_ event: Event, to record: PlacementRecord, day: Int, caps: Caps) -> PlacementRecord {
        var next = record
        switch event {
        case .tap:
            next.consecutiveDismissals = 0
        case .dismiss:
            next.consecutiveDismissals += 1
            if next.consecutiveDismissals >= Defaults.standard.dismissalsForBackoff {
                next.consecutiveDismissals = 0
                next.backoffUntilDay = day + caps.backoffDays
            }
        }
        return next
    }
}

/// The limits as this device keeps them: each placement's record and the day's count on disk, the
/// session's count in memory (an app session is the process). Shared by every presented look.
@MainActor
internal final class TriggerPresentationLimitStore {
    static let shared: TriggerPresentationLimitStore = {
        let store = TriggerPresentationLimitStore(storage: UserDefaultsStore(), calendar: .autoupdatingCurrent, sessionStart: ProcessStart.date)
        #if DEBUG
        // The demo app writes a new token to start over; a release build never reads it.
        store.resetToken = { UserDefaults.standard.string(forKey: TriggerPresentationLimitStore.debugResetKey) }
        #endif
        return store
    }()

    /// DEBUG builds only: a new value under this key forgets every limit at the next check.
    static let debugResetKey = "encore.debug.trigger.presentationReset"
    /// Read at each check; a token this device has not handled yet resets the store once. Nil (release,
    /// tests) never resets.
    var resetToken: () -> String? = { nil }
    private static let handledResetKey = prefix + "resetHandled"

    private static let prefix = "encore.trigger.presentation."
    private static let dayKey = prefix + "day"
    private static let firstSessionKey = prefix + "firstSession"
    /// Every placement record's key, so a reset finds them.
    private static let placementsKey = prefix + "placements"

    private struct DayCount: Codable {
        let day: Int
        let count: Int
    }

    private let storage: KeyValueStore
    private let calendar: Calendar
    private let sessionStart: Date
    private(set) var sessionShown = 0
    /// Placements whose slot a look's `slot.afterClose: hidden` closed for this app session (the process),
    /// per user: another user's slot is open, and a language change keeps it closed.
    private var closedSlots: Set<ClosedSlot> = []
    /// This process is the first one the limits ever ran in.
    private var isFirstSession: Bool

    init(storage: KeyValueStore, calendar: Calendar, sessionStart: Date) {
        self.storage = storage
        self.calendar = calendar
        self.sessionStart = sessionStart
        let stamp = sessionStart.timeIntervalSince1970
        if let first: Double = storage.load(Self.firstSessionKey) {
            isFirstSession = first == stamp
        } else {
            storage.save(stamp, to: Self.firstSessionKey)
            isFirstSession = true
        }
    }

    /// The local-day index of `date`, the unit every record counts in.
    func day(_ date: Date) -> Int {
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
    }

    func state(placement: String, now: Date, foreground: Bool, sheetUp: Bool) -> TriggerPresentationLimits.State {
        if let token = resetToken(), token != (storage.load(Self.handledResetKey) as String?) {
            reset()
            storage.save(token, to: Self.handledResetKey)
        }
        let today = day(now)
        let counted: DayCount? = storage.load(Self.dayKey)
        return TriggerPresentationLimits.State(
            day: today,
            secondsIntoFirstSession: isFirstSession ? now.timeIntervalSince(sessionStart) : nil,
            foreground: foreground, sheetUp: sheetUp,
            sessionShown: sessionShown,
            dayShown: counted?.day == today ? counted?.count ?? 0 : 0,
            placement: record(placement)
        )
    }

    /// The first limit holding a presented look back at `placement`; nil allows it. `firstSession` false
    /// leaves the first session's quiet period out (judged later, when the slot is seen).
    func check(
        placement: String, caps: TriggerPresentationLimits.Caps, now: Date, foreground: Bool, sheetUp: Bool, firstSession: Bool = true
    ) -> TriggerPresentationLimit? {
        let full = state(placement: placement, now: now, foreground: foreground, sheetUp: sheetUp)
        let state = firstSession ? full : TriggerPresentationLimits.State(
            day: full.day, secondsIntoFirstSession: nil, foreground: full.foreground, sheetUp: full.sheetUp,
            sessionShown: full.sessionShown, dayShown: full.dayShown, placement: full.placement
        )
        return TriggerPresentationLimits.check(state, caps: caps)
    }

    /// A container showed at `placement`.
    func recordShown(placement: String, now: Date) {
        let today = day(now)
        var placed = record(placement)
        placed.dayShown = placed.lastShownDay == today ? placed.dayShown + 1 : 1
        placed.lastShownDay = today
        save(placed, placement)
        let counted: DayCount? = storage.load(Self.dayKey)
        storage.save(DayCount(day: today, count: (counted?.day == today ? counted?.count ?? 0 : 0) + 1), to: Self.dayKey)
        sessionShown += 1
    }

    func recordDismiss(placement: String, caps: TriggerPresentationLimits.Caps, now: Date) {
        save(TriggerPresentationLimits.apply(.dismiss, to: record(placement), day: day(now), caps: caps), placement)
    }

    func recordTap(placement: String, now: Date) {
        save(TriggerPresentationLimits.apply(.tap, to: record(placement), day: day(now), caps: .none), placement)
    }

    /// `slot.afterClose: hidden` ran at `placement` for `userId`: its slot asks for nothing more this session
    /// for that user. A language change keeps it; another user starts over.
    func closeSlot(placement: String, userId: String?) {
        closedSlots.insert(Self.closedSlotKey(placement, userId))
    }

    func isSlotClosed(placement: String, userId: String?) -> Bool {
        closedSlots.contains(Self.closedSlotKey(placement, userId))
    }

    private struct ClosedSlot: Hashable {
        let placement: String
        let userId: String?
    }

    private static func closedSlotKey(_ placement: String, _ userId: String?) -> ClosedSlot {
        ClosedSlot(placement: PlacementLabel.sanitized(placement) ?? "", userId: userId)
    }

    /// Forgets every record, this session's count and its closed slots (the demo's reset, through ``debugResetKey``).
    func reset() {
        sessionShown = 0
        closedSlots = []
        storage.remove(Self.dayKey)
        let placed: [String] = storage.load(Self.placementsKey) ?? []
        for key in placed { storage.remove(key) }
        storage.remove(Self.placementsKey)
        isFirstSession = false
    }

    private func key(_ placement: String) -> String {
        "\(Self.prefix)placement.\(PlacementLabel.sanitized(placement) ?? "")"
    }

    private func record(_ placement: String) -> TriggerPresentationLimits.PlacementRecord {
        storage.load(key(placement)) ?? TriggerPresentationLimits.PlacementRecord()
    }

    private func save(_ record: TriggerPresentationLimits.PlacementRecord, _ placement: String) {
        let key = key(placement)
        storage.save(record, to: key)
        let placed: [String] = storage.load(Self.placementsKey) ?? []
        if !placed.contains(key) { storage.save(placed + [key], to: Self.placementsKey) }
    }
}

/// When this process started, so the first session's quiet period counts from the launch, not from
/// the first trigger. Falls back to the first read.
internal enum ProcessStart {
    static let date: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()
}
