import Foundation

/// Length-prefixed JSON frames: 4-byte big-endian size, then UTF-8 JSON.
public enum ControlCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(value)
        var header = UInt32(body.count).bigEndian
        var frame = Data(bytes: &header, count: 4)
        frame.append(body)
        return frame
    }

    public static func decode<Value: Decodable>(_ frame: Data, as type: Value.Type) throws -> Value
    {
        guard frame.count >= 4 else {
            throw ControlCodecError.truncated
        }

        let size = Int(
            UInt32(bigEndian: frame.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) })
        )
        let body = frame.dropFirst(4)

        guard body.count == size else {
            throw ControlCodecError.lengthMismatch(expected: size, actual: body.count)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(body))
    }

    public static func decodeBody<Value: Decodable>(_ body: Data, as type: Value.Type) throws
        -> Value
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: body)
    }
}

public enum ControlCodecError: Error, LocalizedError {
    case truncated
    case lengthMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .truncated:
            "frame too short"
        case .lengthMismatch(let expected, let actual):
            "frame length \(actual) != header \(expected)"
        }
    }
}
