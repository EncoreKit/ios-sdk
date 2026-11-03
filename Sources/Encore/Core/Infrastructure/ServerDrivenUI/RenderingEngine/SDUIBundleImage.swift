// An image in the app's main bundle behind a URL, so a look's `asyncImage` slot draws it with no
// new element: the trigger host writes the URL, `CachedAsyncImage` reads it.

import UIKit

enum SDUIBundleImage {
    static let scheme = "encore-bundle"

    /// Test seam: where a name resolves. The app's main bundle.
    nonisolated(unsafe) static var provider: @Sendable (String) -> UIImage? = { UIImage(named: $0, in: .main, with: nil) }

    /// A key per launch that only host-written URLs carry, so served data cannot name an app image.
    private static let hostKey = UUID().uuidString

    /// `encore-bundle://image/<name>?host=<key>`, the name percent-encoded.
    static func url(named name: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "image"
        components.path = "/" + name
        components.queryItems = [URLQueryItem(name: "host", value: hostKey)]
        // Unreachable (the path setter encodes every name); an empty path reads as no image.
        return components.url ?? URL(string: "\(scheme)://image/") ?? URL(fileURLWithPath: "/")
    }

    /// Whether `url` has the bundle scheme, in any case.
    static func isBundle(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    /// The name a bundle URL carries; nil for any other URL.
    static func name(of url: URL) -> String? {
        guard isBundle(url) else { return nil }
        let name = url.path.dropFirst()
        return name.isEmpty ? nil : String(name)
    }

    /// Whether the host wrote `url` with ``url(named:)`` in this launch.
    static func isHostWritten(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "host", value: hostKey)]
    }

    /// The app's image for a host-written URL; nil for any other.
    static func image(for url: URL) -> UIImage? {
        guard isHostWritten(url) else { return nil }
        return name(of: url).flatMap(provider)
    }
}
