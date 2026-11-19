// BlurHash placeholders (CONTRACT 5): a served image's hash draws as a blurred preview until the image loads.
// Decoder follows the reference algorithm (github.com/woltapp/blurhash); no third-party dependency.

import UIKit

internal enum BlurHash {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
    private static let index: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    /// The preview at `size` pixels, or nil for a malformed hash.
    static func image(_ hash: String, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage? {
        let chars = Array(hash)
        guard chars.count >= 6, let sizeFlag = decode83(chars[0...0]) else { return nil }
        let numY = sizeFlag / 9 + 1
        let numX = sizeFlag % 9 + 1
        guard chars.count == 4 + 2 * numX * numY,
              let quantisedMax = decode83(chars[1...1]), let dc = decode83(chars[2..<6]) else { return nil }
        let maxValue = Float(quantisedMax + 1) / 166
        var colours = [decodeDC(dc)]
        for i in 1..<(numX * numY) {
            guard let ac = decode83(chars[(4 + i * 2)..<(6 + i * 2)]) else { return nil }
            colours.append(decodeAC(ac, maxValue: maxValue))
        }

        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    let cosY = cos(Float.pi * Float(y) * Float(j) / Float(height))
                    for i in 0..<numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width)) * cosY
                        let colour = colours[i + j * numX]
                        r += colour.0 * basis
                        g += colour.1 * basis
                        b += colour.2 * basis
                    }
                }
                let offset = (y * width + x) * 4
                pixels[offset] = linearToSRGB(r)
                pixels[offset + 1] = linearToSRGB(g)
                pixels[offset + 2] = linearToSRGB(b)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func decode83<C: Collection>(_ chars: C) -> Int? where C.Element == Character {
        var value = 0
        for char in chars {
            guard let digit = index[char] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        (sRGBToLinear(value >> 16), sRGBToLinear((value >> 8) & 255), sRGBToLinear(value & 255))
    }

    private static func decodeAC(_ value: Int, maxValue: Float) -> (Float, Float, Float) {
        func component(_ q: Int) -> Float { signPow((Float(q) - 9) / 9, 2) * maxValue }
        return (component(value / (19 * 19)), component((value / 19) % 19), component(value % 19))
    }

    private static func signPow(_ value: Float, _ exp: Float) -> Float { copysign(pow(abs(value), exp), value) }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Float) -> UInt8 {
        let v = max(0, min(1, value))
        let s = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, Int(s * 255 + 0.5))))
    }
}

/// Served image URL to its BlurHash, filled from each `/offers/search` response.
internal enum ImageBlurHashes {
    private static let maxEntries = 500
    private static let hashes = Atomic<[String: String]>([:])
    /// NSCache is thread-safe.
    nonisolated(unsafe) private static let images = NSCache<NSString, UIImage>()

    static func record(_ entries: [String: String]) {
        guard !entries.isEmpty else { return }
        hashes.mutate { stored in
            // Bounded: a full table starts over rather than growing with every search.
            if stored.count + entries.count > maxEntries { stored = [:] }
            stored.merge(entries) { _, new in new }
        }
    }

    /// The decoded preview for `url`, or nil when the server sent no hash for it.
    static func placeholder(for url: URL?) -> UIImage? {
        guard let key = url?.absoluteString, let hash = hashes.value[key] else { return nil }
        if let image = images.object(forKey: hash as NSString) { return image }
        guard let image = BlurHash.image(hash) else { return nil }
        images.setObject(image, forKey: hash as NSString)
        return image
    }

    #if DEBUG
    static func resetForTesting() {
        hashes.value = [:]
        images.removeAllObjects()
    }
    #endif
}
