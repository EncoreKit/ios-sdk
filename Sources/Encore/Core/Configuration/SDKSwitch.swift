// The host's on/off switch behind `Encore.shared.isEnabled`, readable from any thread.
// Process memory only: every launch starts on (docs/architecture/enabled.md).

import Foundation

internal enum SDKSwitch {
    private static let state = Atomic(true)

    static var isOn: Bool {
        get { state.value }
        set { state.value = newValue }
    }

    /// Thrown in place of a request while the SDK is off: no request leaves the device.
    static let refusal = EncoreError.transport(.network(URLError(.cancelled)))

    /// Whether a request may leave now: on, or off with a sheet that was already open (it finishes, as on Android).
    static func allowsRequest(openSheet: Bool) async -> Bool {
        if isOn { return true }
        guard openSheet else { return false }
        return await MainActor.run { OfferSheetCoordinator.isPresenting }
    }
}

/// Refuses every request while the SDK is off, so no feature can reach the network by a path the facade did not gate.
/// `allowsOpenSheet` is true only for the claim client (`ServiceContainer.claimClient`), so a sheet already open can
/// finish its claim; every other client refuses even then.
internal struct SwitchedHTTPClient: HTTPClientProtocol {
    let base: HTTPClientProtocol
    var allowsOpenSheet = false

    func request<T: Decodable>(
        path: String, method: String, body: Encodable?, query: [String: String?]?, headers: [String: String]
    ) async throws -> T {
        guard await SDKSwitch.allowsRequest(openSheet: allowsOpenSheet) else { throw SDKSwitch.refusal }
        return try await base.request(path: path, method: method, body: body, query: query, headers: headers)
    }

    func request<T: Decodable>(
        path: String, method: String, bodyData: Data?, query: [String: String?]?, headers: [String: String]
    ) async throws -> T {
        guard await SDKSwitch.allowsRequest(openSheet: allowsOpenSheet) else { throw SDKSwitch.refusal }
        return try await base.request(path: path, method: method, bodyData: bodyData, query: query, headers: headers)
    }

    func requestWithStatus<T: Decodable>(
        path: String, method: String, body: Encodable?, query: [String: String?]?, headers: [String: String]
    ) async throws -> (T, Int) {
        guard await SDKSwitch.allowsRequest(openSheet: allowsOpenSheet) else { throw SDKSwitch.refusal }
        return try await base.requestWithStatus(path: path, method: method, body: body, query: query, headers: headers)
    }
}
