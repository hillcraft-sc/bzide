import Foundation
import os

// Servers fill optional fields inconsistently: missing, null, a number sent as a
// string, a list sent as a single object. None of that may fail a whole response.
// These helpers turn "wrong shape" into "absent" for optional fields, and drop only
// the broken element from a list.

private let logger = Logger(subsystem: "MusicApp", category: "Decoding")

extension KeyedDecodingContainer {
    /// A string, or a number rendered as a string (some servers send numeric ids).
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    /// An integer, or a string holding one.
    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value) ?? Double(value).map { Int($0) }
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Bool(value.lowercased()) }
        return nil
    }

    /// The element's identifier. Without one an item is unusable, so this throws and
    /// the surrounding `lossyArray` drops just that element.
    func requiredID(_ key: Key) throws -> String {
        guard let id = lenientString(key), !id.isEmpty else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing id"))
        }
        return id
    }

    /// A list where broken elements are skipped instead of failing the whole list.
    /// A missing list is empty, and a lone object is treated as a one-element list.
    func lossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return [] }
        if let wrapped = try? decode([LossyElement<Element>].self, forKey: key) {
            let elements = wrapped.compactMap(\.value)
            if elements.count < wrapped.count {
                logger.notice("Skipped \(wrapped.count - elements.count) undecodable \(String(describing: Element.self), privacy: .public) item(s)")
            }
            return elements
        }
        if let single = try? decode(Element.self, forKey: key) { return [single] }
        logger.notice("Couldn't decode list \(key.stringValue, privacy: .public)")
        return []
    }
}

private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: any Decoder) throws {
        value = try? Element(from: decoder)
    }
}
