// Animated GIF and WebP for `asyncImage`, sniffed from the bytes: frames and their delays decoded
// with ImageIO, drawn on a timeline, and stilled to the first frame under reduce motion or a pause.

import ImageIO
import SwiftUI
import UIKit

/// The decoded frames of an animated image and how long each shows.
struct SDUIAnimatedFrames {
    let frames: [UIImage]
    let delays: [Double]
    var duration: Double { delays.reduce(0, +) }
    /// What the decoded frames hold in memory, the cache's cost.
    var decodedBytes: Int { frames.reduce(0) { $0 + Int($1.size.width * $1.scale * $1.size.height * $1.scale) * 4 } }

    /// The frame showing `elapsed` seconds in, looping.
    func frame(at elapsed: Double) -> UIImage {
        guard frames.count > 1, duration > 0 else { return frames[0] }
        var t = elapsed.truncatingRemainder(dividingBy: duration)
        for (index, delay) in delays.enumerated() {
            if t < delay { return frames[index] }
            t -= delay
        }
        return frames[frames.count - 1]
    }
}

enum SDUIAnimatedImageDecoder {
    /// Frames decode with their longer side at most this, as Android samples; the budget counts these bytes.
    static let maxPixelSide = 1024
    /// Past the budget the image draws its first frame only, so one large file cannot exhaust memory.
    static let maxDecodedBytes = 48 * 1024 * 1024
    /// Bounds decode work, not memory: tiny frames fit the budget in the thousands.
    static let maxFrames = 300
    /// Browsers raise a delay under 20 ms to 100 ms; matching them keeps a GIF at the speed it plays on web.
    static let minimumDelay = 0.02
    static let defaultDelay = 0.1

    /// A GIF or a WebP by its magic bytes; only these may animate.
    static func isAnimatableFormat(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: Array("GIF8".utf8)) { return true }
        return b.count >= 12 && b.starts(with: Array("RIFF".utf8)) && Array(b[8..<12]) == Array("WEBP".utf8)
    }

    /// Whether `frames` frames of `width` x `height` RGBA fit the decode budget; an overflow does not fit.
    static func fitsBudget(width: Int, height: Int, frames: Int) -> Bool {
        guard width > 0, height > 0, frames > 0 else { return false }
        var total = width
        for factor in [height, 4, frames] {
            let (product, overflow) = total.multipliedReportingOverflow(by: factor)
            if overflow { return false }
            total = product
        }
        return total <= maxDecodedBytes
    }

    /// The size a `width` x `height` frame decodes at: its longer side capped at `maxPixelSide`, rounded up.
    static func downsampledSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longer = max(width, height)
        guard longer > maxPixelSide else { return (width, height) }
        let scale = Double(maxPixelSide) / Double(longer)
        return (Int((Double(width) * scale).rounded(.up)), Int((Double(height) * scale).rounded(.up)))
    }

    /// Thumbnail options that decode the pixels now, at most `maxPixelSide` on the longer side.
    static var frameOptions: CFDictionary { [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
    ] as CFDictionary }

    /// The still drawn before (or instead of) the frames: a GIF or WebP's first frame at most `maxPixelSide`, anything else as `UIImage(data:)`.
    static func stillImage(_ data: Data) -> UIImage? {
        guard isAnimatableFormat(data) else { return UIImage(data: data) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let first = CGImageSourceCreateThumbnailAtIndex(source, 0, frameOptions) else { return nil }
        return UIImage(cgImage: first)
    }

    /// The frames of an animated GIF or WebP, decoded to pixels by the caller's thread, or nil for a
    /// still image or one over the caps.
    static func decode(_ data: Data) -> SDUIAnimatedFrames? {
        guard isAnimatableFormat(data), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= maxFrames else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let drawn = downsampledSize(width: width, height: height)
        guard fitsBudget(width: drawn.width, height: drawn.height, frames: count) else { return nil }
        var frames: [UIImage] = []
        var delays: [Double] = []
        let options = frameOptions
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { return nil }
            frames.append(UIImage(cgImage: image))
            delays.append(delay(source, index))
        }
        return SDUIAnimatedFrames(frames: frames, delays: delays)
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let pairs: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (dictionary, unclamped, clamped) in pairs {
            guard let values = properties[dictionary] as? [CFString: Any] else { continue }
            let seconds = (values[unclamped] as? Double) ?? (values[clamped] as? Double) ?? defaultDelay
            return seconds < minimumDelay ? defaultDelay : seconds
        }
        return defaultDelay
    }
}

/// Decoded frames shared per URL, so every row drawing one GIF decodes it once and holds it once.
@MainActor
enum SDUIAnimatedImageCache {
    private final class Entry { let frames: SDUIAnimatedFrames; init(_ frames: SDUIAnimatedFrames) { self.frames = frames } }

    /// Decoded bytes across every animated image, evicted least recently used past this.
    static let totalCostLimit = 64 * 1024 * 1024
    private static let cache: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = totalCostLimit
        return cache
    }()
    private static var inFlight: [URL: Task<SDUIAnimatedFrames?, Never>] = [:]
    #if DEBUG
    static var decodeCount = 0
    #endif

    /// The frames for `url`: cached, joined to a decode in flight, or decoded to pixels in a detached task.
    static func frames(for url: URL, data: Data) async -> SDUIAnimatedFrames? {
        if let entry = cache.object(forKey: url as NSURL) { return entry.frames }
        if let task = inFlight[url] { return await task.value }
        #if DEBUG
        decodeCount += 1
        #endif
        let task = Task.detached(priority: .userInitiated) { SDUIAnimatedImageDecoder.decode(data) }
        inFlight[url] = task
        let frames = await task.value
        inFlight[url] = nil
        if let frames { cache.setObject(Entry(frames), forKey: url as NSURL, cost: frames.decodedBytes) }
        return frames
    }

    #if DEBUG
    static func resetForTesting() {
        cache.removeAllObjects()
        inFlight = [:]
        decodeCount = 0
    }
    #endif
}

/// Draws animated frames on a timeline. Reduce motion shows the first frame; a pause holds the frame it reached.
struct SDUIAnimatedImageView: View {
    let animation: SDUIAnimatedFrames
    let contentMode: ContentMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sduiMotionPaused) private var paused
    @State private var clock = SDUIMotionClock()

    /// The frame to draw: the first under reduce motion, else the one `elapsed` seconds in.
    static func shownFrame(_ animation: SDUIAnimatedFrames, reduceMotion: Bool, elapsed: Double) -> UIImage {
        reduceMotion ? animation.frames[0] : animation.frame(at: elapsed)
    }

    var body: some View {
        if reduceMotion {
            still(Self.shownFrame(animation, reduceMotion: true, elapsed: 0))
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
                let elapsed = clock.phase(at: timeline.date, duration: animation.duration) * animation.duration
                still(Self.shownFrame(animation, reduceMotion: false, elapsed: elapsed))
            }
            .onAppear { if !paused { clock.resume(at: Date()) } }
            .onChange(of: paused) { isPaused in
                if isPaused { clock.pause(at: Date()) } else { clock.resume(at: Date()) }
            }
        }
    }

    private func still(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
    }
}
