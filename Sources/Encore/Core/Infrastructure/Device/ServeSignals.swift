// The fields the SDK reads on its own for each `/offers/search`: device, time and consent
// (CONTRACT 2.3 and 2.5). No IDFA and no ATT read on iOS (D10). Each read has a /config switch.

import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// Device and time fields for one search. Contextual, like country and platform: sent at every user
/// scope, personalization off included; only `signals.deviceReads` turns them off (ruling D).
internal struct DeviceSignals: Sendable, Equatable {
    var model: String?
    var connectionType: String?
    var lowPowerMode = false
    var timeZone: String?
    var appVersion: String?
    var offersRenderMs: Int?
    var networkRttMs: Int?
    /// `attributes.osVersion`, as `/offers/message` takes it, such as `17.5.1`.
    var osVersion: String?
    /// `context.device.type`: `phone`, `tablet` or `desktop`.
    var type: String?
}

/// Consent and opt-out keys for `attributes`, read from the IAB storage keys and the app's switch.
/// Privacy values are forwarded as stored: the server reads a malformed one as an opt-out, so the SDK never cleans one away.
internal struct ConsentSignals: Sendable, Equatable, Encodable {
    /// `IABGPP_GppSID`: the ids when every token parses, else the stored text, which the server reads as an opt-out.
    enum SectionIds: Sendable, Equatable, Encodable {
        case ids([Int])
        case unreadable(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .ids(let ids): try container.encode(ids)
            case .unreadable(let raw): try container.encode(raw)
            }
        }
    }

    var gdprApplies: Bool?
    var consentString: String?
    var usPrivacy: String?
    var gpp: String?
    var gppSid: SectionIds?
    var personalization: Bool?

    var isEmpty: Bool { self == ConsentSignals() }

    /// The IAB keys a CMP writes to `UserDefaults.standard`.
    static func read(from defaults: UserDefaults, personalization: Bool?) -> ConsentSignals {
        var signals = ConsentSignals(personalization: personalization)
        if let raw = defaults.object(forKey: "IABTCF_gdprApplies") {
            // 0/1 as a number or a string; any other value counts as applies, as the server reads a malformed one.
            let flag = (raw as? NSNumber)?.intValue ?? (raw as? String).flatMap { Int($0) }
            signals.gdprApplies = flag.map { $0 != 0 } ?? true
        }
        signals.consentString = nonEmpty(defaults.string(forKey: "IABTCF_TCString"))
        signals.usPrivacy = nonEmpty(defaults.string(forKey: "IABUSPrivacy_String"))
        signals.gpp = nonEmpty(defaults.string(forKey: "IABGPP_HDR_GppString"))
        if let sid = nonEmpty(defaults.string(forKey: "IABGPP_GppSID")) {
            let tokens = sid.split(whereSeparator: { $0 == "_" || $0 == "," })
            let ids = tokens.compactMap { Int($0) }
            signals.gppSid = ids.count == tokens.count && !ids.isEmpty ? .ids(ids) : .unreadable(sid)
        }
        return signals
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// The readers behind each search's automatic fields; tests inject fixed ones (V5-21).
internal struct ServeSignalSource: Sendable {
    var device: @Sendable () -> DeviceSignals
    var consent: @Sendable () -> ConsentSignals
    /// The app's own switch alone, sent even with the consent reads off.
    var personalization: @Sendable () -> Bool? = { Personalization.current }
    /// The device locale's currency for a purchase moment, read only when one is sent.
    var storefrontCurrency: @Sendable () async -> String?
    /// The `/config` switches; the defaults until `/config` says otherwise.
    var switches: @Sendable () -> ServeSwitches
    /// The headline copy source for a search with no sheet overrides (launch and prefetch searches).
    var headlineCopySource: @Sendable (UseCase?) -> String? = { _ in nil }

    static let live = ServeSignalSource(
        device: {
            DeviceSignals(
                model: DeviceModel.identifier,
                connectionType: ConnectionMonitor.shared.current,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeZone: TimeZone.current.identifier,
                appVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { String($0.prefix(50)) },
                offersRenderMs: ServeTimings.lastRenderMs,
                networkRttMs: ServeTimings.lastRttMs,
                osVersion: DeviceModel.osVersion,
                type: DeviceModel.type
            )
        },
        consent: { ConsentSignals.read(from: .standard, personalization: Personalization.current) },
        storefrontCurrency: { await StorefrontCurrency.current() },
        switches: { ServeSwitches.current },
        headlineCopySource: { useCase in
            let useCase = useCase ?? .reduceChurn
            let values = Encore.shared.services?.remoteConfigManager.config(for: useCase)?.ui.values
            return HeadlineCopySource.resolve(useCase: useCase, overrides: [:], uiValues: values)
        }
    )
}

// MARK: - Readers

internal enum DeviceModel {
    /// `hw.machine` (for example `iPhone16,2`); the simulated model on a simulator. Capped at 32.
    static let identifier: String? = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return String(simulated.prefix(32))
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : String(value.prefix(32))
    }()

    /// The OS version, with the patch only when it is not zero.
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    /// From the model, with no main-actor read: an iPad is a tablet, an iOS app on a Mac a desktop.
    static let type: String? = {
        if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp { return "desktop" }
        guard let model = identifier else { return nil }
        if model.hasPrefix("iPad") { return "tablet" }
        if model.hasPrefix("iPhone") || model.hasPrefix("iPod") { return "phone" }
        return nil
    }()
}

/// The current network path, from one `NWPathMonitor` started on first use. Nil before its first update.
internal final class ConnectionMonitor: @unchecked Sendable {
    static let shared = ConnectionMonitor()
    private let monitor = NWPathMonitor()
    private let state = Atomic<String?>(nil)

    private init() {
        monitor.pathUpdateHandler = { [state] path in state.value = Self.wire(path) }
        monitor.start(queue: DispatchQueue(label: "com.encore.connection-monitor", qos: .utility))
    }

    var current: String? { state.value }

    static func wire(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
        return "other"
    }
}

internal enum StorefrontCurrency {
    /// The device locale's currency (Ryan's ruling R7: no store read in 2.7.x).
    static func current() async -> String? {
        if #available(iOS 16.0, *) { return Locale.current.currency?.identifier.uppercased() }
        return Locale.current.currencyCode?.uppercased()
    }
}

/// The two timings that describe the previous serve (CONTRACT 2.3).
internal enum ServeTimings {
    private static let rtt = Atomic<Int?>(nil)
    private static let render = Atomic<Int?>(nil)
    private static let responses = Atomic(PresentationMap<UInt64>())

    static var lastRttMs: Int? { rtt.value }
    static var lastRenderMs: Int? { render.value }

    static func recordRoundTrip(startNs: UInt64, endNs: UInt64 = PresentationClock.nowNs()) {
        rtt.value = endNs > startNs ? Int((endNs - startNs) / 1_000_000) : 0
    }

    /// The serve response behind `presentationId` arrived.
    static func responseArrived(for presentationId: String, atNs: UInt64 = PresentationClock.nowNs()) {
        responses.mutate { $0[presentationId] = atNs }
    }

    /// The presentation's first offer was drawn: its time since the response becomes the next `offersRenderMs`.
    static func firstOfferDrawn(for presentationId: String, atNs: UInt64 = PresentationClock.nowNs()) {
        guard let start = responses.value[presentationId] else { return }
        responses.mutate { $0[presentationId] = nil }
        render.value = atNs > start ? Int((atNs - start) / 1_000_000) : 0
    }

    #if DEBUG
    static func resetForTesting() {
        rtt.value = nil
        render.value = nil
        responses.value = PresentationMap()
    }
    #endif
}

/// The app's own personalization switch, saved on the device so the next launch's first serve has it (D13).
internal enum Personalization {
    static let storageKey = "encore.personalization"

    /// nil until the app sets it: no key is sent.
    static var current: Bool? {
        UserDefaults.standard.object(forKey: storageKey) as? Bool
    }

    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
    }

    #if DEBUG
    static func resetForTesting() { UserDefaults.standard.removeObject(forKey: storageKey) }
    #endif
}
