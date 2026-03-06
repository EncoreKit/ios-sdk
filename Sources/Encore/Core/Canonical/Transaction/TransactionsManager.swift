// Sources/Encore/Features/Transactions/TransactionsManager.swift
//
// Manager for transaction operations.
// Wraps TransactionsRepository and provides domain-level API.
//

import Foundation

/// Manager for transaction operations (starting transactions, etc.)
internal struct TransactionsManager: Sendable {
    private let repository: TransactionsRepository
    
    init(repository: TransactionsRepository) {
        self.repository = repository
    }
    
    // MARK: - Transaction Operations
    
    /// Starts a new transaction for a campaign.
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - campaignId: The campaign ID to start a transaction for
    /// - Returns: The transaction ID
    func start(userId: String, campaignId: String) async throws -> String {
        try await repository.start(userId: userId, campaignId: campaignId)
    }
}
