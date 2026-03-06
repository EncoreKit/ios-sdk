// Sources/Encore/Core/Canonical/RemoteConfig/RemoteConfigDto.swift
//
// Remote configuration domain DTOs - SDUI layout and app config operations.
//

import Foundation

extension DTO {
    
    /// Remote Configuration Domain DTOs
    enum RemoteConfig {
        
        // MARK: - Config Route (GET /publisher/sdk/v1/config) - Unified endpoint
        
        /// Full response from the /config endpoint
        typealias ConfigResponse = Operations.get_sol_publisher_sol_sdk_sol_v1_sol_config.Output.Ok.Body.jsonPayload
        
        /// UI configuration (template + values)
        typealias UIConfig = ConfigResponse.uiPayload
        
        /// UI template (additionalProperties - parsed to SDUIConfig domain model)
        typealias UITemplate = UIConfig.templatePayload
        
        /// UI values (text + appearance)
        typealias UIValues = UIConfig.valuesPayload
        
        /// Entitlements configuration (IAP or Native mode)
        typealias EntitlementsConfig = ConfigResponse.entitlementsPayload
        
        /// IAP entitlement config
        typealias IAPConfig = EntitlementsConfig.iapPayload
        
        /// Native entitlement config
        typealias NativeConfig = EntitlementsConfig.nativePayload
        
        /// Experiments configuration
        typealias ExperimentsConfig = ConfigResponse.experimentsPayload
        
        /// NCL experiment config
        typealias NCLConfig = ExperimentsConfig.nclPayload
        
        // MARK: - Legacy (GET /publisher/sdk/v1/ui-config) - Deprecated
        
        /// Full response type from the legacy ui-config endpoint
        @available(*, deprecated, message: "Use ConfigResponse from /config endpoint")
        typealias Response = Operations.get_sol_publisher_sol_sdk_sol_v1_sol_ui_hyphen_config.Output.Ok.Body.jsonPayload
        
        /// Success response with SDUI config and remote config (value1)
        @available(*, deprecated, message: "Use UIConfig from /config endpoint")
        typealias SuccessResponse = Response.Value1Payload
        
        /// Response when no active variant exists (value2)
        @available(*, deprecated, message: "Use ConfigResponse from /config endpoint")
        typealias NoVariantResponse = Response.Value2Payload
        
        /// SDUI config wrapper containing variant info and layout JSON
        @available(*, deprecated, message: "Use UIConfig from /config endpoint")
        typealias SDUIConfig = SuccessResponse.sduiConfigPayload
        
        /// SDUI layout config (additionalProperties)
        @available(*, deprecated, message: "Use UITemplate from /config endpoint")
        typealias SDUILayout = SDUIConfig.configPayload
        
        /// Remote config with app text/color variables (flat structure)
        @available(*, deprecated, message: "Use UIValues from /config endpoint")
        typealias LegacyRemoteConfig = SuccessResponse.remoteConfigPayload
        
        /// Appearance mode enum (light/dark/auto)
        @available(*, deprecated, message: "Use UIValues.appearance.mode from /config endpoint")
        typealias AppearanceMode = LegacyRemoteConfig.appearanceModePayload
    }
}
