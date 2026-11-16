// Cross-launch reconciliation for strict-unlock claims.
// A strict-mode claim that ends unverified (poll timeout, swipe-away, process
// death) persists its transactionId; on launch and every foreground we re-poll
// and fire `onVerified` — wired by the composition root (Encore.configure).

import Foundation
import Combine

/// Reconciler-pattern companion to `VerificationPoller` (mirrors
/// `IAPTransactionObserver`'s launch/foreground cadence): the poller owns the
/// in-sheet verification window, this owns everything after the flow ended.
@MainActor
internal final class StrictUnlockReconciler {

    private enum Keys {
        static let transactionId = "com.encore.strictPendingTransactionId"
        static let recordedAt = "com.encore.strictPendingRecordedAt"
        static let placementId = "com.encore.strictPendingPlacementId"
        static let useCase = "com.encore.strictPendingUseCase"
        static let userId = "com.encore.strictPendingUserId"
    }

    /// Stop retrying transactions older than this — the campaign's postback
    /// window is long gone and the row will never verify.
    internal static let maxAge: TimeInterval = 7 * 24 * 3600

    private let storage: KeyValueStore
    /// Anonymous ids that identified this session, to the identified id: a sheet started anonymous may note its claim late.
    private var identifiedAs: [String: String] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var reconcileTask: Task<Void, Never>?

    /// Test seam; default polls `VerificationPoller` directly.
    var verify: @MainActor (String) async throws -> VerificationPollResult = { transactionId in
        guard #available(iOS 17.0, *) else { return .timedOut }
        return try await VerificationPoller(transactionId: transactionId).poll()
    }

    /// Fired after a late verification (pending claim already cleared).
    var onVerified: @MainActor (String) async -> Void = { _ in }

    /// The signed-in user; a claim is reconciled only for the user who made it.
    private let currentUserId: @MainActor () -> String?

    nonisolated init(storage: KeyValueStore = UserDefaultsStore(), currentUserId: @escaping @MainActor () -> String? = { nil }) {
        self.storage = storage
        self.currentUserId = currentUserId
    }

    /// Subscribe to foreground events and run the launch reconcile pass.
    func start() {
        lifecycle?.didForeground
            .sink { [weak self] in self?.kick() }
            .store(in: &cancellables)
        kick()
    }

    // MARK: - Pending Claim Bookkeeping (called by OfferSheetViewModel)

    /// Record a strict-mode claim awaiting verification. Survives process
    /// death — beside appAccountId in UserDefaults.
    ///
    /// The placement and use case are persisted with it because the sheet that
    /// knows them is gone by the time verification lands: without this the late
    /// `sdk_offer_verified` is the one conversion signal that cannot be sliced.
    /// `ownerUserId` is the user the transaction was started for (default: the current user).
    func notePending(
        transactionId: String,
        placementId: String? = nil,
        useCase: UseCase? = nil,
        ownerUserId: String? = nil,
        recordedAt: Date = Date()
    ) {
        storage.save(transactionId, to: Keys.transactionId)
        storage.save(recordedAt, to: Keys.recordedAt)
        if let owner = ownerUserId.map(owner(of:)) ?? currentUserId() {
            storage.save(owner, to: Keys.userId)
        } else {
            storage.remove(Keys.userId)
        }
        if let placementId {
            storage.save(placementId, to: Keys.placementId)
        } else {
            storage.remove(Keys.placementId)
        }
        if let useCase {
            storage.save(useCase.rawValue, to: Keys.useCase)
        } else {
            storage.remove(Keys.useCase)
        }
    }

    /// Forget the pending claim (verified in-sheet, or explicitly cancelled).
    func clearPending() {
        // Cancel an in-flight pass so it can't fire onVerified for a claim we
        // just dropped. reconcile() itself uses forgetPending — the pass IS
        // the task and must never cancel itself.
        reconcileTask?.cancel()
        reconcileTask = nil
        forgetPending()
    }

    /// The signed-in user changed: stop a pass for the previous one and check for this one.
    /// A claim with no owner (an older build's) is stamped as `previousUserId`'s first.
    func identityChanged(from previousUserId: String) {
        if pendingTransactionId != nil, (storage.load(Keys.userId) as String?) == nil {
            storage.save(previousUserId, to: Keys.userId)
        }
        reconcileTask?.cancel()
        reconcileTask = nil
        kick()
    }

    /// An anonymous user identified: their claim follows them, as the server moves it.
    /// A pass in flight is the same person's, so it is not cancelled.
    func carryOver(from previousUserId: String, to userId: String) {
        identifiedAs[previousUserId] = userId
        if pendingTransactionId != nil, isOwned(by: previousUserId) { storage.save(userId, to: Keys.userId) }
        kick()
    }

    /// Who owns a claim started as `userId`: the identified user when that anonymous id identified since.
    func owner(of userId: String) -> String { identifiedAs[userId] ?? userId }

    /// A claim with no owner was recorded before owners were kept: it is the current user's.
    private func isOwned(by userId: String?) -> Bool {
        guard let owner: String = storage.load(Keys.userId) else { return true }
        return owner == userId
    }

    private func forgetPending() {
        storage.remove(Keys.userId)
        storage.remove(Keys.transactionId)
        storage.remove(Keys.recordedAt)
        storage.remove(Keys.placementId)
        storage.remove(Keys.useCase)
    }

    /// The persisted pending transactionId, if any.
    var pendingTransactionId: String? {
        storage.load(Keys.transactionId)
    }

    // MARK: - Reconcile

    private func kick() {
        guard reconcileTask == nil else { return }
        reconcileTask = Task { [weak self] in
            await self?.reconcile()
            // A cancelled pass was already detached by clearPending or identityChanged:
            // don't clobber a successor's handle.
            if !Task.isCancelled { self?.reconcileTask = nil }
        }
    }

    /// One reconcile pass. Internal (not private) so tests can drive it
    /// without waiting on lifecycle events.
    func reconcile() async {
        // In-sheet poller owns the txn during a flow; the stream's contract
        // is after-flow-only.
        guard !OfferSheetCoordinator.isPresenting else { return }
        guard let transactionId: String = storage.load(Keys.transactionId) else { return }

        // Persisted value is untrusted input interpolated into a URL path.
        guard transactionId.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            Logger.warn(.offers, "Dropping malformed strict-unlock transaction id")
            forgetPending()
            return
        }

        if let recordedAt: Date = storage.load(Keys.recordedAt),
           Date().timeIntervalSince(recordedAt) > Self.maxAge {
            Logger.debug(.offers, "Dropping stale strict-unlock transaction \(transactionId)")
            forgetPending()
            return
        }

        // Another user's claim waits for them to sign in again.
        guard isOwned(by: currentUserId()) else { return }

        Logger.debug(.offers, "Reconciling strict-unlock transaction \(transactionId)")
        guard let result = try? await verify(transactionId), result == .verified else {
            // Still unverified — keep the claim for the next foreground
            // (until maxAge lapses).
            return
        }

        // A pass cancelled mid-poll (clearPending) must not fire onVerified.
        if Task.isCancelled { return }
        // Identity changed or a newer claim replaced this one mid-poll —
        // don't act on a stale pass.
        let current: String? = storage.load(Keys.transactionId)
        guard current == transactionId, isOwned(by: currentUserId()) else { return }

        // Read before forgetPending clears them.
        let placementId: String? = storage.load(Keys.placementId)
        let useCase = (storage.load(Keys.useCase) as String?).flatMap(UseCase.init(rawValue:))

        forgetPending()
        Logger.debug(.offers, "Late strict-unlock verification for \(transactionId)")
        // No sheet survives to this point, so the per-impression fields stay
        // absent — never fabricated. Only what the claim persisted is stamped;
        // a record written by an older build simply carries neither.
        analyticsClient?.track(OfferVerifiedEvent(
            transactionId: transactionId,
            placementId: placementId,
            useCase: useCase
        ))
        await onVerified(transactionId)
    }
}
