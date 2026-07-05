import Foundation

/// Deterministic JSON encoding/decoding for the interchange format. Sorted
/// keys + ISO-8601 dates + pretty printing, so files diff cleanly in git —
/// a hard requirement of the platform design (docs/PLATFORM.md).
public enum InterchangeCodec {
    public enum CodecError: Error, Equatable {
        /// The document declares a schema version newer than this reader.
        case unsupportedSchemaVersion(Int)
        case notAnInterchangeDocument
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    /// Decodes after checking the document's declared schema version, so a
    /// v1 reader fails loudly (not with a field-level decoding error) on a
    /// future-versioned file.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        struct VersionProbe: Decodable {
            let schemaVersion: Int?
        }
        guard let probe = try? decoder().decode(VersionProbe.self, from: data) else {
            throw CodecError.notAnInterchangeDocument
        }
        if let version = probe.schemaVersion, version > Interchange.schemaVersion {
            throw CodecError.unsupportedSchemaVersion(version)
        }
        return try decoder().decode(type, from: data)
    }
}

/// File-name slugs for the per-entity repo layout:
/// "Band Pulses" → "band-pulses", "Y's and T's" → "ys-and-ts".
public enum Slug {
    public static func make(_ name: String) -> String {
        let apostrophes = CharacterSet(charactersIn: "'’")
        let stripped = name.unicodeScalars.filter { !apostrophes.contains($0) }
        var result = ""
        var lastWasDash = true // suppress leading dashes
        for scalar in stripped {
            if CharacterSet.alphanumerics.contains(scalar) {
                result += String(scalar).lowercased()
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        return result
    }
}
