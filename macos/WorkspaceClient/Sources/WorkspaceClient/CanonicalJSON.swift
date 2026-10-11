import Foundation
import CoreFoundation

// Pinned Forge JSON contracts use Unicode scalar key order, never locale/numeric sorting.
enum CanonicalJSON {
    static func data(_ value: Any, ascii: Bool) throws -> Data {
        Data(try encode(value, ascii: ascii).utf8)
    }
    private static func encode(_ value: Any, ascii: Bool) throws -> String {
        if value is NSNull { return "null" }
        if let object = value as? NSDictionary {
            guard let keys = object.allKeys as? [String] else { throw AdvisoryError.invalid }
            let ordered = keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
            let pairs = try ordered.map { try quote($0, ascii: ascii)+":"+encode(object.object(forKey: $0)!, ascii: ascii) }
            return "{"+pairs.joined(separator: ",")+"}"
        }
        if let array = value as? [Any] {
            return "["+(try array.map { try encode($0, ascii: ascii) }).joined(separator: ",")+"]"
        }
        if let text = value as? String { return quote(text, ascii: ascii) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true":"false" }
            guard ["c","s","i","l","q","C","S","I","L","Q"].contains(String(cString:number.objCType)) else {
                throw AdvisoryError.invalid
            }
            return number.stringValue
        }
        throw AdvisoryError.invalid
    }
    private static func quote(_ text: String, ascii: Bool) -> String {
        let escaped = text.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 8: return "\\b"
            case 9: return "\\t"
            case 10: return "\\n"
            case 12: return "\\f"
            case 13: return "\\r"
            case 34: return "\\\""
            case 92: return "\\\\"
            case 0..<32: return String(format: "\\u%04x", scalar.value)
            default:
                let v = scalar.value
                if !ascii || v < 127 { return String(scalar) }
                if v <= 0xffff { return String(format: "\\u%04x", v) }
                return String(format: "\\u%04x\\u%04x",0xd800+((v-0x10000)>>10),0xdc00+((v-0x10000)&0x3ff))
            }
        }.joined()
        return "\""+escaped+"\""
    }
}
