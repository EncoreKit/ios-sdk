//
//  SDUIDevConfig.swift
//  Encore
//
//  Dev variant selection via Xcode launch arguments.
//  Add `-SDUIDevVariant <name>` to scheme to activate.
//

import Foundation

/// Dev variant selection for SDUI testing.
///
/// Usage: Xcode scheme → Edit Scheme → Run → Arguments → add:
///   `-SDUIDevVariant leadCapture`
///   `-SDUIDevVariant iapFirst`
///
/// No launch argument = production behavior (remote config → fallback).
enum SDUIDevConfig {

    #if DEBUG
    // MARK: - Launch Argument Selection

    /// True when a dev variant is selected via launch argument
    static var useDevConfig: Bool {
        devVariantName != nil
    }

    /// Mock variant ID for analytics when using dev config
    static let mockVariantId: String? = "83abb4d7-c185-4ba6-95b9-75e735e00a14"

    /// The selected variant's JSON (empty object triggers fallback in SDUIConfigurationManager)
    static var devJSON: String {
        guard let name = devVariantName, let json = variants[name] else {
            return "{}"
        }
        return json
    }

    // MARK: - Variant Registry

    /// Available dev variants. Add new variants here after creating their file in Variants/.
    private static let variants: [String: String] = [
        "leadCapture": SDUIVariant_LeadCapture.json,
        "iapFirst": SDUIVariant_IAPFirst.json,
    ]

    /// Reads `-SDUIDevVariant <name>` from launch arguments
    private static var devVariantName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-SDUIDevVariant"),
              idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    #else
    static let useDevConfig = false
    static let mockVariantId: String? = nil
    static let devJSON = "{}"
    #endif
}
