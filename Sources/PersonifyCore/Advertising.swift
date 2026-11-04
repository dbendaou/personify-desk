import Foundation

public struct AdvertisementFlags: Equatable, Sendable, Codable {
    public var raw: UInt8
    public var leLimitedDiscoverable: Bool
    public var leGeneralDiscoverable: Bool
    public var brEdrNotSupported: Bool
    public var simultaneousController: Bool
    public var simultaneousHost: Bool

    public init(raw: UInt8) {
        self.raw = raw
        leLimitedDiscoverable = raw & 0x01 != 0
        leGeneralDiscoverable = raw & 0x02 != 0
        brEdrNotSupported = raw & 0x04 != 0
        simultaneousController = raw & 0x08 != 0
        simultaneousHost = raw & 0x10 != 0
    }
}

public struct AdSection: Equatable, Sendable, Codable {
    public var type: UInt8
    public var typeName: String
    public var payloadHex: String

    public init(type: UInt8, typeName: String, payloadHex: String) {
        self.type = type
        self.typeName = typeName
        self.payloadHex = payloadHex
    }
}

public struct ServiceDataRecord: Equatable, Sendable, Codable {
    public var uuid: String
    public var payloadHex: String

    public init(uuid: String, payloadHex: String) {
        self.uuid = uuid
        self.payloadHex = payloadHex
    }
}

/// Apple's public iBeacon manufacturer payload (company ID 0x004C, type 0x02, length 0x15).
/// Parsed so it can be compared with a controller beacon-network UUID. That comparison is not verified.
public struct IBeaconFields: Equatable, Sendable, Codable {
    public var uuid: String
    public var major: UInt16
    public var minor: UInt16
    public var measuredPower: Int8

    public init(uuid: String, major: UInt16, minor: UInt16, measuredPower: Int8) {
        self.uuid = uuid
        self.major = major
        self.minor = minor
        self.measuredPower = measuredPower
    }

    public static func parse(companyID: UInt16, payload: Data) -> IBeaconFields? {
        guard companyID == 0x004C, payload.count == 23, payload[0] == 0x02, payload[1] == 0x15 else {
            return nil
        }
        let uuidBytes = payload.subdata(in: 2..<18)
        let hex = Hex.encode(uuidBytes).uppercased()
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        let major = UInt16(payload[18]) << 8 | UInt16(payload[19])
        let minor = UInt16(payload[20]) << 8 | UInt16(payload[21])
        let power = Int8(bitPattern: payload[22])
        return IBeaconFields(uuid: uuid, major: major, minor: minor, measuredPower: power)
    }
}

public struct ManufacturerRecord: Equatable, Sendable, Codable {
    public var companyID: UInt16
    public var companyName: String?
    public var payloadHex: String
    public var iBeacon: IBeaconFields?

    public init(companyID: UInt16, companyName: String?, payloadHex: String, iBeacon: IBeaconFields?) {
        self.companyID = companyID
        self.companyName = companyName
        self.payloadHex = payloadHex
        self.iBeacon = iBeacon
    }

    /// CoreBluetooth's manufacturer-data value is the 16-bit company ID, little endian, then the payload.
    public static func parse(companyPrefixed data: Data) -> ManufacturerRecord {
        guard data.count >= 2 else {
            return ManufacturerRecord(
                companyID: 0,
                companyName: nil,
                payloadHex: Hex.encode(data),
                iBeacon: nil
            )
        }
        let companyID = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let payload = Data(data.dropFirst(2))
        return ManufacturerRecord(
            companyID: companyID,
            companyName: AssignedNumbers.companyName(companyID),
            payloadHex: Hex.encode(payload),
            iBeacon: IBeaconFields.parse(companyID: companyID, payload: payload)
        )
    }
}

public struct Advertisement: Equatable, Sendable, Codable {
    public var localName: String?
    public var serviceUUIDs: [String]
    public var solicitedServiceUUIDs: [String]
    public var serviceData: [ServiceDataRecord]
    public var manufacturerRecords: [ManufacturerRecord]
    public var txPower: Int?
    public var flags: AdvertisementFlags?
    public var appearance: UInt16?
    public var sections: [AdSection]
    public var warnings: [String]

    public init(
        localName: String? = nil,
        serviceUUIDs: [String] = [],
        solicitedServiceUUIDs: [String] = [],
        serviceData: [ServiceDataRecord] = [],
        manufacturerRecords: [ManufacturerRecord] = [],
        txPower: Int? = nil,
        flags: AdvertisementFlags? = nil,
        appearance: UInt16? = nil,
        sections: [AdSection] = [],
        warnings: [String] = []
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.serviceData = serviceData
        self.manufacturerRecords = manufacturerRecords
        self.txPower = txPower
        self.flags = flags
        self.appearance = appearance
        self.sections = sections
        self.warnings = warnings
    }

    /// Parse a legacy advertising or scan-response payload of AD structures.
    /// Length overruns are recorded in `warnings` and do not discard earlier fields.
    public static func parse(adStructures data: Data) -> Advertisement {
        var advertisement = Advertisement()
        var index = 0
        while index < data.count {
            let length = Int(data[index])
            if length == 0 {
                advertisement.warnings.append("zero-length AD structure at byte \(index)")
                break
            }
            let end = index + 1 + length
            if end > data.count {
                advertisement.warnings.append("truncated AD structure at byte \(index)")
                advertisement.warnings.append("trailing \(Hex.encode(Data(data.suffix(from: index))))")
                break
            }
            let type = data[index + 1]
            let payload = data.subdata(in: (index + 2)..<end)
            advertisement.consume(type: type, payload: payload)
            index = end
        }
        return advertisement
    }

    private mutating func consume(type: UInt8, payload: Data) {
        sections.append(AdSection(type: type, typeName: Self.sectionName(type), payloadHex: Hex.encode(payload)))
        switch type {
        case 0x01:
            if let first = payload.first {
                flags = AdvertisementFlags(raw: first)
            }
        case 0x02, 0x03:
            appendUUIDs(payload, width: 2, into: \.serviceUUIDs)
        case 0x04, 0x05:
            appendUUIDs(payload, width: 4, into: \.serviceUUIDs)
        case 0x06, 0x07:
            appendUUIDs(payload, width: 16, into: \.serviceUUIDs)
        case 0x08:
            if localName == nil {
                localName = String(data: payload, encoding: .utf8)
            }
        case 0x09:
            localName = String(data: payload, encoding: .utf8)
        case 0x0A:
            if let byte = payload.first {
                txPower = Int(Int8(bitPattern: byte))
            }
        case 0x14:
            appendUUIDs(payload, width: 2, into: \.solicitedServiceUUIDs)
        case 0x15:
            appendUUIDs(payload, width: 16, into: \.solicitedServiceUUIDs)
        case 0x16:
            appendServiceData(payload, uuidWidth: 2)
        case 0x19:
            if payload.count >= 2 {
                appearance = UInt16(payload[0]) | (UInt16(payload[1]) << 8)
            }
        case 0x1F:
            appendUUIDs(payload, width: 4, into: \.solicitedServiceUUIDs)
        case 0x20:
            appendServiceData(payload, uuidWidth: 4)
        case 0x21:
            appendServiceData(payload, uuidWidth: 16)
        case 0xFF:
            manufacturerRecords.append(ManufacturerRecord.parse(companyPrefixed: payload))
        default:
            break
        }
    }

    private mutating func appendUUIDs(_ payload: Data, width: Int, into keyPath: WritableKeyPath<Advertisement, [String]>) {
        guard width > 0, payload.count % width == 0 else {
            warnings.append("UUID list length \(payload.count) is not a multiple of \(width)")
            return
        }
        var offset = 0
        while offset < payload.count {
            let slice = payload.subdata(in: offset..<(offset + width))
            let formatted: String?
            switch width {
            case 2: formatted = formatUUID16(slice)
            case 4: formatted = formatUUID32(slice)
            default: formatted = formatUUID128(slice)
            }
            if let formatted {
                self[keyPath: keyPath].append(formatted)
            }
            offset += width
        }
    }

    private mutating func appendServiceData(_ payload: Data, uuidWidth: Int) {
        guard payload.count >= uuidWidth else {
            warnings.append("service data shorter than its UUID")
            return
        }
        let uuidSlice = payload.subdata(in: 0..<uuidWidth)
        let formatted: String?
        switch uuidWidth {
        case 2: formatted = formatUUID16(uuidSlice)
        case 4: formatted = formatUUID32(uuidSlice)
        default: formatted = formatUUID128(uuidSlice)
        }
        guard let formatted else { return }
        let rest = payload.subdata(in: uuidWidth..<payload.count)
        serviceData.append(ServiceDataRecord(uuid: formatted, payloadHex: Hex.encode(rest)))
    }

    private static func sectionName(_ type: UInt8) -> String {
        switch type {
        case 0x01: "Flags"
        case 0x02: "Incomplete 16-bit Service UUIDs"
        case 0x03: "Complete 16-bit Service UUIDs"
        case 0x04: "Incomplete 32-bit Service UUIDs"
        case 0x05: "Complete 32-bit Service UUIDs"
        case 0x06: "Incomplete 128-bit Service UUIDs"
        case 0x07: "Complete 128-bit Service UUIDs"
        case 0x08: "Shortened Local Name"
        case 0x09: "Complete Local Name"
        case 0x0A: "TX Power Level"
        case 0x14: "16-bit Service Solicitation UUIDs"
        case 0x15: "128-bit Service Solicitation UUIDs"
        case 0x16: "Service Data - 16-bit UUID"
        case 0x19: "Appearance"
        case 0x1F: "32-bit Service Solicitation UUIDs"
        case 0x20: "Service Data - 32-bit UUID"
        case 0x21: "Service Data - 128-bit UUID"
        case 0xFF: "Manufacturer Specific Data"
        default: String(format: "AD type 0x%02X", type)
        }
    }
}
