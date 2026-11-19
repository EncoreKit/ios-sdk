// A sheet element's `animation`: a Lottie file drawn over the element, only when the host app links
// lottie-ios 4.x; otherwise the element draws. EncoreKit never links Lottie; it finds `CompatibleAnimationView`
// at run time. Contract: backend docs/architecture/sdui-sheet-motion.md, "Layer 2".

import CryptoKit
import ObjectiveC
import SwiftUI
import UIKit

// MARK: - Model

/// The Lottie file a sheet element plays over itself; the element is the fallback.
struct SDUIElementAnimation: Equatable {
    let url: String
    /// Nil is true. False plays once and holds the last frame.
    var loop: Bool?
    /// Nil is true. False draws the first frame and does not play.
    var autoplay: Bool?
    /// Offer pictures for the file's image assets, by asset id.
    var images: [String: SDUIAnimationImageSlot]?
    /// Fired when a play-once file ends, or after `fallbackSeconds` when it cannot play.
    var onComplete: SDUIAction?
    /// The served `onComplete`, so equality covers the whole action, its transition included.
    var onCompleteJSON: Data?
    var fallbackSeconds: Double?

    static func == (a: SDUIElementAnimation, b: SDUIElementAnimation) -> Bool {
        a.url == b.url && a.loop == b.loop && a.autoplay == b.autoplay && a.images == b.images && a.fallbackSeconds == b.fallbackSeconds
            && a.onCompleteJSON == b.onCompleteJSON
    }

    /// An http or https URL, the rule `asyncImage.url` follows.
    var resolvedURL: URL? {
        guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

extension KeyedDecodingContainer {
    /// A bad animation drops only the animation with one warning; the element draws as it is.
    func decodeIfPresent(_ type: SDUIElementAnimation.Type, forKey key: K) throws -> SDUIElementAnimation? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let decoder = try superDecoder(forKey: key)
        let object = decoder.motionJSON?.object
        let problem: String? = {
            guard let object else { return "must be an object" }
            guard let url = object["url"]?.string, SDUIElementAnimation(url: url).resolvedURL != nil else { return "url is not an http or https URL" }
            return SheetMotionRules.animationFlagsProblem(object)
        }()
        guard problem == nil, let object, let url = object["url"]?.string else {
            Logger.warn(.presentation, "[SDUI] Dropped an animation: \(problem ?? "it does not decode"); drawing the element")
            return nil
        }
        func flag(_ key: String) -> Bool? { if case .bool(let b)? = object[key] { return b } else { return nil } }
        var animation = SDUIElementAnimation(url: url, loop: flag("loop"), autoplay: flag("autoplay"))
        if let raw = object["images"] {
            let read = SheetMotionRules.imageSlots(raw)
            for problem in read.problems { Logger.warn(.presentation, "[SDUI] Dropped an animation image slot: \(problem)") }
            animation.images = read.slots.isEmpty ? nil : read.slots
        }
        if let raw = object["onComplete"], !SheetMotionRules.isAbsent(raw) {
            if let problem = Self.completionProblem(object) {
                sduiFlowWarn("dropped animation.onComplete: \(problem)")
            } else {
                animation.onComplete = try? JSONDecoder().decode(SDUIAction.self, from: raw.serialized())
                animation.onCompleteJSON = animation.onComplete.map { _ in raw.serialized() }
                animation.fallbackSeconds = object["fallbackSeconds"]?.number
            }
        }
        return animation
    }

    /// Why an animation's `onComplete` cannot fire, or nil: a play-once file with `fallbackSeconds` 0.5 to 10.
    static func completionProblem(_ object: SkinObject) -> String? {
        guard case .bool(false)? = object["loop"] else { return "needs loop false" }
        guard SheetMotionRules.isWithin(object["fallbackSeconds"], 0.5, 10) else { return "needs fallbackSeconds from 0.5 to 10" }
        return SheetMotionRules.flowActionProblem(object["onComplete"])
    }

    /// The served style never sets the element's animation; only the element decoder does.
    func decodeIfPresent(_ type: SDUIElementAnimationSpec.Type, forKey key: K) throws -> SDUIElementAnimationSpec? { nil }
}

/// An offer picture for one of the Lottie file's image assets.
struct SDUIAnimationImageSlot: Equatable {
    /// The position in the sheet's offers, as a `forEach` over offers with this `offset`.
    let offer: Int
    /// `offerLogoImage`, `offerHeroImage` or `offerPrimaryCreative`.
    let binding: SDUICreativeBinding

    /// The picture's URL for the sheet's `offers`, or nil when that offer or picture does not exist.
    func url(in offers: [Offer]) -> URL? {
        guard offers.indices.contains(offer) else { return nil }
        let target = offers[offer]
        let raw: String?
        switch binding {
        case .offerLogoImage: raw = target.displayLogoUrl
        case .offerHeroImage: raw = target.displayHeroImageUrl
        case .offerPrimaryCreative: raw = target.displayPrimaryImageUrl
        case .instructionImage: raw = nil
        }
        return SDUIImageSlotPlan.nonBlank(raw).flatMap { URL(string: $0) }
    }
}

/// The one key the element decoder reads beside the element's own decode.
enum SDUIElementAnimationKey: String, CodingKey { case animation }

/// An element's animation as the style carries it to the renderer, with the content mode it draws in.
struct SDUIElementAnimationSpec: Decodable, Equatable {
    let animation: SDUIElementAnimation
    let contentMode: ContentMode

    init(animation: SDUIElementAnimation, contentMode: ContentMode) {
        self.animation = animation
        self.contentMode = contentMode
    }

    init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "set by the element decoder only"))
    }
}

extension SDUIElement {
    /// The element's key in the template, such as `asyncImage`.
    var kindName: String {
        switch self {
        case .text: return "text"
        case .systemImage: return "systemImage"
        case .asyncImage: return "asyncImage"
        case .asyncVideo: return "asyncVideo"
        case .appIcon: return "appIcon"
        case .button: return "button"
        case .vStack: return "vStack"
        case .hStack: return "hStack"
        case .zStack: return "zStack"
        case .spacer: return "spacer"
        case .shape: return "shape"
        case .gradient: return "gradient"
        case .scrollView: return "scrollView"
        case .forEach: return "forEach"
        case .conditional: return "conditional"
        case .group: return "group"
        case .textField: return "textField"
        case .toggle: return "toggle"
        case .slideButton: return "slideButton"
        case .compactPageIndicator: return "compactPageIndicator"
        case .confetti: return "confetti"
        case .progress: return "progress"
        case .marquee: return "marquee"
        case .empty: return "empty"
        }
    }

    /// The element with `animation` in its style, where the renderer draws it. An element with no style has no
    /// frame of its own to draw in, so it keeps drawing itself with one warning.
    func withAnimation(_ animation: SDUIElementAnimation) -> SDUIElement {
        let mode: SDUIContentMode? = {
            switch self {
            case .asyncImage(let e): return e.contentMode
            case .asyncVideo(let e): return e.contentMode
            default: return nil
            }
        }()
        let spec = SDUIElementAnimationSpec(animation: animation, contentMode: mode?.contentMode ?? .fit)
        if case .spacer = self {} else if let animated = restyled({ $0.animation = spec }) { return animated }
        SDUILottieWarnings.once("kind:\(kindName)", "[SDUI] Dropped an animation: a \(kindName) has no frame to draw it in; drawing the element")
        return self
    }
}

// MARK: - Warnings

/// One warning per animation URL for the life of the process, whatever failed.
enum SDUILottieWarnings {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var warned: Set<String> = []

    /// Returns the message when it was logged, nil when this URL already warned.
    @discardableResult
    static func warn(_ url: String, _ reason: String) -> String? {
        once(url, "[SDUI] Animation \(url) \(reason); drawing the element")
    }

    /// Logs `message` the first time `key` is seen in the process.
    @discardableResult
    static func once(_ key: String, _ message: String) -> String? {
        lock.lock()
        let first = warned.insert(key).inserted
        lock.unlock()
        guard first else { return nil }
        Logger.warn(.presentation, message)
        return message
    }

    #if DEBUG
    static func resetForTesting() {
        lock.lock()
        warned = []
        lock.unlock()
    }
    #endif
}

// MARK: - Loader

/// Downloads a Lottie file once per URL into memory and a disk cache, never revalidated: animation
/// URLs are content hashed and served immutable. A bad status, size or file is remembered; a network error is retried.
final class SDUILottieLoader: @unchecked Sendable {
    static let shared = SDUILottieLoader()

    /// The largest Lottie file the SDK plays: Lottie parses it on the main thread, so the cap bounds that hitch.
    static let maxBytes = 150 * 1024

    private let session: URLSession
    private let directory: URL?
    private let lock = NSLock()
    private var memory: [URL: Data] = [:]
    private var failed: Set<URL> = []
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(session: URLSession = SDUILottieLoader.defaultSession, directory: URL? = SDUILottieLoader.defaultDirectory) {
        self.session = session
        self.directory = directory
    }

    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // The loader keeps its own cache; animation hosts get no cookies or credentials from the app.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EncoreAnimations", isDirectory: true)
    }

    static func cacheFile(for url: URL, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).json")
    }

    /// Memory, else disk, without the network.
    func cached(_ url: URL) -> Data? {
        lock.lock()
        if let data = memory[url] { lock.unlock(); return data }
        lock.unlock()
        guard let directory, let data = try? Data(contentsOf: Self.cacheFile(for: url, in: directory)) else { return nil }
        guard Self.problem(with: data) == nil else {
            try? FileManager.default.removeItem(at: Self.cacheFile(for: url, in: directory))
            return nil
        }
        remember(data, for: url)
        return data
    }

    /// The file's bytes, or nil after one warning. Concurrent callers for one URL share one download.
    func load(_ url: URL) async -> Data? {
        if let data = cached(url) { return data }
        lock.lock()
        if failed.contains(url) { lock.unlock(); return nil }
        if let task = inFlight[url] { lock.unlock(); return await task.value }
        let task = Task { await self.download(url) }
        inFlight[url] = task
        lock.unlock()
        let data = await task.value
        lock.lock()
        inFlight[url] = nil
        lock.unlock()
        return data
    }

    private func download(_ url: URL) async -> Data? {
        var data = Data()
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
            func stop(_ reason: String) -> Data? {
                bytes.task.cancel()
                return fail(url, reason)
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return stop("answered HTTP \(http.statusCode)")
            }
            // A declared size over the cap is refused before the body is read, and a read stops at the cap.
            if response.expectedContentLength > Int64(Self.maxBytes) { return stop("is larger than 150 KB") }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxBytes { return stop("is larger than 150 KB") }
            }
        } catch {
            // Offline or a timeout is the moment, not the file: the next presentation tries again.
            let ns = error as NSError
            return fail(url, "did not download (\(ns.domain) \(ns.code))", remember: false)
        }
        if let problem = Self.problem(with: data) { return fail(url, problem) }
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: Self.cacheFile(for: url, in: directory), options: .atomic)
        }
        remember(data, for: url)
        return data
    }

    /// Why `data` is not a playable Lottie file, or nil: the size cap and the keys every Lottie file has.
    static func problem(with data: Data) -> String? {
        guard data.count <= maxBytes else { return "is larger than 150 KB" }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["layers"] is [Any], ["w", "h", "ip", "op", "fr"].allSatisfy({ object[$0] is NSNumber })
        else { return "is not a Lottie file" }
        return nil
    }

    private func remember(_ data: Data, for url: URL) {
        lock.lock()
        memory[url] = data
        lock.unlock()
    }

    /// One warning per URL; only an HTTP status, size or parse failure is remembered for the process.
    private func fail(_ url: URL, _ reason: String, remember: Bool = true) -> Data? {
        lock.lock()
        if remember { failed.insert(url) }
        lock.unlock()
        SDUILottieWarnings.warn(url.absoluteString, reason)
        return nil
    }

    #if DEBUG
    /// Test seam: forget what this process learned, keeping the disk cache.
    func resetForTesting() {
        lock.lock()
        memory = [:]; failed = []; inFlight = [:]
        lock.unlock()
    }
    #endif
}

// MARK: - Runtime bridge

/// Drives lottie-ios's `@objc` `CompatibleAnimationView` through the Objective-C runtime, so the SDK
/// compiles and runs without Lottie. Every selector is checked first: a missing one means no Lottie.
@MainActor
enum SDUILottieBridge {
    /// lottie-ios 4.x's Objective-C name for the class. Tests point it at a stand-in.
    static var className = "Lottie.CompatibleAnimationView"

    private static let initWithData = NSSelectorFromString("initWithData:")
    private static let required = ["play", "pause", "isAnimationPlaying", "currentProgress", "setCurrentProgress:",
                                   "loopAnimationCount", "setLoopAnimationCount:", "duration"].map(NSSelectorFromString)

    /// The class when the host links a Lottie this bridge can drive, else nil.
    static var viewClass: UIView.Type? {
        guard let cls = NSClassFromString(className) as? UIView.Type, cls.instancesRespond(to: initWithData),
              required.allSatisfy(cls.instancesRespond(to:)) else { return nil }
        return cls
    }

    static var isAvailable: Bool { viewClass != nil }

    /// A view for `data`, set to loop or play once, at progress 0 and not playing. Nil when Lottie is
    /// absent or the file did not load (lottie-ios builds an empty view for bytes it cannot parse).
    static func makeView(data: Data, loop: Bool, images: SDUILottieImageProvider? = nil) -> UIView? {
        guard let cls = viewClass else { return nil }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        typealias InitFn = @convention(c) (AnyObject, Selector, NSData) -> Unmanaged<UIView>
        let allocSel = NSSelectorFromString("alloc")
        guard let allocImp = class_getMethodImplementation(object_getClass(cls), allocSel),
              let initImp = class_getMethodImplementation(cls, initWithData) else { return nil }
        let raw = unsafeBitCast(allocImp, to: AllocFn.self)(cls, allocSel).takeUnretainedValue()
        let view = unsafeBitCast(initImp, to: InitFn.self)(raw, initWithData, data as NSData).takeRetainedValue()
        guard number(view, "duration") > 0 else { return nil }
        view.setValue(loop ? -1.0 : 1.0, forKey: "loopAnimationCount")
        // Pause in the background rather than restart: the sheet resumes it when it is seen again.
        if view.responds(to: NSSelectorFromString("setBackgroundMode:")) { view.setValue(1, forKey: "backgroundMode") }
        view.setValue(0.0, forKey: "currentProgress")
        // A Lottie without the provider keeps its embedded placeholders, so the animation still plays.
        if let images, view.responds(to: NSSelectorFromString("setCompatibleAnimationImageProvider:")) {
            view.setValue(images, forKey: "compatibleAnimationImageProvider")
        }
        return view
    }

    static func isPlaying(_ view: UIView) -> Bool { (view.value(forKey: "isAnimationPlaying") as? Bool) == true }
    static func progress(_ view: UIView) -> Double { number(view, "currentProgress") }
    static func play(_ view: UIView) { view.perform(NSSelectorFromString("play")) }
    static func pause(_ view: UIView) { view.perform(NSSelectorFromString("pause")) }

    private static func number(_ view: UIView, _ key: String) -> Double {
        (view.value(forKey: key) as? NSNumber)?.doubleValue ?? 0
    }
}

// MARK: - Offer pictures

/// Answers lottie-ios's `CompatibleAnimationImageProvider` (`imageForAssetWithName:`) without linking Lottie.
/// Built only when that protocol requires exactly this selector. A provider replaces Lottie's own, so it also
/// decodes the file's embedded placeholders (already cut to their asset's size in the bytes).
final class SDUILottieImageProvider: NSObject, @unchecked Sendable {
    /// Pictures by the marker each filled slot's asset was renamed to.
    private let pictures: [String: CGImage]

    private init(pictures: [String: CGImage]) {
        self.pictures = pictures
        super.init()
    }

    /// A provider for `pictures`, or nil when the host's Lottie does not take one this class can answer.
    static func make(pictures: [String: CGImage]) -> SDUILottieImageProvider? {
        guard compatibleProtocol != nil else { return nil }
        return SDUILottieImageProvider(pictures: pictures)
    }

    /// Lottie's ObjC names for the protocol. Tests point it at a stand-in.
    nonisolated(unsafe) static var protocolNames = ["_TtP6Lottie32CompatibleAnimationImageProvider_", "Lottie.CompatibleAnimationImageProvider"]

    /// Lottie's protocol when its only required method is `imageForAssetWithName:`, adopted at run time; else nil,
    /// so a renamed or extended protocol can never reach a selector this class does not answer.
    static var compatibleProtocol: Protocol? {
        for name in protocolNames {
            guard let proto = objc_getProtocol(name) else { continue }
            var count: UInt32 = 0
            let required = protocol_copyMethodDescriptionList(proto, true, true, &count)
            defer { free(required) }
            let selector = NSSelectorFromString("imageForAssetWithName:")
            let only = count == 1 && required.map { $0[0].name == selector } == true
            guard only, protocol_getMethodDescription(proto, selector, true, true).name == selector else { return nil }
            if !class_conformsToProtocol(SDUILottieImageProvider.self, proto) { class_addProtocol(SDUILottieImageProvider.self, proto) }
            return proto
        }
        return nil
    }

    @objc(imageForAssetWithName:)
    func imageForAsset(name: String) -> CGImage? {
        if let picture = pictures[name] { return picture }
        return Self.decodeDataURI(name)
    }

    /// No slot or placeholder image decodes past this on a side, so a bad file cannot exhaust memory.
    static let maxPixels = 1024

    /// A `data:image/...;base64,` asset, decoded to at most `maxPixels` on a side; nil for anything else.
    static func decodeDataURI(_ value: String, maxPixels: Int = maxPixels) -> CGImage? {
        dataURIBytes(value).flatMap { decode($0, maxPixels: maxPixels) }
    }

    static func dataURIBytes(_ value: String) -> Data? {
        guard value.hasPrefix("data:image/"), let range = value.range(of: ";base64,") else { return nil }
        return Data(base64Encoded: String(value[range.upperBound...]), options: .ignoreUnknownCharacters)
    }

    /// `data` decoded straight to at most `maxPixels` on its longer side, never at full size first.
    static func decode(_ data: Data, maxPixels: Int) -> CGImage? {
        guard maxPixels > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image's own pixel size, read from its header without decoding it.
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The longer side to decode an image of `size` to so its shorter side still covers a `width` x `height` box:
    /// never larger than the image itself, and at most 1024.
    static func coveringLimit(_ size: CGSize, width: Double, height: Double) -> Int {
        guard width > 0, height > 0 else { return maxPixels }
        let scale = min(1, max(width / size.width, height / size.height))
        return min(maxPixels, Int((max(size.width, size.height) * scale).rounded(.up)))
    }

    /// `data` decoded so it covers a `width` x `height` box, no larger than needed and at most 1024 a side.
    static func decodeCovering(_ data: Data, width: Double, height: Double) -> CGImage? {
        guard let size = pixelSize(data) else { return nil }
        return decode(data, maxPixels: coveringLimit(size, width: width, height: height))
    }

    /// The marker a slot's asset is renamed to, so two identical placeholders still tell their slots apart.
    static func marker(_ id: String) -> String { "encore-slot:\(id)" }

    /// The bytes Lottie plays and the provider for filled slots (nil when none, or Lottie takes none). Path images
    /// are emptied and large embedded ones cut down in the bytes, since Lottie decodes them before any provider is set.
    /// Nil when the bytes cannot be read or written: draw the element.
    static func prepare(_ data: Data, pictures: [String: Data]) -> (data: Data, provider: SDUILottieImageProvider?)? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard var assets = root["assets"] as? [[String: Any]] else { return (data, nil) }
        let slotsUsable = !pictures.isEmpty && compatibleProtocol != nil
        var drawn: [String: CGImage] = [:]
        var changed = false
        for index in assets.indices where assets[index]["layers"] == nil {
            // A missing or non-string `p` is emptied like a path, so its `u` never reaches Lottie.
            let path = assets[index]["p"] as? String ?? ""
            guard path.hasPrefix("data:image/") else {
                assets[index]["p"] = ""
                assets[index]["u"] = ""
                changed = true
                continue
            }
            let width = (assets[index]["w"] as? NSNumber)?.doubleValue ?? 0
            let height = (assets[index]["h"] as? NSNumber)?.doubleValue ?? 0
            if slotsUsable, let id = assets[index]["id"] as? String, let bytes = pictures[id],
               let picture = decodeCovering(bytes, width: width, height: height).flatMap({ filled(UIImage(cgImage: $0), width: width, height: height) }) {
                drawn[marker(id)] = picture
                assets[index]["p"] = marker(id)
                assets[index]["u"] = ""
                changed = true
            } else if let smaller = smallerPlaceholder(path, width: width, height: height) {
                assets[index]["p"] = smaller
                changed = true
            }
        }
        guard changed else { return (data, nil) }
        root["assets"] = assets
        guard let out = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return (out, drawn.isEmpty ? nil : make(pictures: drawn))
    }

    /// A placeholder larger than its box, re-encoded at the covering size; nil when it is already small enough.
    static func smallerPlaceholder(_ uri: String, width: Double, height: Double) -> String? {
        guard let bytes = dataURIBytes(uri), let size = pixelSize(bytes) else { return nil }
        let limit = coveringLimit(size, width: width, height: height)
        guard CGFloat(limit) < max(size.width, size.height), let image = decode(bytes, maxPixels: limit),
              let png = UIImage(cgImage: image).pngData() else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// `image` scaled to fill a `width` x `height` box, centred and cropped, as Lottie stretches an image to its
    /// asset's box. One pixel per point, cut to at most 1024 a side, since the box comes from the downloaded file.
    static func filled(_ image: UIImage, width: Double, height: Double) -> CGImage? {
        guard width.isFinite, height.isFinite, width > 0, height > 0, image.size.width > 0, image.size.height > 0 else { return nil }
        let cap = min(1, Double(maxPixels) / max(width, height))
        let box = CGSize(width: max(1, (width * cap).rounded()), height: max(1, (height * cap).rounded()))
        let scale = max(box.width / image.size.width, box.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: box, format: format).image { _ in
            image.draw(in: CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2, width: size.width, height: size.height))
        }.cgImage
    }

    #if DEBUG
    var pictureMarkersForTesting: Set<String> { Set(pictures.keys) }
    #endif
}

/// Loads a slot's offer picture through the SDK image cache; nil keeps the placeholder.
enum SDUIAnimationPictures {
    /// Every slot's picture bytes by asset id, loaded together. A slot with no offer, no picture or a failed load is absent.
    static func load(_ slots: [String: SDUIAnimationImageSlot], offers: [Offer],
                     fetch: @escaping @Sendable (URL) async -> Data? = defaultFetch) async -> [String: Data] {
        let urls = slots.compactMapValues { $0.url(in: offers) }
        return await withTaskGroup(of: (String, Data?).self) { group in
            for (id, url) in urls {
                group.addTask { (id, await fetch(url)) }
            }
            var out: [String: Data] = [:]
            for await (id, bytes) in group { if let bytes { out[id] = bytes } }
            return out
        }
    }

    /// The image cache's own load of the offer's URL, as an `asyncImage` binding it would fetch.
    static let defaultFetch: @Sendable (URL) async -> Data? = { url in
        guard let (data, _) = try? await SDUIImageLoader.load(url), SDUIImageLoader.looksLikeImage(data) else { return nil }
        return data
    }
}

private struct SDUIAnimationOffersKey: EnvironmentKey {
    static let defaultValue: [Offer] = []
}

extension EnvironmentValues {
    /// The sheet's offers, for an animation's offer pictures.
    var sduiAnimationOffers: [Offer] {
        get { self[SDUIAnimationOffersKey.self] }
        set { self[SDUIAnimationOffersKey.self] = newValue }
    }
}

// MARK: - Rendering

/// Plays an element's animation over the element's frame. The element keeps its layout and draws until the
/// animation is ready, under reduce motion, without Lottie, and after any failure; hidden, it stays accessible.
struct SDUIElementAnimationModifier: ViewModifier {
    let spec: SDUIElementAnimationSpec?
    var persistKey: String? = nil
    @Environment(\.sduiMotionPaused) private var sheetPaused
    @Environment(\.sduiLeavingFlow) private var leaving
    @Environment(\.sduiFlowActions) private var sink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sduiAnimationOffers) private var offers
    @Environment(\.visibilityProbesPaused) private var probesPaused
    @State private var player: SDUILottiePlayer?
    /// What `player` was built for: the file and each slot's picture, so a changed offer list rebuilds it.
    @State private var playerKey: String?
    @State private var inView: Bool?
    /// Sheet seconds since the element appeared, for an `onComplete` that cannot wait for the file.
    @State private var seen = SDUIMotionClock()
    @State private var firedComplete = false
    /// The file started playing before the fallback ran out, so `onComplete` waits for its end.
    @State private var playStarted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let spec, let url = spec.animation.resolvedURL {
            let animation = spec.animation
            let showing = player != nil && !reduceMotion
            content
                // Hidden content records no impression; it reports again if the animation goes and it draws.
                .environment(\.visibilityProbesPaused, probesPaused || showing)
                .opacity(showing ? 0 : 1)
                .overlay {
                    if let player, !reduceMotion {
                        SDUILottieHost(
                            player: player,
                            contentMode: spec.contentMode,
                            loop: animation.loop ?? true,
                            playing: Self.shouldPlay(autoplay: animation.autoplay, paused: sheetPaused || inView != true)
                        )
                        .accessibilityHidden(true)
                    }
                }
                .modifier(SDUIInViewProbe(inView: $inView))
                .task(id: Self.taskKey(url, images: animation.images, offers: offers, reduceMotion: reduceMotion)) {
                    let key = Self.taskKey(url, images: animation.images, offers: offers, reduceMotion: reduceMotion)
                    // The same element in the other branch of a `setState` keeps its player and its frame.
                    if player == nil, let persistKey, sink?.context?.stateTransition?.keptKeys.contains(persistKey) == true,
                       let kept = sink?.registry?.players[persistKey], kept.key == key {
                        player = kept.player
                        playerKey = key
                        return
                    }
                    guard !reduceMotion, player == nil || playerKey != key else { return }
                    // The current player keeps drawing until the new one is ready; a new file replaces it at once.
                    if playerKey.map({ !$0.hasPrefix("\(false)|\(url.absoluteString)|") }) ?? true { player = nil }
                    playerKey = key
                    let made = await Self.makePlayer(url: url, loop: animation.loop ?? true, images: animation.images, offers: offers,
                                                     loader: Self.loader, fetch: Self.fetch)
                    if !Task.isCancelled, playerKey == key {
                        player = made
                        if let persistKey, let made { sink?.registry?.players[persistKey] = (key, made) }
                    }
                }
                .onAppear { if !sheetPaused { seen.resume(at: Date()) } }
                .onChange(of: sheetPaused) { paused in if paused { seen.pause(at: Date()) } else { seen.resume(at: Date()) } }
                .task(id: SDUICompletionWait(sheetPaused: sheetPaused, hasPlayer: player != nil)) {
                    await waitForCompletion(animation)
                }
        } else {
            content
        }
    }

    static func shouldPlay(autoplay: Bool?, paused: Bool) -> Bool { autoplay != false && !paused }

    /// Fires `onComplete` at the file's end when it started playing within `fallbackSeconds` of the element
    /// appearing, else once those sheet seconds pass (the file still draws). Never after the element left.
    private func waitForCompletion(_ animation: SDUIElementAnimation) async {
        guard let action = animation.onComplete, let fallback = animation.fallbackSeconds, !firedComplete, !sheetPaused else { return }
        while !Task.isCancelled, !firedComplete {
            let view = reduceMotion ? nil : player?.activeView
            let shownFor = seen.elapsed(at: Date())
            // A kept play-once file that had already ended does not play again, so it waits for the fallback.
            if !playStarted, shownFor < fallback, let view, SDUILottieBridge.isPlaying(view) { playStarted = true }
            if Self.completionDue(started: playStarted, progress: view.map(SDUILottieBridge.progress), seen: shownFor, fallback: fallback) {
                guard leaving == nil else { return }
                firedComplete = true
                sink?.fire(action)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Due at the end of a file that started playing first (or once its view is gone), else after `fallback`.
    static func completionDue(started: Bool, progress: Double?, seen: TimeInterval, fallback: TimeInterval) -> Bool {
        if started { return (progress ?? 1) >= 0.999 }
        return seen >= fallback
    }

    /// Test seams: the loader and the picture fetch a mounted element uses.
    @MainActor static var loader = SDUILottieLoader.shared
    @MainActor static var fetch: @Sendable (URL) async -> Data? = SDUIAnimationPictures.defaultFetch

    /// The file and every slot's picture URL against the current offers, as a forEach with that offset reads them.
    static func taskKey(_ url: URL, images: [String: SDUIAnimationImageSlot]?, offers: [Offer], reduceMotion: Bool) -> String {
        let slots = (images ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.url(in: offers)?.absoluteString ?? "")" }
        return "\(reduceMotion)|\(url.absoluteString)|" + slots.joined(separator: ",")
    }

    /// Nil draws the still: no Lottie in the host (no download at all), or a file or view that failed.
    @MainActor
    static func makePlayer(
        url: URL, loop: Bool, images: [String: SDUIAnimationImageSlot]? = nil, offers: [Offer] = [],
        loader: SDUILottieLoader = .shared, fetch: @escaping @Sendable (URL) async -> Data? = SDUIAnimationPictures.defaultFetch
    ) async -> SDUILottiePlayer? {
        guard SDUILottieBridge.isAvailable else {
            logMissingLottieOnce()
            return nil
        }
        guard let loaded = await loader.load(url) else { return nil }
        // The element draws until every slot has its picture or has failed; a failed slot keeps its placeholder.
        var pictures: [String: Data] = [:]
        if let images, !images.isEmpty { pictures = await SDUIAnimationPictures.load(images, offers: offers, fetch: fetch) }
        // Parsing, decoding and drawing the pictures stay off the main actor; only the view is built on it.
        guard let prepared = await Task.detached(priority: .userInitiated, operation: { SDUILottieImageProvider.prepare(loaded, pictures: pictures) }).value else {
            SDUILottieWarnings.warn(url.absoluteString, "could not be prepared for Lottie")
            return nil
        }
        let player = SDUILottiePlayer(data: prepared.data, loop: loop, images: prepared.provider)
        guard player.view != nil else {
            SDUILottieWarnings.warn(url.absoluteString, "did not load in Lottie")
            return nil
        }
        return player
    }

    @MainActor private static var loggedMissingLottie = false

    @MainActor private static func logMissingLottieOnce() {
        guard !loggedMissingLottie else { return }
        loggedMissingLottie = true
        Logger.info(.presentation, "[SDUI] lottie-ios is not linked in this app; sheet animations draw their element")
    }
}

/// One Lottie view per element, built once: SwiftUI may build a host more than once, and a view sits in one
/// container only, so it goes to the newest host container in a window (a duplicate never in one gets nothing).
@MainActor
final class SDUILottiePlayer {
    let data: Data
    let loop: Bool
    let images: SDUILottieImageProvider?
    /// The view every host of this element shows, nil when Lottie did not load the file.
    let view: UIView?
    /// The container showing `view`.
    private(set) weak var owner: SDUILottieContainer?
    private let containers = NSHashTable<SDUILottieContainer>.weakObjects()
    /// The view while a host shows it, for the progress a completion reads.
    var activeView: UIView? { owner == nil ? nil : view }
    /// The file's length in seconds.
    var duration: Double { view.map { ($0.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0 } ?? 0 }

    init(data: Data, loop: Bool, images: SDUILottieImageProvider?) {
        self.data = data
        self.loop = loop
        self.images = images
        view = SDUILottieBridge.makeView(data: data, loop: loop, images: images)
    }

    /// A new host takes the view only from a host that is not in a window; entering one takes it in any case.
    func attach(_ container: SDUILottieContainer) {
        containers.add(container)
        if owner?.window == nil { give(to: container) }
    }

    func windowChanged(_ container: SDUILottieContainer) {
        if container.window != nil {
            if owner !== container { give(to: container) }
        } else if owner === container, let other = containers.allObjects.last(where: { $0 !== container && $0.window != nil }) {
            give(to: other)
        }
    }

    /// A host that goes pauses the view, unless another host in a window takes it over.
    func detach(_ container: SDUILottieContainer) {
        containers.remove(container)
        guard owner === container, let view else { return }
        owner = nil
        SDUILottieBridge.pause(view)
        if let other = containers.allObjects.last(where: { $0.window != nil }) { give(to: other) }
    }

    private func give(to container: SDUILottieContainer) {
        guard let view else { return }
        owner = container
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)
        container.applySettings()
    }
}

/// A host's container. It tells the player when it enters or leaves a window, and keeps its host's settings
/// so it applies them to the view when it takes the view over.
final class SDUILottieContainer: UIView {
    let player: SDUILottiePlayer
    var contentModeFill = false
    var loop: Bool?
    var playing = false

    init(player: SDUILottiePlayer) {
        self.player = player
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        player.windowChanged(self)
    }

    /// The view when this container shows it.
    var ownedView: UIView? { player.owner === self ? player.view : nil }

    func applySettings() {
        guard let view = ownedView else { return }
        view.contentMode = contentModeFill ? .scaleAspectFill : .scaleAspectFit
        clipsToBounds = contentModeFill
        if let loop { SDUILottieHost.apply(loop: loop, to: view) }
        SDUILottieHost.apply(playing: playing, to: view)
    }
}

/// What restarts the wait for an animation's `onComplete`: the sheet pausing or the player arriving.
struct SDUICompletionWait: Equatable {
    let sheetPaused: Bool
    let hasPlayer: Bool
}

/// Hosts the player's view in a plain container, so SwiftUI sizes it to the element, not to Lottie's own size.
struct SDUILottieHost: UIViewRepresentable {
    let player: SDUILottiePlayer
    let contentMode: ContentMode
    /// This element's own loop: a kept player plays on under the arriving element's.
    var loop: Bool? = nil
    let playing: Bool

    func makeUIView(context: Context) -> SDUILottieContainer {
        let container = SDUILottieContainer(player: player)
        player.attach(container)
        return container
    }

    func updateUIView(_ container: SDUILottieContainer, context: Context) {
        container.contentModeFill = contentMode == .fill
        container.loop = loop
        container.playing = playing
        container.applySettings()
    }

    /// A looping file set to play once finishes its cycle and stops; a play-once file set to loop plays on.
    @MainActor
    static func apply(loop: Bool, to view: UIView) {
        let count = loop ? -1.0 : 1.0
        if (view.value(forKey: "loopAnimationCount") as? NSNumber)?.doubleValue != count { view.setValue(count, forKey: "loopAnimationCount") }
    }

    /// Play or hold. A play-once animation that reached its end stays on its last frame.
    @MainActor
    static func apply(playing: Bool, to view: UIView) {
        let isPlaying = SDUILottieBridge.isPlaying(view)
        if playing, !isPlaying {
            let playsOnce = ((view.value(forKey: "loopAnimationCount") as? NSNumber)?.doubleValue ?? 0) != -1
            if playsOnce, SDUILottieBridge.progress(view) >= 1 { return }
            SDUILottieBridge.play(view)
        } else if !playing, isPlaying {
            SDUILottieBridge.pause(view)
        }
    }


    static func dismantleUIView(_ container: SDUILottieContainer, coordinator: ()) {
        container.player.detach(container)
    }
}
