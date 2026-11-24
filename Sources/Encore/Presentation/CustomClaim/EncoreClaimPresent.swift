// EncoreClaim.present() (vocab §2.11): the handle has no slot, so it asks Encore for a look drawn over
// the screen (a popup, a half sheet or a full-screen cover) on its own request, and shows it under the
// same device limits a mounted GiftsButton follows. The app's own view and its rules are untouched.

import Foundation

/// What ``EncoreClaim/present()`` did.
public enum PresentOutcome: Equatable, Sendable {
    /// The look is on screen in this mode.
    case shown(PresentedMode)
    /// Nothing was shown, for this reason.
    case suppressed(PresentSuppressedReason)
}

/// Why ``EncoreClaim/present()`` showed nothing. The same names on every platform. A `switch` over it
/// needs an `@unknown default`: a later SDK may add a reason.
public enum PresentSuppressedReason: String, Equatable, Sendable, CaseIterable {
    /// Encore has no presented look for this placement and user. Nothing is sent.
    case noLook
    /// Nothing could be shown: no offers for this user, no answer, the look went away while waiting,
    /// the user changed, or no screen to show it on.
    case unavailable
    /// The look uses something this SDK version does not draw.
    case unrenderable
    /// `Encore.shared.isEnabled` is false.
    case disabled
    /// Below iOS 17, where Encore draws no trigger look.
    case unsupportedOS
    /// A device limit held it back: the app is not active.
    case background
    /// A device limit held it back: another Encore sheet or presented look is up (this handle's included).
    case sheetUp
    /// A device limit held it back: the first 30 s of the app's first session.
    case firstSession
    /// A device limit held it back: closed twice in a row at this placement recently.
    case dismissBackoff
    /// A device limit held it back: already shown at this placement today (or within the look's days).
    case placementDay
    /// A device limit held it back: one per app session.
    case session
    /// A device limit held it back: two per local day.
    case day

    /// The reason a device limit gives.
    init(_ limit: TriggerPresentationLimit) {
        switch limit {
        case .background: self = .background
        case .sheetUp: self = .sheetUp
        case .firstSession: self = .firstSession
        case .dismissBackoff: self = .dismissBackoff
        case .placementDay: self = .placementDay
        case .session: self = .session
        case .day: self = .day
        }
    }
}

extension EncoreClaim {
    /// Shows Encore's look for this placement over the screen, if Encore serves one: a popup, a half
    /// sheet or a full-screen cover, chosen per look by Encore. A tap opens the reward sheet; the close
    /// button or a swipe closes it. Returns once it is on screen, or with why nothing showed. Looks
    /// are limited per device (at most one per app session, two a day), so expect a limit's reason.
    public func present() async -> PresentOutcome {
        guard #available(iOS 17.0, *) else { return .suppressed(.unsupportedOS) }
        guard Encore.shared.isEnabled else { return .suppressed(.disabled) }
        guard !presenting, presenter?.isShowing != true else { return .suppressed(.sheetUp) }
        presenting = true
        defer { presenting = false }
        let outcome: PresentOutcome
        if case .reminder = state {
            let host = TriggerHostModel(
                plugin: ClaimReminderTrigger(source: environment.claims, sheet: environment.sheet), placement: placement,
                settings: TriggerMountSettings(useCase: useCase), dependencies: environment.presentedReminder ?? .live
            )
            hand(host)
            outcome = await Self.present(host)
        } else {
            let host = TriggerHostModel(
                plugin: GiftsButtonTrigger(environment: giftsTrigger.environment), placement: placement,
                settings: TriggerMountSettings(useCase: useCase), dependencies: environment.presentedGifts ?? .live
            )
            hand(host)
            outcome = await Self.present(host)
        }
        if case .suppressed = outcome {
            // It showed nothing: stopped, so no notification loads it again.
            presenter?.stop()
            presenter = nil
        }
        return outcome
    }

    /// The handle's sheet settings, on the host whose tap opens the sheet.
    private func hand<Plugin: TriggerPlugin>(_ host: TriggerHostModel<Plugin>) {
        presenter = host
        host.onContainerEnded = { [weak self, weak host] in
            if let self, self.presenter === host { self.presenter = nil }
        }
        host.publisherReward = publisherReward
        host.sheetText = TriggerSheetText(headline: sheetHeadline, subheadline: sheetSubheadline)
        host.onResult = { [weak self] in self?.onResult?($0) }
        host.setMoment(moment)
    }

    /// Runs one presenting host: its gate and its request, then its container under the limits.
    private static func present<Plugin: TriggerPlugin>(_ host: TriggerHostModel<Plugin>) async -> PresentOutcome {
        host.presentations = .presentedOnly
        host.presentsWithoutSlot = true
        host.reportsNullAnswers = false
        host.start()
        return await withCheckedContinuation { (continuation: CheckedContinuation<PresentOutcome, Never>) in
            let once = PresentOnce(continuation)
            host.onContainerShown = { once.resume(.shown($0)) }
            host.onContainerHeld = { limit in
                // Turned off during the wait: that, not a missing look, is why nothing showed.
                guard Encore.shared.isEnabled else { return once.resume(.suppressed(.disabled)) }
                once.resume(.suppressed(limit.map(PresentSuppressedReason.init) ?? .unavailable))
            }
            Task { @MainActor in
                await host.refresh()
                switch host.escalation {
                case .waiting, .delaying, .showing:
                    return  // the container's callbacks answer
                case .ended:
                    return  // held: its callback answered
                case .idle:
                    break
                }
                guard Encore.shared.isEnabled else { return once.resume(.suppressed(.disabled)) }
                switch host.config {
                case nil, .failed?:
                    // No offers, no user, a superseded refresh, or no answer.
                    once.resume(.suppressed(.unavailable))
                case .config(_, let loaded)? where host.plugin.unrenderable(loaded, settings: host.settings) != nil:
                    once.resume(.suppressed(.unrenderable))
                default:
                    once.resume(.suppressed(.noLook))
                }
            }
        }
    }
}

/// A host the handle presented with, erased over its plug-in.
@MainActor
internal protocol TriggerPresenting: AnyObject {
    /// Its presented look's container is on screen.
    var isShowing: Bool { get }
    func stop()
    /// The SDK turned off: a container on show goes, a wait in flight answers.
    func turnedOff()
    /// The user or language changed: what it was showing or waiting to show was the previous user's.
    func userChanged()
}

extension TriggerHostModel: TriggerPresenting {
    var isShowing: Bool { escalation == .showing }
}

/// Resumes a continuation once, whichever answer comes first.
@MainActor
private final class PresentOnce {
    private var continuation: CheckedContinuation<PresentOutcome, Never>?

    init(_ continuation: CheckedContinuation<PresentOutcome, Never>) { self.continuation = continuation }

    func resume(_ outcome: PresentOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
