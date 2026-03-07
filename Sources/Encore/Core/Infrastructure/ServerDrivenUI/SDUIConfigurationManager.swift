// Sources/Encore/Core/Infrastructure/ServerDrivenUI/SDUIConfigurationManager.swift
//
// SDUI configuration management - parsing and fallback handling.
// Lazily derives layout from RemoteConfigurationManager when accessed.
//

import Foundation

// MARK: - SDUI Configuration Manager

/// Manages SDUI layout parsing and fallback handling.
/// Lazily derives layout from `remoteConfigManager?.ui` when accessed.
class SDUIConfigurationManager {
    
    private let decoder = JSONDecoder()
    
    /// Cache for parsed layout (invalidated when source config changes)
    private var cachedLayout: SDUIConfig?
    private var cachedSourceId: String?
    
    // MARK: - Public Properties
    
    /// SDUI layout config. Lazily parsed from remote config, with dev/fallback handling.
    var layout: SDUIConfig? {
        #if DEBUG
        if SDUIDevConfig.useDevConfig {
            return loadDevConfig()
        }
        #endif
        
        // Check if cache is still valid (same variant)
        let currentVariantId = remoteConfigManager?.ui?.variantId
        if cachedLayout != nil && cachedSourceId == currentVariantId {
            return cachedLayout
        }
        
        // Parse and cache
        cachedLayout = deriveLayout()
        cachedSourceId = currentVariantId
        return cachedLayout
    }
    
    /// Variant ID from remote config
    var variantId: String? { remoteConfigManager?.ui?.variantId }
    
    /// Whether the current layout requires IAP functionality
    var requiresIAP: Bool {
        guard let config = layout else { return false }
        return elementContainsTriggerIAP(config.root)
    }
    
    // MARK: - Public Methods
    
    /// Forces fallback config. Call when variant validation fails (e.g., invalid IAP product).
    func useFallbackConfig(reason: String) {
        Logger.warn("⚠️ [SDUIConfig] Switching to fallback: \(reason)")
        cachedLayout = loadFallbackConfig()
        cachedSourceId = "fallback"
    }
    
    /// Loads the embedded fallback config.
    func loadFallbackConfig() -> SDUIConfig? {
        guard let data = SDUIFallbackConfig.offerSheetJSON.data(using: .utf8) else {
            Logger.warn("❌ [SDUIConfig] Fallback JSON invalid")
            return nil
        }
        
        do {
            return try decoder.decode(SDUIConfig.self, from: data)
        } catch {
            Logger.warn("❌ [SDUIConfig] Failed to parse fallback: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func deriveLayout() -> SDUIConfig? {
        guard let ui = remoteConfigManager?.ui else {
            Logger.info("📦 [SDUIConfig] No remote config, using fallback")
            return loadFallbackConfig()
        }
        
        guard let template = ui.template else {
            Logger.info("ℹ️ [SDUIConfig] No template in config, using fallback")
            return loadFallbackConfig()
        }
        
        Logger.info("✅ [SDUIConfig] Using remote template: variantId=\(ui.variantId ?? "nil")")
        return template
    }
    
    #if DEBUG
    private func loadDevConfig() -> SDUIConfig? {
        guard let data = SDUIDevConfig.devJSON.data(using: .utf8) else {
            Logger.warn("❌ [SDUIConfig] Dev JSON invalid, using fallback")
            return loadFallbackConfig()
        }
        
        do {
            return try decoder.decode(SDUIConfig.self, from: data)
        } catch {
            Logger.warn("❌ [SDUIConfig] Failed to parse dev config: \(error), using fallback")
            return loadFallbackConfig()
        }
    }
    #endif
    
    private func elementContainsTriggerIAP(_ element: SDUIElement) -> Bool {
        switch element {
        case .button(let button):
            return button.action.type == .triggerIAP
        case .vStack(let stack):
            return stack.children.contains { elementContainsTriggerIAP($0) }
        case .hStack(let stack):
            return stack.children.contains { elementContainsTriggerIAP($0) }
        case .zStack(let stack):
            return stack.children.contains { elementContainsTriggerIAP($0) }
        case .scrollView(let scroll):
            return elementContainsTriggerIAP(scroll.content)
        case .conditional(let cond):
            return elementContainsTriggerIAP(cond.ifTrue) || (cond.ifFalse.map { elementContainsTriggerIAP($0) } ?? false)
        case .forEach(let forEach):
            return elementContainsTriggerIAP(forEach.itemTemplate)
        default:
            return false
        }
    }
}
