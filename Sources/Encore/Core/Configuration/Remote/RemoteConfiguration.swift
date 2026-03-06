// Sources/Encore/Core/Configuration/Remote/RemoteConfiguration.swift
//
// Domain models for remote configuration.
// Maps from DTOs to domain entities with init(from:) pattern.
//

import Foundation

// MARK: - Root Configuration

/// Remote configuration fetched from /config endpoint.
/// Contains UI, entitlements, and experiments configuration.
/// Codable for disk caching (last-known-good snapshot).
/// Sendable for thread-safe access via Atomic wrapper.
struct RemoteConfiguration: Codable, Sendable {
    let ui: UIConfiguration
    let entitlements: EntitlementConfiguration
    let experiments: ExperimentConfiguration
    
    init(from dto: DTO.RemoteConfig.ConfigResponse) {
        self.ui = UIConfiguration(from: dto.ui)
        self.entitlements = EntitlementConfiguration(from: dto.entitlements)
        self.experiments = ExperimentConfiguration(from: dto.experiments)
    }
}

// MARK: - UI Configuration

/// UI configuration including SDUI template and values for substitution.
/// Codable for disk caching. Note: `template` (SDUIConfig) is excluded from coding
/// because SDUIConfig is Decodable-only — it's re-parsed from the network response.
/// @unchecked Sendable: SDUIConfig is a value-type tree; safe for cross-thread access.
struct UIConfiguration: Codable, @unchecked Sendable {
    let variantId: String?
    let variantName: String?
    let minSdkVersion: String?
    let values: UIValues
    
    /// Parsed SDUI template. Not persisted to disk (re-parsed from network on each fetch).
    let template: SDUIConfig?
    
    // Exclude template from Codable (SDUIConfig is Decodable-only)
    enum CodingKeys: String, CodingKey {
        case variantId, variantName, minSdkVersion, values
    }
    
    init(from dto: DTO.RemoteConfig.UIConfig) {
        self.variantId = dto.variantId
        self.variantName = dto.variantName
        self.minSdkVersion = dto.minSdkVersion
        self.template = Self.parseTemplate(dto.template)
        self.values = UIValues(from: dto.values)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.variantId = try container.decodeIfPresent(String.self, forKey: .variantId)
        self.variantName = try container.decodeIfPresent(String.self, forKey: .variantName)
        self.minSdkVersion = try container.decodeIfPresent(String.self, forKey: .minSdkVersion)
        self.values = try container.decode(UIValues.self, forKey: .values)
        self.template = nil  // Not persisted; re-parsed from network
    }
    
    /// Parses the raw template payload into SDUIConfig domain model
    private static func parseTemplate(_ template: DTO.RemoteConfig.UITemplate?) -> SDUIConfig? {
        guard let template else { return nil }
        do {
            let data = try JSONEncoder().encode(template)
            return try JSONDecoder().decode(SDUIConfig.self, from: data)
        } catch {
            Logger.warn("⚠️ [UIConfiguration] Failed to parse SDUI template: \(error)")
            return nil
        }
    }
}

// MARK: - UI Values

/// Text and appearance values for template substitution.
struct UIValues: Codable, Sendable {
    // Text values
    let appName: String?
    let title: String?
    let subtitle: String?
    let offerDescription: String?
    let instructionsTitle: String?
    let lastStepHeader: String?
    let lastStepDescription: String?
    let creditClaimedTitle: String?
    let creditClaimedSubtitle: String?
    let applyCreditsButton: String?
    let accentTitle: String?
    let customHeadline: String?
    let customSubheadline: String?

    // Appearance values
    let appearanceMode: AppearanceMode?
    let accentColor: String?
    let accentTitleColor: String?
    
    enum AppearanceMode: String, Codable {
        case light
        case dark
        case auto
    }
    
    init(from dto: DTO.RemoteConfig.UIValues) {
        // Text
        self.appName = dto.text.appName
        self.title = dto.text.title
        self.subtitle = dto.text.subtitle
        self.offerDescription = dto.text.offerDescription
        self.instructionsTitle = dto.text.instructionsTitle
        self.lastStepHeader = dto.text.lastStepHeader
        self.lastStepDescription = dto.text.lastStepDescription
        self.creditClaimedTitle = dto.text.creditClaimedTitle
        self.creditClaimedSubtitle = dto.text.creditClaimedSubtitle
        self.applyCreditsButton = dto.text.applyCreditsButton
        self.accentTitle = dto.text.accentTitle
        self.customHeadline = dto.text.customHeadline
        self.customSubheadline = dto.text.customSubheadline

        // Appearance
        self.appearanceMode = dto.appearance.mode.flatMap { AppearanceMode(rawValue: $0.rawValue) }
        self.accentColor = dto.appearance.accentColor
        self.accentTitleColor = dto.appearance.accentTitleColor
    }
    
    /// Empty values for fallback scenarios
    static let empty = UIValues(
        appName: nil, title: nil, subtitle: nil, offerDescription: nil,
        instructionsTitle: nil, lastStepHeader: nil, lastStepDescription: nil,
        creditClaimedTitle: nil, creditClaimedSubtitle: nil, applyCreditsButton: nil,
        accentTitle: nil, customHeadline: nil, customSubheadline: nil,
        appearanceMode: nil, accentColor: nil, accentTitleColor: nil
    )

    private init(
        appName: String?, title: String?, subtitle: String?, offerDescription: String?,
        instructionsTitle: String?, lastStepHeader: String?, lastStepDescription: String?,
        creditClaimedTitle: String?, creditClaimedSubtitle: String?, applyCreditsButton: String?,
        accentTitle: String?, customHeadline: String?, customSubheadline: String?,
        appearanceMode: AppearanceMode?, accentColor: String?, accentTitleColor: String?
    ) {
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.offerDescription = offerDescription
        self.instructionsTitle = instructionsTitle
        self.lastStepHeader = lastStepHeader
        self.lastStepDescription = lastStepDescription
        self.creditClaimedTitle = creditClaimedTitle
        self.creditClaimedSubtitle = creditClaimedSubtitle
        self.applyCreditsButton = applyCreditsButton
        self.accentTitle = accentTitle
        self.customHeadline = customHeadline
        self.customSubheadline = customSubheadline
        self.appearanceMode = appearanceMode
        self.accentColor = accentColor
        self.accentTitleColor = accentTitleColor
    }
}

// MARK: - Entitlement Configuration

/// Entitlement configuration - IAP or Native mode.
/// Mode is implicit: if `iap` has a productId, use IAP mode; otherwise use Native.
struct EntitlementConfiguration: Codable, Sendable {
    let iap: IAPEntitlement?
    let native: NativeEntitlement?
    
    /// True if app uses IAP mode (has productId configured)
    var usesIAPMode: Bool { iap != nil }
    
    /// IAP product ID if configured
    var iapProductId: String? { iap?.productId }
    
    /// Entitlement value for template substitution (from native config)
    var entitlementValue: String? { native?.value }
    
    /// Entitlement unit for template substitution (from native config)
    var entitlementUnit: String? { native?.unit }
    
    struct IAPEntitlement: Codable, Sendable {
        let productId: String
    }
    
    struct NativeEntitlement: Codable, Sendable {
        let type: String
        let value: String
        let unit: String
        let durationDays: Int
    }
    
    init(from dto: DTO.RemoteConfig.EntitlementsConfig) {
        self.iap = dto.iap.map { IAPEntitlement(productId: $0.productId) }
        self.native = dto.native.map {
            NativeEntitlement(type: $0._type, value: $0.value, unit: $0.unit, durationDays: $0.durationDays)
        }
    }
    
    /// Empty entitlements for fallback scenarios
    static let empty = EntitlementConfiguration(iap: nil, native: nil)
    
    private init(iap: IAPEntitlement?, native: NativeEntitlement?) {
        self.iap = iap
        self.native = native
    }
}

// MARK: - Experiment Configuration

/// Experiment configuration for A/B testing features.
struct ExperimentConfiguration: Codable, Sendable {
    let ncl: NCLExperiment?
    
    struct NCLExperiment: Codable, Sendable {
        let rolloutPct: Int
        let assignmentVersion: Int
        let enabled: Bool
    }
    
    init(from dto: DTO.RemoteConfig.ExperimentsConfig) {
        self.ncl = dto.ncl.map {
            NCLExperiment(rolloutPct: $0.rolloutPct, assignmentVersion: $0.assignmentVersion, enabled: $0.enabled)
        }
    }
    
    /// Empty experiments for fallback scenarios
    static let empty = ExperimentConfiguration(ncl: nil)
    
    private init(ncl: NCLExperiment?) {
        self.ncl = ncl
    }
}
