// Sources/Encore/Data/OpenAPIRuntime+Extensions.swift
//
// Extensions for OpenAPI Runtime types to bridge between generated types and SDK internals.
//

import Foundation

// =============================================================================
// MARK: - OpenAPIValueContainer Unboxing
// =============================================================================

extension OpenAPIValueContainer {
    /// Unbox the container to a plain Swift value for logging, analytics, or bridging to [String: Any] APIs.
    func unboxedValue() -> Any {
        guard let val = value else { return "" }
        
        if let s = val as? String { return s }
        if let i = val as? Int { return i }
        if let d = val as? Double { return d }
        if let b = val as? Bool { return b }
        if let arr = val as? [OpenAPIValueContainer] { return arr.map { $0.unboxedValue() } }
        if let dict = val as? [String: OpenAPIValueContainer] { return dict.mapValues { $0.unboxedValue() } }
        
        return val
    }
}

extension Dictionary where Key == String, Value == OpenAPIValueContainer {
    /// Convert OpenAPIValueContainer dictionary to `[String: Any]`.
    var asDict: [String: Any] {
        mapValues { $0.unboxedValue() }
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Convert `[String: Any]` to OpenAPIValueContainer dictionary.
    /// Date values are converted to ISO8601 strings via `JSONCoding`; unsupported types are skipped.
    var asOpenAPIProperties: [String: OpenAPIValueContainer] {
        var result: [String: OpenAPIValueContainer] = [:]
        for (key, value) in self {
            // Convert Date to ISO8601 string, otherwise pass value directly
            // OpenAPIValueContainer validates internally; unsupported types will fail silently
            let jsonValue: Any = (value as? Date).map { JSONCoding.string(from: $0) } ?? value
            if let container = try? OpenAPIValueContainer(unvalidatedValue: jsonValue) {
                result[key] = container
            }
        }
        return result
    }
}

