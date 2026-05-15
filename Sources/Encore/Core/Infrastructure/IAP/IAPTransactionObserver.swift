// Sources/Encore/Core/Infrastructure/IAP/IAPTransactionObserver.swift
//
// Reconciles StoreKit transaction history with backend iap_links.
// Scans Transaction.all on cold launch, foreground, and background to catch all purchases
// (organic, Encore-initiated, renewals, family sharing, etc.).
//
// Each new originalTransactionId is linked to the current appAccountId
// via the reliable outbox. Dedup via UserDefaults Set<String>.

import Foundation
import StoreKit
import Combine

// MARK: - IAP Transaction Observer

/// Scans all StoreKit transactions and links them to appAccountId for NCL attribution.
///
/// Replaces the old `Transaction.updates` listener — that stream only fires for
/// server-initiated events, not `Product.purchase()`. `Transaction.all` catches everything.
@available(iOS 15.0, *)
internal final class IAPTransactionObserver {
    
    // MARK: - Dependencies
    
    private let outbox: OutboxManaging
    private let transactionProvider: TransactionProviding
    private let storage: KeyValueStore
    private var lifecycleCancellables = Set<AnyCancellable>()
    
    // MARK: - Storage Keys
    
    private enum Keys {
        static let linkedOriginalTxnIds = "com.encore.iap.linkedOriginalTxnIds"
    }
    
    // MARK: - Initialization
    
    init(
        outbox: OutboxManaging,
        transactionProvider: TransactionProviding = StoreKitTransactionProvider(),
        storage: KeyValueStore = UserDefaultsStore()
    ) {
        self.outbox = outbox
        self.transactionProvider = transactionProvider
        self.storage = storage
    }
    
    // MARK: - Start
    
    /// Starts reconciliation: immediate scan + foreground/background re-scans.
    func start() {
        Logger.debug("🔄 [IAP-Reconcile] Cold start scan")
        reconcileTransactions()
        
        lifecycle?.didForeground.sink { [weak self] in
            Logger.debug("🔄 [IAP-Reconcile] Foreground scan triggered")
            self?.reconcileTransactions()
        }.store(in: &lifecycleCancellables)
        
        lifecycle?.didBackground.sink { [weak self] in
            Logger.debug("🔄 [IAP-Reconcile] Background scan triggered")
            self?.reconcileTransactions()
        }.store(in: &lifecycleCancellables)
    }
    
    // MARK: - Reconciliation
    
    /// Scans all transactions and links any new originalTransactionIds to the app account.
    /// No-op if appAccountId is unavailable (iOS <16 or unverified).
    func reconcileTransactions() {
        guard let appAccountId = userManager?.appAccountId else {
            Logger.debug("🔄 [IAP-Reconcile] No appAccountId — skipping reconciliation")
            return
        }
        
        Logger.debug("🔄 [IAP-Reconcile] Starting scan (appAccountId: \(appAccountId))")
        Task(priority: .utility) {
            await performReconciliation(appAccountId: appAccountId)
        }
    }
    
    private func performReconciliation(appAccountId: String) async {
        var linkedIds = loadLinkedIds()
        let allIds = await transactionProvider.verifiedOriginalTransactionIds()
        var newLinks = 0
        
        Logger.debug("🔄 [IAP-Reconcile] Found \(allIds.count) verified transaction(s), \(linkedIds.count) already linked")
        
        for originalId in allIds {
            guard !linkedIds.contains(originalId) else { continue }
            
            outbox.enqueue(.iapLink(
                appAccountId: appAccountId,
                originalTransactionId: originalId
            ))
            Logger.debug("🔗 [IAP-Reconcile] Linking txn \(originalId) → \(appAccountId)")
            
            linkedIds.insert(originalId)
            newLinks += 1
        }
        
        if newLinks > 0 {
            saveLinkedIds(linkedIds)
            Logger.info("🔄 [IAP-Reconcile] Linked \(newLinks) new transaction chain(s)")
        } else {
            Logger.debug("🔄 [IAP-Reconcile] No new transactions to link")
        }
    }
    
    // MARK: - Immediate Link (for IAPClient.purchase)
    
    /// Links a single transaction immediately after purchase. Called by IAPClient.
    func linkTransaction(originalTransactionId: String) {
        guard let appAccountId = userManager?.appAccountId else {
            Logger.warn("🔗 [IAP-Link] No appAccountId — skipping link for txn \(originalTransactionId)")
            return
        }
        
        var linkedIds = loadLinkedIds()
        guard !linkedIds.contains(originalTransactionId) else {
            Logger.debug("🔗 [IAP-Link] Already linked txn \(originalTransactionId)")
            return
        }
        
        outbox.enqueue(.iapLink(
            appAccountId: appAccountId,
            originalTransactionId: originalTransactionId
        ))
        Logger.info("🔗 [IAP-Link] Linked txn \(originalTransactionId) → appAccountId \(appAccountId)")
        
        linkedIds.insert(originalTransactionId)
        saveLinkedIds(linkedIds)
    }
    
    // MARK: - Dedup Persistence
    
    private func loadLinkedIds() -> Set<String> {
        let array: [String]? = storage.load(Keys.linkedOriginalTxnIds)
        return Set(array ?? [])
    }
    
    private func saveLinkedIds(_ ids: Set<String>) {
        storage.save(Array(ids), to: Keys.linkedOriginalTxnIds)
    }
    
    deinit {
        lifecycleCancellables.forEach { $0.cancel() }
    }
}
