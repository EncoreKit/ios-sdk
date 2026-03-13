// Sources/Encore/Core/Canonical/Transaction/TransactionsRepository.swift
//
// Repository for transaction-related network operations.
//

import Foundation

internal struct TransactionsRepository {
    private let client: HTTPClientProtocol
    
    init(client: HTTPClientProtocol) {
        self.client = client
    }
    
    // MARK: - Start Transaction
    
    /// Starts a new transaction for a campaign
    /// - Returns: The transaction ID
    func start(userId: String, campaignId: String) async throws -> String {
        let request = DTO.Transactions.StartRequest(
            campaignId: campaignId,
            userId: userId
        )
        
        Logger.debug("🔄 [TransactionsRepository] Starting transaction for campaign: \(campaignId)")
        
        let dto: DTO.Transactions.StartResponse = try await client.request(
            path: "transactions",
            method: "POST",
            body: request,
            query: nil
        )
        
        guard dto.success, let transactionId = dto.transactionId else {
            let errorMessage = dto.error ?? "Transaction start failed"
            throw EncoreError.protocol(.api(status: 400, code: "transaction_failed", message: errorMessage))
        }
        
        return transactionId
    }
}
