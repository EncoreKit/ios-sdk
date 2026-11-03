// Core/Infrastructure/Errors/ErrorProvider.swift
//
// Protocol defining the interface for error reporting providers.
//

import Foundation

/// An adapter that forwards an error report to one destination (the backend, or Sentry as its fallback).
internal protocol ErrorProvider: Sendable {
    /// `details` replaces or extends the error type, message and metadata derived from `error`.
    func report(_ error: EncoreError, underlying: Error?, context: ErrorContext, location: String?, sdkVersion: String, userId: String?, details: ErrorReportDetails?)
}

/// What a report carries beyond its `EncoreError`: a wrapper's own error type and message, and extra metadata.
internal struct ErrorReportDetails: Sendable, Equatable {
    var errorType: String?
    var message: String?
    var metadata: [String: String] = [:]

    /// These details plus the wrapper identity, or nil when there is nothing to add.
    func withWrapperIdentity() -> ErrorReportDetails? {
        var merged = self
        merged.metadata.merge(WrapperIdentity.fields) { own, _ in own }
        return merged == ErrorReportDetails() ? nil : merged
    }
}
