// A calendar day as the server reads it: Gregorian `yyyy-MM-dd`, whatever calendar the user picked
// (Buddhist, Japanese, Islamic, Hebrew), in the time zone the caller names.

import Foundation

internal enum GregorianDay {
    /// `date`'s Gregorian day in `timeZone`, as `yyyy-MM-dd`.
    static func string(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
