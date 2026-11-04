import Foundation

/// Numeric fields confirmed on 00020001, 00020002, and 00020003.
public enum LiveRoomReading {
    public static func setpointOffset(_ data: Data) -> Double? {
        finite(data, at: 14)
    }

    public static func roomTemperature(_ data: Data) -> Double? {
        finite(data, at: 27)
    }

    /// Fan at absolute bytes 18–21. `1` Auto, `2` Off, `3`/`4`/`5` speeds 1/2/3.
    public static func fanSetting(_ data: Data) -> FanSetting? {
        guard let value = finite(data, at: 18) else { return nil }
        return FanSetting.from(wire: Float(value))
    }

    /// Prefers the float at absolute bytes 8–11, then the first finite level.
    public static func lightLevel(_ data: Data) -> Double? {
        if let primary = finite(data, at: 8) { return primary }
        var offset = 0
        while offset + 4 <= data.count {
            if let value = finite(data, at: offset) { return value }
            offset += 4
        }
        return nil
    }

    /// Closed percent for each 16-byte record. Nil means float 0 was NaN, so that group does not exist.
    public static func blindClosed(_ data: Data) -> [Double?] {
        let count = max(data.count / 16, 0)
        return (0..<count).map { record in
            finite(data, at: record * 16)
        }
    }

    /// 1-based group indexes whose record is present. `00 00 c0 7f` (NaN) is absent. Only groups 1...8 can be written.
    public static func blindGroups(_ data: Data) -> [Int] {
        blindClosed(data).enumerated().compactMap { index, value in
            let number = index + 1
            guard value != nil, (1...8).contains(number) else { return nil }
            return number
        }
    }

    private static func finite(_ data: Data, at offset: Int) -> Double? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bits = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        let value = Float(bitPattern: bits)
        if value.isNaN || value.isInfinite { return nil }
        return Double(value)
    }
}
