import Foundation

public enum HexError: Error, Equatable, Sendable {
    case oddLength
    case invalidDigit(Character)
}

public enum Hex {
    public static func encode(_ data: Data, spaced: Bool = false) -> String {
        let digits = data.map { String(format: "%02x", $0) }
        return spaced ? digits.joined(separator: " ") : digits.joined()
    }

    public static func decode(_ raw: String) throws -> Data {
        var cleaned = ""
        let scalars = raw.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let character = scalars[index]
            if character == " " || character == "\n" || character == "\r" || character == "\t" || character == "," || character == ":" {
                index = scalars.index(after: index)
                continue
            }
            if character == "0" {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "x" || scalars[next] == "X" {
                    index = scalars.index(after: next)
                    continue
                }
            }
            cleaned.append(Character(character))
            index = scalars.index(after: index)
        }
        guard cleaned.count % 2 == 0 else { throw HexError.oddLength }
        var data = Data()
        data.reserveCapacity(cleaned.count / 2)
        var cursor = cleaned.startIndex
        while cursor < cleaned.endIndex {
            let next = cleaned.index(cursor, offsetBy: 2)
            let pair = cleaned[cursor..<next]
            guard let byte = UInt8(pair, radix: 16) else {
                throw HexError.invalidDigit(pair.first ?? "?")
            }
            data.append(byte)
            cursor = next
        }
        return data
    }
}
