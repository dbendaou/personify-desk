import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum BluetoothMode: Equatable, Sendable {
    case disabled
    case open
    case commissioning
    case privateMode
    case undocumented(Int)

    public init(raw: Int) {
        switch raw {
        case 0: self = .disabled
        case 1: self = .open
        case 2: self = .commissioning
        case 3: self = .privateMode
        default: self = .undocumented(raw)
        }
    }

    public var raw: Int {
        switch self {
        case .disabled: 0
        case .open: 1
        case .commissioning: 2
        case .privateMode: 3
        case .undocumented(let value): value
        }
    }

    public var label: String {
        switch self {
        case .disabled: "Disabled"
        case .open: "Open"
        case .commissioning: "Commissioning"
        case .privateMode: "Private"
        case .undocumented(let value): "bluetoothMode \(value) (not in the published 0...3 list)"
        }
    }
}

public enum RoomModelType: Equatable, Sendable {
    case unitouch
    case unitouchH
    case unitouchCH
    case ecMultiSensorBLE
    case undocumented(Int)

    public init(raw: Int) {
        switch raw {
        case 0: self = .unitouch
        case 2: self = .unitouchH
        case 3: self = .unitouchCH
        case 4: self = .ecMultiSensorBLE
        default: self = .undocumented(raw)
        }
    }

    public var raw: Int {
        switch self {
        case .unitouch: 0
        case .unitouchH: 2
        case .unitouchCH: 3
        case .ecMultiSensorBLE: 4
        case .undocumented(let value): value
        }
    }

    public var label: String {
        switch self {
        case .unitouch: "Allure UNITOUCH"
        case .unitouchH: "Allure UNITOUCH-H"
        case .unitouchCH: "Allure UNITOUCH-CH"
        case .ecMultiSensorBLE: "EC-Multi-Sensor-BLE"
        case .undocumented(let value): "modelType \(value) (not in the published enum)"
        }
    }
}

public struct ControllerGroup: Equatable, Sendable, Codable {
    public var id: Int?
    public var index: Int?
    public var name: String?
    public var displayName: String?
    public var enabled: Bool?

    public init(id: Int? = nil, index: Int? = nil, name: String? = nil, displayName: String? = nil, enabled: Bool? = nil) {
        self.id = id
        self.index = index
        self.name = name
        self.displayName = displayName
        self.enabled = enabled
    }
}

public struct ControllerRoomDevice: Equatable, Sendable {
    public var resourceIndex: Int?
    public var bluetoothMode: BluetoothMode?
    public var modelType: RoomModelType?
    public var name: String?
    public var roomName: String?
    public var subnetID: Int?
    public var beaconNetworkUUID: String?
    /// Present when a controller document included it. Kept off the explorer export.
    public var pinCode: String?
    public var lightGroups: [ControllerGroup]
    public var sunBlindGroups: [ControllerGroup]
    public var spaceOwners: [String]

    public init(
        resourceIndex: Int? = nil,
        bluetoothMode: BluetoothMode? = nil,
        modelType: RoomModelType? = nil,
        name: String? = nil,
        roomName: String? = nil,
        subnetID: Int? = nil,
        beaconNetworkUUID: String? = nil,
        pinCode: String? = nil,
        lightGroups: [ControllerGroup] = [],
        sunBlindGroups: [ControllerGroup] = [],
        spaceOwners: [String] = []
    ) {
        self.resourceIndex = resourceIndex
        self.bluetoothMode = bluetoothMode
        self.modelType = modelType
        self.name = name
        self.roomName = roomName
        self.subnetID = subnetID
        self.beaconNetworkUUID = beaconNetworkUUID
        self.pinCode = pinCode
        self.lightGroups = lightGroups
        self.sunBlindGroups = sunBlindGroups
        self.spaceOwners = spaceOwners
    }

    public struct PublicSummary: Equatable, Sendable, Codable {
        public var resourceIndex: Int?
        public var bluetoothMode: String?
        public var bluetoothModeRaw: Int?
        public var modelType: String?
        public var modelTypeRaw: Int?
        public var name: String?
        public var roomName: String?
        public var subnetID: Int?
        public var beaconNetworkUUID: String?
        public var lightGroups: [ControllerGroup]
        public var sunBlindGroups: [ControllerGroup]
        public var spaceOwners: [String]
    }

    public func publicSummary() -> PublicSummary {
        PublicSummary(
            resourceIndex: resourceIndex,
            bluetoothMode: bluetoothMode?.label,
            bluetoothModeRaw: bluetoothMode?.raw,
            modelType: modelType?.label,
            modelTypeRaw: modelType?.raw,
            name: name,
            roomName: roomName,
            subnetID: subnetID,
            beaconNetworkUUID: beaconNetworkUUID,
            lightGroups: lightGroups,
            sunBlindGroups: sunBlindGroups,
            spaceOwners: spaceOwners
        )
    }
}

public enum ControllerParseError: Error, Equatable, CustomStringConvertible {
    case empty
    case unrecognized
    case json(String)
    case xml(String)

    public var description: String {
        switch self {
        case .empty: "The controller document is empty."
        case .unrecognized: "The document is not a ble-room-devices record."
        case .json(let message): "JSON: \(message)"
        case .xml(let message): "XML: \(message)"
        }
    }
}

public enum ControllerDocument {
    public static func parse(_ data: Data) throws -> [ControllerRoomDevice] {
        let body = data.drop { byte in
            byte == 0xEF || byte == 0xBB || byte == 0xBF || byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
        guard let first = body.first else { throw ControllerParseError.empty }
        if first == UInt8(ascii: "<") {
            return try parseXML(data)
        }
        return try parseJSON(data)
    }

    private static func parseJSON(_ data: Data) throws -> [ControllerRoomDevice] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ControllerParseError.json(error.localizedDescription)
        }
        let devices = try collectJSON(object)
        if devices.isEmpty { throw ControllerParseError.unrecognized }
        return devices
    }

    private static func collectJSON(_ any: Any) throws -> [ControllerRoomDevice] {
        if any is NSNull { return [] }
        if let array = any as? [Any] {
            return try array.flatMap { try collectJSON($0) }
        }
        guard let dict = any as? [String: Any] else {
            throw ControllerParseError.unrecognized
        }
        let lowered = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })
        if let nested = lowered["bleroomdevices"] ?? lowered["devices"] ?? lowered["bleroomdevice"] {
            let found = try collectJSON(nested)
            if !found.isEmpty { return found }
        }
        if isDevice(lowered) {
            return [device(from: lowered)]
        }
        throw ControllerParseError.unrecognized
    }

    private static func isDevice(_ dict: [String: Any]) -> Bool {
        ["resourceindex", "bluetoothmode", "modeltype", "lightgroups", "sunblindgroups", "roomname", "pincode"]
            .contains { dict[$0] != nil }
    }

    private static func device(from dict: [String: Any]) -> ControllerRoomDevice {
        var device = ControllerRoomDevice()
        device.resourceIndex = intValue(dict["resourceindex"])
        if let raw = intValue(dict["bluetoothmode"]) {
            device.bluetoothMode = BluetoothMode(raw: raw)
        }
        if let raw = intValue(dict["modeltype"]) {
            device.modelType = RoomModelType(raw: raw)
        }
        device.name = stringValue(dict["name"])
        device.roomName = stringValue(dict["roomname"])
        device.subnetID = intValue(dict["subnetid"])
        device.beaconNetworkUUID = stringValue(dict["uuid"])
        device.pinCode = stringValue(dict["pincode"])
        device.lightGroups = groups(dict["lightgroups"])
        device.sunBlindGroups = groups(dict["sunblindgroups"])
        device.spaceOwners = strings(dict["spaceowners"])
        return device
    }

    private static func groups(_ any: Any?) -> [ControllerGroup] {
        guard let array = any as? [Any] else { return [] }
        return array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            let lowered = Dictionary(uniqueKeysWithValues: dict.map { ($0.key.lowercased(), $0.value) })
            return ControllerGroup(
                id: intValue(lowered["id"]),
                index: intValue(lowered["index"]),
                name: stringValue(lowered["name"]),
                displayName: stringValue(lowered["displayname"]),
                enabled: boolValue(lowered["enabled"])
            )
        }
    }

    private static func strings(_ any: Any?) -> [String] {
        if let string = stringValue(any) { return [string] }
        guard let array = any as? [Any] else { return [] }
        return array.compactMap { stringValue($0) }
    }

    private static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        switch any {
        case let value as Bool:
            return value
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes": return true
            case "false", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func parseXML(_ data: Data) throws -> [ControllerRoomDevice] {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let delegate = ControllerXMLParser()
        parser.delegate = delegate
        if !parser.parse() {
            throw ControllerParseError.xml(delegate.failure ?? parser.parserError?.localizedDescription ?? "The XML did not parse.")
        }
        if let failure = delegate.failure {
            throw ControllerParseError.xml(failure)
        }
        if delegate.devices.isEmpty {
            throw ControllerParseError.unrecognized
        }
        return delegate.devices
    }
}

private final class ControllerXMLParser: NSObject, XMLParserDelegate {
    var devices: [ControllerRoomDevice] = []
    var failure: String?
    private var stack: [String] = []
    private var text = ""
    private var device: ControllerRoomDevice?
    private var group: ControllerGroup?
    private var groupKind: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        let name = elementName.lowercased()
        stack.append(name)
        switch name {
        case "bleroomdevice":
            device = ControllerRoomDevice()
        case "lightgroup":
            group = ControllerGroup()
            groupKind = "light"
        case "sunblindgroup":
            group = ControllerGroup()
            groupKind = "blind"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        if name == "lightgroup" || name == "sunblindgroup" {
            if let group, var device {
                if groupKind == "blind" {
                    device.sunBlindGroups.append(group)
                } else {
                    device.lightGroups.append(group)
                }
                self.device = device
            }
            group = nil
            groupKind = nil
        } else if parent == "lightgroup" || parent == "sunblindgroup" {
            assignGroup(name, value)
        } else if name == "spaceowner" {
            if !value.isEmpty {
                device?.spaceOwners.append(value)
            }
        } else if parent == "bleroomdevice" {
            assignDevice(name, value)
        }
        if name == "bleroomdevice", let device {
            devices.append(device)
            self.device = nil
        }
        text = ""
        if !stack.isEmpty {
            stack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failure = parseError.localizedDescription
    }

    private func assignGroup(_ name: String, _ value: String) {
        guard var group else { return }
        switch name {
        case "id": group.id = Int(value)
        case "index": group.index = Int(value)
        case "name": group.name = value.isEmpty ? nil : value
        case "displayname": group.displayName = value.isEmpty ? nil : value
        case "enabled": group.enabled = value.lowercased() == "true" || value == "1"
        default: break
        }
        self.group = group
    }

    private func assignDevice(_ name: String, _ value: String) {
        guard var device else { return }
        switch name {
        case "resourceindex": device.resourceIndex = Int(value)
        case "bluetoothmode":
            if let raw = Int(value) { device.bluetoothMode = BluetoothMode(raw: raw) }
        case "modeltype":
            if let raw = Int(value) { device.modelType = RoomModelType(raw: raw) }
        case "name": device.name = value.isEmpty ? nil : value
        case "roomname": device.roomName = value.isEmpty ? nil : value
        case "subnetid": device.subnetID = Int(value)
        case "uuid": device.beaconNetworkUUID = value.isEmpty ? nil : value
        case "pincode": device.pinCode = value.isEmpty ? nil : value
        default: break
        }
        self.device = device
    }
}
