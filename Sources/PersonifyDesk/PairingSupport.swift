import Foundation
import PersonifyCore

enum BluetoothAddressLookup {
    static func address(for peripheralID: UUID) -> String? {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            else { continue }
            let normalized = cocoaToAny(plist)
            if let address = BluetoothAddressCache.address(forPeripheralUUID: peripheralID.uuidString, in: normalized) {
                return address
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var urls = [
            URL(fileURLWithPath: "/Library/Preferences/com.apple.Bluetooth.plist"),
            home.appendingPathComponent("Library/Preferences/com.apple.Bluetooth.plist"),
        ]
        let byHost = home.appendingPathComponent("Library/Preferences/ByHost")
        if let files = try? FileManager.default.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil) {
            urls.append(contentsOf: files.filter { $0.lastPathComponent.contains("com.apple.Bluetooth") })
        }
        return urls
    }

    private static func cocoaToAny(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string
        case let dictionary as [String: Any]:
            return dictionary.mapValues(cocoaToAny)
        case let array as [Any]:
            return array.map(cocoaToAny)
        case let dictionary as NSDictionary:
            var output: [String: Any] = [:]
            for (key, item) in dictionary {
                if let key = key as? String {
                    output[key] = cocoaToAny(item)
                }
            }
            return output
        case let array as NSArray:
            return array.map { cocoaToAny($0) }
        case let data as Data:
            return data
        case let number as NSNumber:
            return number.stringValue
        default:
            return String(describing: value)
        }
    }
}
