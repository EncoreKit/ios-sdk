// Sources/Encore/Core/Infrastructure/Logging/Logger.swift
//
// Unified logging infrastructure for the Encore SDK.
// Provides level-based logging with automatic error reporting.
//

import Foundation

// MARK: - Logger

/// Stateless logger for the Encore SDK.
/// Works before and after SDK configuration.
/// Automatically reports errors to backend when Errors service is available.
///
/// **Thread Safety:** All methods are stateless and thread-safe.
internal enum Logger {
    
    // MARK: - Logging Methods
    
    /// Debug-level logging for verbose internal state.
    /// Only visible when configured log level is `>= .debug`.
    static func debug(_ message: String) {
        log(level: .debug, emoji: "🔍", message: message)
    }
    
    /// Info-level logging for high-level milestones.
    /// Visible when configured log level is `>= .info`.
    static func info(_ message: String) {
        log(level: .info, emoji: "ℹ️", message: message)
    }
    
    /// Warning-level logging for recoverable issues.
    /// Visible when configured log level is `>= .warn`.
    /// Does NOT report to backend.
    static func warn(_ message: String) {
        log(level: .warn, emoji: "⚠️", message: message)
    }
    
    /// Error-level logging for system failures.
    /// Always visible (unless `.none`).
    /// Automatically reports to backend via Errors service (if configured).
    static func error(
        _ error: EncoreError,
        context: ErrorContext,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        // Developer-facing: clean, actionable message
        let message = error.errorDescription ?? "Unknown error"
        log(level: .error, emoji: "❌", message: message)
        
        // Report to error services (ErrorsClient handles async dispatch internally)
        let location = formatLocation(file: file, line: line, function: function)
        errorsClient?.report(error, context: context, location: location)
    }
    
    // MARK: - Private
    
    private static func log(level: Encore.LogLevel, emoji: String, message: String) {
        // Read configured log level if available; fall back to `.error` pre-configure.
        let configured = configuration?.logLevel ?? .error
        guard configured >= level else { return }
        print("\(emoji) [Encore] \(message)")
    }
    
    private static func formatLocation(file: String, line: Int, function: String) -> String {
        let filename = file.split(separator: "/").last.map(String.init) ?? file
        return "\(filename):\(line) \(function)"
    }
}

// MARK: - Log Level

extension Encore {
    /// Log level for SDK debug output.
    /// Higher levels include lower levels (e.g., .info shows info + warn + error).
    public enum LogLevel: Int, Comparable, Sendable {
        case none = 0    // No logging (production default)
        case error = 1   // Only errors
        case warn = 2    // Warnings and errors
        case info = 3    // Milestones, warnings, errors
        case debug = 4   // Everything (verbose)
        
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
} 
