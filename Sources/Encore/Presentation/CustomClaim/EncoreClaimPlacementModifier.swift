// `.encoreClaim(placement:)`: the one-line form of the claim handle. It owns an ``EncoreClaim`` for the
// placement and draws the app's view only while the handle has offers; hidden, the view takes no space.

import Combine
import SwiftUI
import UIKit

extension View {
    /// Shows this view only while Encore has offers for `placement`, counts its views, and opens the
    /// reward sheet on a tap. Hidden (loading, no offers, offline, or Encore's rule after a completion),
    /// it takes no space. Use it on a plain view, not a `Button`, whose own action competes for the tap.
    /// To draw each state yourself, use ``Encore/claim(placement:useCase:autoOpen:publisherReward:sheetHeadline:sheetSubheadline:onResult:)``.
    public func encoreClaim(
        placement: String,
        useCase: UseCase = .rewardUsers,
        autoOpen: AutoOpen? = nil,
        publisherReward: PublisherReward? = nil,
        sheetHeadline: String? = nil,
        sheetSubheadline: String? = nil,
        onResult: ((PresentationResult) -> Void)? = nil
    ) -> some View {
        let key = EncoreClaimPlacementModifier.Key(placement: placement, useCase: useCase, autoOpen: autoOpen)
        let hooks = EncoreClaimPlacementModifier.Hooks(
            publisherReward: publisherReward, sheetHeadline: sheetHeadline, sheetSubheadline: sheetSubheadline, onResult: onResult
        )
        return modifier(EncoreClaimPlacementModifier(key: key, hooks: hooks) {
            Encore.claim(placement: placement, useCase: useCase, autoOpen: autoOpen)
        })
    }
}

internal struct EncoreClaimPlacementModifier: ViewModifier {
    /// What a handle is made for: a change makes a new handle, as `Encore.claim` takes these once.
    struct Key: Equatable {
        let placement: String
        let useCase: UseCase
        let autoOpen: AutoOpen?
    }

    /// Applied to the live handle on every update.
    struct Hooks {
        let publisherReward: PublisherReward?
        let sheetHeadline: String?
        let sheetSubheadline: String?
        let onResult: ((PresentationResult) -> Void)?
        var moment: Moment? = nil

        func with(moment: Moment?) -> Hooks {
            var copy = self
            copy.moment = moment
            return copy
        }
    }

    let key: Key
    let hooks: Hooks
    let make: @MainActor () -> EncoreClaim
    @StateObject private var slot = EncoreClaimSlot()
    /// Set with `.moment(_:)` on this view or around it.
    @Environment(\.encoreMoment) private var moment

    func body(content: Content) -> some View {
        let claim = slot.claim(for: key, hooks: hooks.with(moment: moment), make: make)
        if claim.hasOffers {
            content.encoreClaim(claim)
        }
        // Hidden: nothing, not even spacing in a stack. The handle keeps loading with the hooks
        // already on it, so a sheet that opens by itself shows the app's prize and text.
    }
}

/// Holds the modifier's handle and passes on its changes. Made in `body` without publishing, so
/// a new key never updates state during a view update.
@MainActor
internal final class EncoreClaimSlot: ObservableObject {
    /// Declared, so the default getter never reflects over this class's fields.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    private var claim: EncoreClaim?
    private var key: EncoreClaimPlacementModifier.Key?
    private var forward: AnyCancellable?

    /// The handle for `key`, made on first ask or a new key. The hooks are set on every ask, from the
    /// first: none of them is published, so setting them in `body` updates no view state, and
    /// `onResult` is always the newest closure.
    func claim(
        for key: EncoreClaimPlacementModifier.Key, hooks: EncoreClaimPlacementModifier.Hooks? = nil, make: () -> EncoreClaim
    ) -> EncoreClaim {
        let current: EncoreClaim
        if let claim, self.key == key {
            current = claim
        } else {
            current = make()
            claim = current
            self.key = key
            forward = current.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        current.onResult = hooks?.onResult
        if let hooks {
            if current.publisherReward != hooks.publisherReward { current.publisherReward = hooks.publisherReward }
            if current.sheetHeadline != hooks.sheetHeadline { current.sheetHeadline = hooks.sheetHeadline }
            if current.sheetSubheadline != hooks.sheetSubheadline { current.sheetSubheadline = hooks.sheetSubheadline }
            if current.moment != hooks.moment { current.moment(hooks.moment) }
        }
        return current
    }
}
