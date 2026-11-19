// `.moment(_:)` on any view, for `.encoreClaim(placement:)` and Encore components inside it (R26).
// A component's own `.moment(_:)` wins over one set around it.

import SwiftUI

private struct EncoreMomentKey: EnvironmentKey {
    static let defaultValue: Moment? = nil
}

extension EnvironmentValues {
    /// The moment set with `.moment(_:)` on this view or an ancestor.
    var encoreMoment: Moment? {
        get { self[EncoreMomentKey.self] }
        set { self[EncoreMomentKey.self] = newValue }
    }
}

extension View {
    /// Why your app shows the Encore views inside this one now, such as `.streak(3)`. Apply it after
    /// `.encoreClaim(placement:)` or on a container: a moment set below that modifier never reaches it.
    public func moment(_ moment: Moment?) -> some View {
        environment(\.encoreMoment, moment)
    }
}
