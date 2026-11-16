// Core/Infrastructure/Errors/Errors.swift
//
// Error reporting client with userId context.
// Stores userId for automatic error attribution.
//

import Foundation

// MARK: - Errors Client

/// Error reporting client for the Encore SDK.
/// Stores userId so error reports are attributed to the current user.
internal final class ErrorsClient {
    
    // MARK: - Properties
    
    private let providers: [ErrorProvider]
    private let sdkVersion: String
    
    /// Current user ID for error attribution. Atomic for thread-safe access.
    private let userId = Atomic<String?>(nil)
    
    // MARK: - Initialization
    
    init(providers: [ErrorProvider], sdkVersion: String) {
        self.providers = providers
        self.sdkVersion = sdkVersion
    }
    
    // MARK: - User Context
    
    #if DEBUG
    /// The user id error reports carry, read-only for tests.
    var userIdForTesting: String? { userId.value }

    /// Sees each report synchronously, with its details as the providers get them. Tests only.
    nonisolated(unsafe) static var reportObserverForTesting: ((ErrorContext, ErrorReportDetails?) -> Void)?
    #endif

    /// Set the current user ID. Called from Encore.identify() and Encore.reset().
    func setUserId(_ userId: String?) {
        self.userId.value = userId
    }
    
    // MARK: - Reporting
    
    /// Reports to every provider off the calling thread, and returns the error for use in a catch block.
    @discardableResult
    func report(_ error: EncoreError, context: ErrorContext, location: String? = nil, details: ErrorReportDetails? = nil) -> EncoreError {
        let underlying = error.underlying
        // Captured here, with the user id, so a later `setWrapper` cannot change a report already made.
        let details = (details ?? ErrorReportDetails()).withWrapperIdentity()
        #if DEBUG
        Self.reportObserverForTesting?(context, details)
        #endif
        let sdkVersion = self.sdkVersion
        let userId = self.userId.value  // Atomic capture
        
        for provider in providers {
            Task.detached(priority: .utility) {
                provider.report(error, underlying: underlying, context: context, location: location, sdkVersion: sdkVersion, userId: userId, details: details)
            }
        }
        return error
    }
}
