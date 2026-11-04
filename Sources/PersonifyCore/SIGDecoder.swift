import Foundation

public struct SIGDecodedValue: Equatable, Sendable {
    public var summary: String
    public var quantity: String

    public init(summary: String, quantity: String) {
        self.summary = summary
        self.quantity = quantity
    }
}

/// Decoders for Bluetooth SIG characteristic layouts.
///
/// Temperature and Humidity follow the GATT Specification Supplement
/// (Temperature §3.235, sint16, decimal exponent −2, Celsius, sentinel 0x8000;
/// Humidity §3.134, uint16, decimal exponent −2, percent, sentinel 0xFFFF).
/// Illuminance follows §3.137 (uint24, decimal exponent −2, lux, sentinel 0xFFFFFF).
/// Battery Level is the uint8 percentage from the Battery Service.
/// String characteristics are UTF-8. These layouts are SIG layouts. They are
/// applied only when the UUID is the SIG assigned number.
public enum SIGDecoder {
    public static func decode(uuid: String, data: Data) -> SIGDecodedValue? {
        switch bluetoothAlias(uuid) {
        case "2A6E":
            return temperature(data)
        case "2A6F":
            return humidity(data)
        case "2AFB":
            return illuminance(data)
        case "2A19":
            return battery(data)
        case "2A00", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29", "2901":
            return text(data, quantity: "text")
        default:
            return nil
        }
    }

    private static func temperature(_ data: Data) -> SIGDecodedValue? {
        guard data.count == 2 else { return nil }
        let raw = UInt16(data[0]) | (UInt16(data[1]) << 8)
        if raw == 0x8000 {
            return SIGDecodedValue(summary: "value is not known", quantity: "temperature")
        }
        let celsius = Double(Int16(bitPattern: raw)) / 100
        var summary = String(format: "%.2f °C", celsius)
        if celsius < -273.15 || celsius > 327.67 {
            summary += " (outside the GATT allowed range)"
        }
        return SIGDecodedValue(summary: summary, quantity: "temperature")
    }

    private static func humidity(_ data: Data) -> SIGDecodedValue? {
        guard data.count == 2 else { return nil }
        let raw = UInt16(data[0]) | (UInt16(data[1]) << 8)
        if raw == 0xFFFF {
            return SIGDecodedValue(summary: "value is not known", quantity: "humidity")
        }
        let percent = Double(raw) / 100
        var summary = String(format: "%.2f %%", percent)
        if percent > 100 {
            summary += " (outside the GATT allowed range)"
        }
        return SIGDecodedValue(summary: summary, quantity: "humidity")
    }

    private static func illuminance(_ data: Data) -> SIGDecodedValue? {
        guard data.count == 3 else { return nil }
        let raw = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16)
        if raw == 0xFFFFFF {
            return SIGDecodedValue(summary: "value is not known", quantity: "illuminance")
        }
        let lux = Double(raw) / 100
        return SIGDecodedValue(summary: String(format: "%.2f lx", lux), quantity: "illuminance")
    }

    private static func battery(_ data: Data) -> SIGDecodedValue? {
        guard data.count == 1 else { return nil }
        let value = Int(data[0])
        if (0...100).contains(value) {
            return SIGDecodedValue(summary: "\(value)%", quantity: "battery")
        }
        return SIGDecodedValue(summary: "\(value) (outside 0–100)", quantity: "battery")
    }

    private static func text(_ data: Data, quantity: String) -> SIGDecodedValue? {
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return nil }
        return SIGDecodedValue(summary: string, quantity: quantity)
    }
}
