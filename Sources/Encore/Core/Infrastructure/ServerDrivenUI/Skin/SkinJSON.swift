// An ordered, by-reference JSON tree for the sheet skin rewrite. Objects keep their key order
// (warnings follow it, as on web) and are shared by reference, so the port of skin.ts reads alike.

import Foundation

/// One JSON value. Objects are `SkinObject` references; everything else is a value.
indirect enum SkinJSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SkinJSON])
    case object(SkinObject)

    var object: SkinObject? { if case .object(let o) = self { return o } else { return nil } }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var number: Double? { if case .number(let n) = self { return n } else { return nil } }

    /// A copy that shares no object with this one (`JSON.parse(JSON.stringify(x))`).
    func deepCopy() -> SkinJSON {
        switch self {
        case .array(let items): return .array(items.map { $0.deepCopy() })
        case .object(let object): return .object(object.deepCopy())
        default: return self
        }
    }

    /// Equality by value: key order is ignored and `1.0` equals `1`.
    func sameValue(as other: SkinJSON) -> Bool {
        switch (self, other) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a.count == b.count && zip(a, b).allSatisfy { $0.sameValue(as: $1) }
        case (.object(let a), .object(let b)):
            return Set(a.keys) == Set(b.keys) && a.entries.allSatisfy { entry in b[entry.key].map { entry.value.sameValue(as: $0) } ?? false }
        default: return false
        }
    }
}

/// A JSON object with its key order, mutated in place like a JS object.
final class SkinObject {
    private(set) var keys: [String] = []
    private var storage: [String: SkinJSON] = [:]

    init() {}

    init(_ pairs: [(String, SkinJSON)]) {
        for (key, value) in pairs { self[key] = value }
    }

    /// nil when the key is absent (JS `undefined`); a JSON null is `.null`.
    subscript(key: String) -> SkinJSON? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    var entries: [(key: String, value: SkinJSON)] { keys.compactMap { key in storage[key].map { (key, $0) } } }
    var count: Int { keys.count }

    func deepCopy() -> SkinObject {
        SkinObject(entries.map { ($0.key, $0.value.deepCopy()) })
    }
}

// MARK: - Parse and serialise

extension SkinJSON {
    struct ParseError: Error {}

    /// Parses JSON text, keeping each object's key order.
    static func parse(_ data: Data) throws -> SkinJSON {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipSpace()
        let value = try parser.value()
        parser.skipSpace()
        guard parser.index == parser.bytes.count else { throw ParseError() }
        return value
    }

    /// The tree from a decoded `JSONValue`, with object keys sorted so the order is stable.
    init(_ value: JSONValue) {
        switch value {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .number(let n): self = .number(n)
        case .string(let s): self = .string(s)
        case .array(let items): self = .array(items.map(SkinJSON.init))
        case .object(let object): self = .object(SkinObject(object.sorted { $0.key < $1.key }.map { ($0.key, SkinJSON($0.value)) }))
        }
    }

    func serialized() -> Data {
        var out = ""
        write(to: &out)
        return Data(out.utf8)
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { out += String(Int64(n)) } else { out += n.isFinite ? "\(n)" : "null" }
        case .string(let s): Self.writeString(s, to: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let object):
            out += "{"
            for (index, entry) in object.entries.enumerated() {
                if index > 0 { out += "," }
                Self.writeString(entry.key, to: &out)
                out += ":"
                entry.value.write(to: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        out += "\""
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
        }

        mutating func value() throws -> SkinJSON {
            guard index < bytes.count else { throw ParseError() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try objectValue()
            case UInt8(ascii: "["): return try arrayValue()
            case UInt8(ascii: "\""): return .string(try stringValue())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try numberValue()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard index + w.count <= bytes.count, Array(bytes[index..<index + w.count]) == w else { throw ParseError() }
            index += w.count
        }

        mutating func objectValue() throws -> SkinJSON {
            index += 1
            let object = SkinObject()
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError() }
                let key = try stringValue()
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError() }
                index += 1
                skipSpace()
                object[key] = try value()
                skipSpace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
                throw ParseError()
            }
        }

        mutating func arrayValue() throws -> SkinJSON {
            index += 1
            var items: [SkinJSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError()
            }
        }

        mutating func stringValue() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var run: [UInt8] = []
            func flush() {
                if !run.isEmpty { scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars); run.removeAll() }
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") { index += 1; flush(); return String(scalars) }
                if byte == UInt8(ascii: "\\") {
                    flush()
                    index += 1
                    guard index < bytes.count else { throw ParseError() }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        // Only a high surrogate followed by a low one is a character; a lone half of either is bad JSON,
                        // and a lone low one fails the scalar check below.
                        if (0xD800..<0xDC00).contains(code) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw ParseError()
                            }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00..<0xE000).contains(low) else { throw ParseError() }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw ParseError() }
                        scalars.append(scalar)
                    default: throw ParseError()
                    }
                    continue
                }
                // A raw control character is bad JSON, as JSONDecoder reads it: the sheet then draws the served template.
                guard byte >= 0x20 else { throw ParseError() }
                run.append(byte)
                index += 1
            }
            throw ParseError()
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let code = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
                throw ParseError()
            }
            index += 4
            return code
        }

        mutating func numberValue() throws -> SkinJSON {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            guard index > start, let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { throw ParseError() }
            return .number(number)
        }
    }
}
