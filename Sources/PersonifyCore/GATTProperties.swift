import Foundation

/// Characteristic property bits.
///
/// Bits 0...7 are the GATT characteristic properties in Bluetooth Core Specification
/// Volume 3, Part G. Bits 0x100 and 0x200 are the extra flags CoreBluetooth reports
/// in `CBCharacteristicProperties` (`notifyEncryptionRequired` and
/// `indicateEncryptionRequired`).
public enum GATTProperties {
    public static func names(mask: UInt) -> [String] {
        let table: [(UInt, String)] = [
            (0x01, "broadcast"),
            (0x02, "read"),
            (0x04, "write-without-response"),
            (0x08, "write"),
            (0x10, "notify"),
            (0x20, "indicate"),
            (0x40, "authenticated-signed-writes"),
            (0x80, "extended-properties"),
            (0x100, "notify-encryption-required"),
            (0x200, "indicate-encryption-required"),
        ]
        var names: [String] = []
        for (bit, name) in table where mask & bit != 0 {
            names.append(name)
        }
        let known: UInt = 0x3FF
        let extra = mask & ~known
        if extra != 0 {
            names.append(String(format: "unknown-%04x", extra))
        }
        return names
    }
}
