// Sources/Encore/Core/JSONCoding.swift
//
// Shared JSON encoder/decoder configuration for the Encore SDK.
// Backend returns ISO8601 dates with fractional seconds: "2024-01-01T10:30:45.123Z"

import Foundation

/// Shared JSON coding utilities for the Encore SDK.
/// All instances are thread-safe singletons — no factories needed.
internal enum JSONCoding {
    
    // MARK: - Date Formatting
    // Safe: static let uses dispatch_once, formatter is never mutated after init.
    
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
   private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Convert a Date to ISO8601 string with fractional seconds.
    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
    
    // MARK: - Encoder / Decoder
    
    /// Shared JSONDecoder configured for Encore backend responses.
    /// Handles multiple date formats for backwards compatibility:
    /// 1. ISO8601 with fractional seconds (backend API format)
    /// 2. ISO8601 without fractional seconds (legacy)
    /// 3. Numeric timestamp (standard JSONEncoder, used by UserDefaultsStore)
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            
            // Try string first (backend API format)
            if let dateString = try? container.decode(String.self) {
                // ISO8601 with fractional seconds (primary backend format)
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
                // ISO8601 without fractional seconds (fallback)
                if let date = fallbackDateFormatter.date(from: dateString) {
                    return date
                }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected ISO8601 date string, got: \(dateString)"
                )
            }
            
            // Fallback: numeric timestamp (standard JSONEncoder format, used by UserDefaultsStore)
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 string or numeric timestamp"
            )
        }
        return decoder
    }()
    
    /// Shared JSONEncoder configured for Encore backend requests.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        return encoder
    }()
}

