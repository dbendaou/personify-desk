import Foundation

/// Fold a UUID string to the 16-bit Bluetooth alias when it sits on the Bluetooth base UUID.
public func bluetoothAlias(_ uuid: String) -> String {
    let hex = uuid.replacingOccurrences(of: "-", with: "").uppercased()
    let suffix = "00001000800000805F9B34FB"
    if hex.count == 32, hex.hasPrefix("0000"), hex.dropFirst(8) == Substring(suffix) {
        return String(hex.dropFirst(4).prefix(4))
    }
    if hex.count == 4 {
        return hex
    }
    return hex
}

func formatUUID16(_ littleEndian: Data) -> String? {
    guard littleEndian.count == 2 else { return nil }
    let value = UInt16(littleEndian[0]) | (UInt16(littleEndian[1]) << 8)
    return String(format: "%04X", value)
}

func formatUUID32(_ littleEndian: Data) -> String? {
    guard littleEndian.count == 4 else { return nil }
    let value = UInt32(littleEndian[0])
        | (UInt32(littleEndian[1]) << 8)
        | (UInt32(littleEndian[2]) << 16)
        | (UInt32(littleEndian[3]) << 24)
    return String(format: "%08X", value)
}

func formatUUID128(_ littleEndian: Data) -> String? {
    guard littleEndian.count == 16 else { return nil }
    let bigEndian = Data(littleEndian.reversed())
    let hex = Hex.encode(bigEndian).uppercased()
    let part1 = hex.prefix(8)
    let part2 = hex.dropFirst(8).prefix(4)
    let part3 = hex.dropFirst(12).prefix(4)
    let part4 = hex.dropFirst(16).prefix(4)
    let part5 = hex.dropFirst(20).prefix(12)
    return "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"
}
