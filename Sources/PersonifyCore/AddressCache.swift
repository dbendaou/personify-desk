import Foundation

public enum BluetoothAddressCache {
    /// Search a property-list value for a peripheral UUID key and return a Bluetooth address.
    ///
    /// macOS keeps a CoreBluetooth cache in a local plist. The key layout is not a public API,
    /// so this walks the tree: a dictionary key that matches the peripheral UUID, then a
    /// colon- or hyphen-separated address in that subtree.
    public static func address(forPeripheralUUID uuid: String, in node: Any) -> String? {
        let target = normalizeUUID(uuid)
        guard !target.isEmpty else { return nil }
        return search(node, target: target)
    }

    public static func normalizeUUID(_ uuid: String) -> String {
        uuid.unicodeScalars.filter { Character($0).isHexDigit }.map { Character($0).uppercased() }.joined()
    }

    public static func normalizeAddress(_ raw: String) -> String? {
        let parts = raw.split { $0 == ":" || $0 == "-" }.map(String.init)
        guard parts.count == 6 else { return nil }
        guard parts.allSatisfy({ part in
            part.count == 2 && part.unicodeScalars.allSatisfy { Character($0).isHexDigit }
        }) else { return nil }
        return parts.joined(separator: "-").uppercased()
    }

    private static func search(_ node: Any, target: String) -> String? {
        if let dict = node as? [String: Any] {
            for (key, value) in dict where normalizeUUID(key) == target {
                if let address = firstAddress(in: value) {
                    return address
                }
            }
            for value in dict.values {
                if let found = search(value, target: target) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = search(value, target: target) {
                    return found
                }
            }
        }
        return nil
    }

    private static func firstAddress(in node: Any) -> String? {
        if let string = node as? String, let address = normalizeAddress(string) {
            return address
        }
        if let dict = node as? [String: Any] {
            for value in dict.values {
                if let address = firstAddress(in: value) {
                    return address
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let address = firstAddress(in: value) {
                    return address
                }
            }
        }
        return nil
    }
}
