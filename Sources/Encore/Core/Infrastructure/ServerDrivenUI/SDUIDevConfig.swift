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
///   `-SDUIDevVariant <name>`
///
/// No launch argument = production behavior (remote config → fallback).
///
/// Available variants are listed in `variants` below and logged at launch.
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
        guard let name = devVariantName else { return "{}" }
        guard let json = variants[name]?.json else {
            print("""
            ❌ [SDUIDevConfig] Unknown variant "\(name)". Available variants:
            \(variantList)
            """)
            return "{}"
        }
        return json
    }

    /// Logs the active dev variant (or available options) on first access.
    /// Call from SDUIConfigurationManager at init to surface in the console.
    static func logStatus() {
        if let name = devVariantName {
            if variants[name] != nil {
                print("🧪 [SDUIDevConfig] Active variant: \(name)")
            }
            // Invalid name case is handled by devJSON's print
        } else {
            print("""
            ℹ️ [SDUIDevConfig] No dev variant active. Add a launch argument to test:
            \(variantList)
            """)
        }
    }

    // MARK: - Variant Registry

    /// Each entry maps a launch-argument name to a description and JSON source.
    /// Add new variants here after creating their file in Variants/.
    private static let variants: [String: (description: String, json: String)] = [
        "leadCapture":       ("Horizontal carousel + email capture + IAP",                SDUIVariant_LeadCapture.json),
        "iapFirst":          ("Triggers StoreKit IAP immediately, shows offers after",    SDUIVariant_IAPFirst.json),
        "verticalListAsync": ("Vertical list + select offer + email capture + async IAP",  SDUIVariant_VerticalListAsync.json),
    ]

    /// Formatted list of available variants for console output.
    private static var variantList: String {
        variants
            .sorted(by: { $0.key < $1.key })
            .map { "   -SDUIDevVariant \($0.key)  — \($0.value.description)" }
            .joined(separator: "\n")
    }

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
