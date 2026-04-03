// Sources/Encore/Internal/Core/Configuration.swift
//
// Environment detection and SDK configuration logic.
// Extracted from Encore.swift to reduce God Object size.
//

import Foundation

// MARK: - Configuration

/// The fully resolved, immutable context for the current SDK session.
/// Captured once at `configure()` and used throughout the service graph.
internal struct Configuration: Sendable {
    // MARK: - App Context (Host App Identity)
    let apiKey: String
    let appBundleId: String
    
    // MARK: - SDK Context (Runtime Behavior)
    let environment: EnvironmentConfiguration
    let logLevel: Encore.LogLevel
    
    init(
        apiKey: String,
        logLevel: Encore.LogLevel = .error,
        environment: EnvironmentConfiguration? = nil
    ) {
        // App Context
        self.apiKey = apiKey
        self.appBundleId = Bundle.main.bundleIdentifier ?? "unknown"
        
        // SDK Context
        self.environment = environment ?? EnvironmentDetector.detect()
        self.logLevel = logLevel
    }
}

// MARK: - Environment Configuration

/// Represents the SDK's runtime environment.
/// Single source of truth for all environment-specific configuration.
internal enum EnvironmentConfiguration: CustomStringConvertible, Equatable, Sendable {
    case local
    case development
    case staging
    case production
    case mock(MockScenario)
    
    // MARK: - URLs
    
    var apiBaseURL: URL {
        let urlString: String = switch self {
        case .local:       "http://localhost:4000/publisher/sdk/v1"
        case .development: "https://api.dev.encorekit.com/publisher/sdk/v1"
        case .staging:     "https://api.staging.encorekit.com/publisher/sdk/v1"
        case .production:  "https://api.encorekit.com/encore/publisher/sdk/v1"
        case .mock:        "https://mock.api.encorekit.com"
        }
        return safeURL(urlString)
    }
    
    var analyticsBaseURL: URL {
        let urlString: String = switch self {
        case .local:       "http://localhost:8081/v1"
        case .development: "https://api.dev.encorekit.com/analytics/v1"
        case .staging:     "https://api.staging.encorekit.com/analytics/v1"
        case .production:  "https://api.encorekit.com/analytics/v1"
        case .mock:        "https://mock.api.encorekit.com/analytics/v1"
        }
        return safeURL(urlString)
    }
    
    // MARK: - Infrastructure Builders
    
    /// Returns the analytics sinks for this environment.
    func analyticsSinks(httpClient: HTTPClientProtocol) -> [AnalyticsSink] {
        switch self {
        case .mock:
            [ConsoleSink()]
        case .local:
            [BackendAnalyticsSink(httpClient: httpClient)]
        case .development, .staging, .production:
            [PostHogSink(), BackendAnalyticsSink(httpClient: httpClient)]
        }
    }
    
    /// Returns the error providers for this environment.
    func errorProviders(httpClient: HTTPClientProtocol) -> [ErrorProvider] {
        switch self {
        case .mock:
            []
        case .local:
            [BackendErrorProvider(httpClient: httpClient)]
        case .development, .staging, .production:
            [SentryErrorProvider()]
        }
    }
    
    // MARK: - Helpers
    
    var isMock: Bool { if case .mock = self { true } else { false } }
    
    var description: String {
        switch self {
        case .local: "local"
        case .development: "development"
        case .staging: "staging"
        case .production: "production"
        case .mock(let scenario): "mock(\(scenario))"
        }
    }
}

// MARK: - Environment Detection

/// Detects the appropriate environment based on build configuration.
///
/// **Security Note**: Non-production environments are ONLY available in DEBUG builds.
/// Release builds of the SDK (distributed to clients) will ALWAYS use production,
/// regardless of any environment variables or Info.plist settings.
internal struct EnvironmentDetector {
    
    /// Determines the appropriate environment configuration.
    static func detect() -> EnvironmentConfiguration {
        #if DEBUG
        // Development builds: allow environment overrides for testing
        Logger.debug("🔧 [Config] Environment specified in DEBUG")
        return detectDevelopmentEnvironment()
        #else
        // Release builds: ALWAYS production - no overrides allowed
        Logger.debug("🔧 [Config] Release build, using production")
        return .production
        #endif
    }
    
    #if DEBUG
    /// Only available in DEBUG builds - detects environment from config.
    /// Defaults to production if no override is set (defense in depth).
    private static func detectDevelopmentEnvironment() -> EnvironmentConfiguration {
        // Priority 1: Process Environment (Launch Arguments/Schemes)
        if let processEnv = ProcessInfo.processInfo.environment["EncoreEnvironment"] {
            Logger.debug("🔧 [Config] Using process environment: \(processEnv)")
            return parse(processEnv)
        }
        
        // Priority 2: Info.plist (xcconfig)
        if let buildConfigEnv = Bundle.main.object(forInfoDictionaryKey: "EncoreEnvironment") as? String {
            Logger.debug("🔧 [Config] Using Info.plist environment: \(buildConfigEnv)")
            return parse(buildConfigEnv)
        }
        
        // Priority 3: Default to production (defense in depth - if DEBUG flag leaks to release, use production)
        Logger.debug("🔧 [Config] No environment override, defaulting to production")
        return .production
    }
    
    private static func parse(_ value: String) -> EnvironmentConfiguration {
        switch value.lowercased() {
        case "local":
            return .local
        case "development":
            return .development
        case "staging":
            return .staging
        case "production":
            return .production
        case "mock":
            return .mock(.successWithOffer)
        default:
            Logger.warn("[Config] Unknown environment '\(value)', defaulting to production")
            return .production
        }
    }
    #endif
}
