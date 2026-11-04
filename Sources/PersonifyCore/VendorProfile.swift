import Foundation

/// Identifiers observed on a my PERSONIFY room controller.
/// Company 838 (0x0346) and the UUID suffix are what those controllers advertised.
/// They are not a published GATT specification.
public enum PersonifyVendor {
    public static let companyID: UInt16 = 838
    public static let uuidSuffix = "00137E5A8EEF"
    /// The service these room controllers put in their advertisement.
    public static let advertisedServiceShortID = "00010000"

    public static func isPersonifyAdvertisement(serviceUUIDs: [String], companyIDs: [UInt16]) -> Bool {
        if companyIDs.contains(companyID) { return true }
        return serviceUUIDs.contains { shortIdentifier($0) == advertisedServiceShortID }
    }

    /// `00010001-0000-0000-0000-00137E5A8EEF` becomes `00010001`.
    public static func shortIdentifier(_ uuid: String) -> String? {
        let hex = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        guard hex.count == 32, hex.hasSuffix(uuidSuffix) else { return nil }
        return String(hex.prefix(8))
    }

    public static func isLiveValue(_ uuid: String) -> Bool {
        guard let short = shortIdentifier(uuid) else { return false }
        return short == "00020001" || short == "00020002" || short == "00020003"
    }

    /// ATT value handles for the live status characteristics.
    /// CoreBluetooth reads them by UUID; the handles are the capture's names for the same three values.
    public static let liveStatusHandles: [String: UInt16] = [
        "00020001": 0x1C,
        "00020002": 0x1F,
        "00020003": 0x22,
    ]
}

public struct RoomRecognition: Equatable, Sendable {
    public var signals: [String]

    public init(signals: [String]) {
        self.signals = signals
    }

    public var isLikelyRoomDevice: Bool { !signals.isEmpty }

    public static func evaluate(name: String?, serviceUUIDs: [String], companyIDs: [UInt16]) -> RoomRecognition {
        var signals: [String] = []
        let names = RoomNameHeuristic.match(name).matchedTerms
        signals.append(contentsOf: names.map { "name \($0)" })
        if serviceUUIDs.contains(where: { PersonifyVendor.shortIdentifier($0) != nil }) {
            signals.append("service \(PersonifyVendor.uuidSuffix)")
        }
        if companyIDs.contains(PersonifyVendor.companyID) {
            signals.append("company 0x0346")
        }
        return RoomRecognition(signals: signals)
    }
}

public struct VendorGroup: Equatable, Sendable {
    public var index: Int
    public var name: String
    public var trailingHex: String

    public init(index: Int, name: String, trailingHex: String) {
        self.index = index
        self.name = name
        self.trailingHex = trailingHex
    }
}

public struct VendorFloatSlot: Equatable, Sendable {
    public var index: Int
    public var bits: UInt32
    public var text: String

    public init(index: Int, bits: UInt32, text: String) {
        self.index = index
        self.bits = bits
        self.text = text
    }
}

public struct VendorReading: Equatable, Sendable {
    public var lines: [String]
    public var groups: [VendorGroup]
    public var floatSlots: [VendorFloatSlot]

    public init(lines: [String], groups: [VendorGroup] = [], floatSlots: [VendorFloatSlot] = []) {
        self.lines = lines
        self.groups = groups
        self.floatSlots = floatSlots
    }
}

public struct ValueChange: Equatable, Sendable {
    public var uuid: String
    public var summary: String

    public init(uuid: String, summary: String) {
        self.uuid = uuid
        self.summary = summary
    }
}

public enum SnapshotComparison {
    /// Diff two per-characteristic byte maps. Float-slot text is included when the UUID is on the vendor base.
    public static func diff(before: [String: Data], after: [String: Data]) -> [ValueChange] {
        let keys = Set(before.keys).union(after.keys).sorted()
        var changes: [ValueChange] = []
        for uuid in keys {
            let left = before[uuid]
            let right = after[uuid]
            if left == right { continue }
            let short = PersonifyVendor.shortIdentifier(uuid) ?? uuid
            let summary: String
            if left == nil, let right {
                summary = "\(short) is new (\(right.count) bytes)."
            } else if right == nil {
                summary = "\(short) is missing from the new snapshot."
            } else if let left, let right {
                let slots = VendorValueDecoder.diff(uuid: uuid, before: left, after: right)
                if slots.isEmpty {
                    summary = "\(short) bytes changed (\(left.count) → \(right.count))."
                } else {
                    let detail = slots.map { change in
                        change.index < 0
                            ? "length \(change.before) → \(change.after)"
                            : "slot \(change.index) \(change.before) → \(change.after)"
                    }.joined(separator: ", ")
                    summary = "\(short) \(detail)."
                }
            } else {
                summary = "\(short) changed."
            }
            changes.append(ValueChange(uuid: uuid, summary: summary))
        }
        return changes
    }

    /// Read-batch bytes overlay the latest read or notify map. Characteristics that were only notified stay in the result, so a snapshot diff is not limited to the batch that just finished.
    public static func covering(latest: [String: Data], readBatch: [String: Data]) -> [String: Data] {
        var combined = latest
        for (uuid, bytes) in readBatch {
            combined[uuid] = bytes
        }
        return combined
    }
}

public struct CaptureChange: Equatable, Sendable {
    public var index: Int
    public var before: String
    public var after: String

    public init(index: Int, before: String, after: String) {
        self.index = index
        self.before = before
        self.after = after
    }
}

public enum VendorValueDecoder {
    /// Read-only interpretation of one captured characteristic. Returns nil for UUIDs outside this vendor base.
    public static func decode(uuid: String, data: Data) -> VendorReading? {
        guard let short = PersonifyVendor.shortIdentifier(uuid) else { return nil }
        switch short {
        case "00010001":
            return configBlob(data)
        case "00010002", "00010003":
            return groupList(data)
        case "00010004":
            return singleTLV(data)
        case "00020001":
            var reading = floatBlob(data, alignedOnly: false)
            reading = VendorReading(
                lines: confirmedLiveValues(data) + reading.lines,
                groups: reading.groups,
                floatSlots: reading.floatSlots
            )
            return reading
        case "00020002":
            var reading = floatBlob(data, alignedOnly: true)
            reading = VendorReading(
                lines: confirmedLightLevels(data) + reading.lines,
                groups: reading.groups,
                floatSlots: reading.floatSlots
            )
            return reading
        case "00020003":
            var reading = floatBlob(data, alignedOnly: true)
            reading = VendorReading(
                lines: confirmedBlindPositions(data) + reading.lines,
                groups: reading.groups,
                floatSlots: reading.floatSlots
            )
            return reading
        default:
            return nil
        }
    }

    public static func diff(uuid: String, before: Data, after: Data) -> [CaptureChange] {
        let left = decode(uuid: uuid, data: before)?.floatSlots ?? []
        let right = decode(uuid: uuid, data: after)?.floatSlots ?? []
        if left.isEmpty && right.isEmpty {
            if before == after { return [] }
            return [CaptureChange(index: -1, before: Hex.encode(before), after: Hex.encode(after))]
        }
        let count = min(left.count, right.count)
        var changes: [CaptureChange] = []
        for index in 0..<count where left[index].text != right[index].text {
            changes.append(CaptureChange(index: index, before: left[index].text, after: right[index].text))
        }
        if left.count != right.count {
            changes.append(CaptureChange(index: -1, before: "\(left.count) slots", after: "\(right.count) slots"))
        }
        return changes
    }

    /// Lines the device view should show above the raw slot dump.
    public static func summaryLines(uuid: String, data: Data) -> [String] {
        guard let reading = decode(uuid: uuid, data: data) else { return [] }
        return reading.lines.filter { line in
            line.hasPrefix("Confirmed ") || line.hasPrefix("Group ") || line.hasPrefix("Blind group ") || line.hasPrefix("Float32 at absolute")
        }
    }

    private static func configBlob(_ data: Data) -> VendorReading {
        VendorReading(
            lines: [
                "\(data.count) bytes. No group-name records of the kind in 00010002 and 00010003.",
                "Leading bytes \(Hex.encode(Data(data.prefix(4)), spaced: true)).",
            ]
        )
    }

    private static func singleTLV(_ data: Data) -> VendorReading {
        guard data.count >= 2, Int(data[1]) == data.count - 2 else {
            return VendorReading(lines: ["\(data.count) bytes, not a single TLV."])
        }
        let value = Data(data.dropFirst(2))
        return VendorReading(lines: [
            String(format: "TLV type 0x%02X, length %d, value %@.", data[0], Int(data[1]), Hex.encode(value, spaced: true)),
        ])
    }

    private static func groupList(_ data: Data) -> VendorReading {
        let body = groupBody(data)
        let groups = parseGroups(body)
        let lines = groups.map { group in
            "Index \(group.index): \(group.name), trailing \(group.trailingHex)."
        }
        return VendorReading(
            lines: lines.isEmpty ? ["No group-name records."] : lines,
            groups: groups
        )
    }

    /// Drops the 3-byte header when its length byte matches the remainder.
    /// 00010003 is `80 01 78` and 0x78 is the remainder. 00010002 is `78 88 01` and 0x88 is the remainder.
    private static func groupBody(_ data: Data) -> Data {
        guard data.count >= 3 else { return data }
        if data[0] == 0x80, data[1] == 0x01, Int(data[2]) == data.count - 3 {
            return Data(data.dropFirst(3))
        }
        if Int(data[1]) == data.count - 3 {
            return Data(data.dropFirst(3))
        }
        return data
    }

    private static func parseGroups(_ data: Data) -> [VendorGroup] {
        var groups: [VendorGroup] = []
        var offset = 0
        while offset + 2 <= data.count {
            let type = data[offset]
            let length = Int(data[offset + 1])
            let end = offset + 2 + length
            guard type == 0x08, end <= data.count else { break }
            if let group = parseGroup(Data(data[offset + 2..<end])) {
                groups.append(group)
            }
            offset = end
        }
        return groups
    }

    private static func parseGroup(_ payload: Data) -> VendorGroup? {
        guard payload.count >= 4, payload[0] == 0x05, payload[2] == 0x0A else { return nil }
        let index = Int(payload[1])
        let nameLength = Int(payload[3])
        let nameStart = 4
        let nameEnd = nameStart + nameLength
        guard nameEnd <= payload.count else { return nil }
        let nameData = payload[nameStart..<nameEnd].filter { $0 != 0 }
        let name = String(decoding: nameData, as: UTF8.self)
        guard name.hasPrefix("Group") || !name.isEmpty else { return nil }
        let trailing = Data(payload[nameEnd...])
        return VendorGroup(index: index, name: name, trailingHex: Hex.encode(trailing))
    }

    /// Each aligned float32 in 00020002 is one group's light level. 100 is on and 0 is off.
    /// The toggled group is absolute bytes 8-11 (`0x42c80000` = 100, then 0, then 100).
    private static func confirmedLightLevels(_ data: Data) -> [String] {
        guard data.count >= 4, data.count % 4 == 0 else { return [] }
        var lines: [String] = []
        var offset = 0
        var group = 0
        while offset + 4 <= data.count {
            let bits = readUInt32LE(data, offset)
            let value = Float(bitPattern: bits)
            let text: String
            if value.isNaN {
                text = "unset"
            } else if value.isInfinite {
                offset += 4
                group += 1
                continue
            } else if abs(value) <= 0.0001 {
                text = "0% (off)"
            } else if abs(value - 100) <= 0.0001 {
                text = "100% (on)"
            } else {
                text = "\(plainNumber(value))%"
            }
            lines.append("Confirmed light level, group \(group): \(text). Little-endian float32 at absolute bytes \(offset)-\(offset + 3).")
            offset += 4
            group += 1
        }
        return lines
    }

    /// 16-byte records, four little-endian float32 values each.
    /// Float 0 is how closed the group is: 0% closed is fully open. Record 0 is Group 1.
    /// NaN (`00 00 c0 7f`) means that group does not exist.
    private static func confirmedBlindPositions(_ data: Data) -> [String] {
        let recordBytes = 16
        let count = data.count / recordBytes
        guard count > 0 else { return [] }
        var lines: [String] = []
        for record in 0..<count {
            let byte = record * recordBytes
            let bits = readUInt32LE(data, byte)
            let value = Float(bitPattern: bits)
            let number = record + 1
            if value.isNaN {
                lines.append("Group \(number) is not present.")
            } else if !value.isInfinite {
                lines.append("Group \(number): \(plainNumber(value))% closed.")
            }
        }
        return lines
    }

    /// Absolute indexes into the raw 00020001 value.
    /// Bytes 12-15 are `c0 7f 00 00` and do not change. The setpoint pattern
    /// `00 00 00 bf` (−0.5) → `00 00 c0 bf` (−1.5) occupies absolute bytes 14-17.
    /// The room temperature 21.615 occupies absolute bytes 27-30, not 25-28.
    /// Bytes 18-21 are the fan (`1` Auto, `2` Off, `3`/`4`/`5` speeds 1/2/3).
    /// Bytes 22-25 are a separate float whose role is still unknown.
    private static func confirmedLiveValues(_ data: Data) -> [String] {
        var lines: [String] = []
        if data.count >= 18 {
            let bits = readUInt32LE(data, 14)
            let value = Float(bitPattern: bits)
            if !value.isNaN, !value.isInfinite {
                lines.append("Confirmed setpoint offset: \(plainNumber(value)) °C from the base temperature (range -3 to +3 °C). Little-endian float32 0x\(String(format: "%08x", bits)) at absolute bytes 14-17.")
            }
        }
        if let first = floatAt(data, byte: 18) {
            if let fan = FanSetting.from(wire: first) {
                lines.append("Confirmed fan: \(fan.title). Little-endian float32 \(plainNumber(first)) at absolute bytes 18-21.")
            } else {
                lines.append("Float32 at absolute bytes 18-21: \(plainNumber(first)). Not a known fan value.")
            }
        }
        if let second = floatAt(data, byte: 22) {
            lines.append("Float32 at absolute bytes 22-25: \(plainNumber(second)). Role is not known.")
        }
        if let temperature = floatAt(data, byte: 27) {
            lines.append("Confirmed room temperature: \(plainNumber(temperature)) °C. Little-endian float32 at absolute bytes 27-30.")
        }
        return lines
    }

    private static func floatAt(_ data: Data, byte: Int) -> Float? {
        guard byte >= 0, byte + 4 <= data.count else { return nil }
        let bits = readUInt32LE(data, byte)
        let value = Float(bitPattern: bits)
        if value.isNaN || value.isInfinite { return nil }
        return value
    }

    private static func plainNumber(_ value: Float) -> String {
        let nearest = value.rounded()
        if abs(value - nearest) <= 0.0001 {
            return String(Int(nearest))
        }
        let tenths = (value * 10).rounded() / 10
        if abs(value - tenths) <= 0.0001 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.3f", value)
    }

    private static func floatBlob(_ data: Data, alignedOnly: Bool) -> VendorReading {
        if data.count % 4 == 0 {
            let slots = alignedSlots(data)
            return VendorReading(
                lines: ["Little-endian float32, \(slots.count) slots."] + slots.map { "\($0.index): \($0.text)" },
                floatSlots: slots
            )
        }
        if alignedOnly {
            return VendorReading(lines: ["\(data.count) bytes is not a whole number of float32 values."])
        }
        let slots = scannedSlots(data)
        let lines = ["Mixed bytes and little-endian float32."] + slots.map { slot in
            "\(slot.index): \(slot.text)"
        }
        return VendorReading(lines: lines, floatSlots: slots)
    }

    static func alignedSlots(_ data: Data) -> [VendorFloatSlot] {
        var slots: [VendorFloatSlot] = []
        var offset = 0
        var index = 0
        while offset + 4 <= data.count {
            let bits = readUInt32LE(data, offset)
            slots.append(VendorFloatSlot(index: index, bits: bits, text: floatText(bits)))
            offset += 4
            index += 1
        }
        return slots
    }

    /// Used when the buffer is not a whole number of float32s.
    /// A canonical NaN (`0x7fc00000` or `0xffc00000`) wins over an overlapping finite value.
    private static func scannedSlots(_ data: Data) -> [VendorFloatSlot] {
        var slots: [VendorFloatSlot] = []
        var offset = 0
        var index = 0
        while offset < data.count {
            if offset + 4 <= data.count, isCanonicalNaN(data, offset) {
                let bits = readUInt32LE(data, offset)
                slots.append(VendorFloatSlot(index: index, bits: bits, text: floatText(bits)))
                index += 1
                offset += 4
                continue
            }
            if offset + 4 <= data.count, finiteText(readUInt32LE(data, offset)) != nil {
                if offset + 5 <= data.count, isCanonicalNaN(data, offset + 1) {
                    slots.append(VendorFloatSlot(index: index, bits: UInt32(data[offset]), text: String(format: "byte %02X", data[offset])))
                    index += 1
                    offset += 1
                    continue
                }
                let bits = readUInt32LE(data, offset)
                slots.append(VendorFloatSlot(index: index, bits: bits, text: floatText(bits)))
                index += 1
                offset += 4
                continue
            }
            slots.append(VendorFloatSlot(index: index, bits: UInt32(data[offset]), text: String(format: "byte %02X", data[offset])))
            index += 1
            offset += 1
        }
        return slots
    }

    private static func isCanonicalNaN(_ data: Data, _ offset: Int) -> Bool {
        guard offset + 4 <= data.count else { return false }
        let bits = readUInt32LE(data, offset)
        return bits == 0x7FC0_0000 || bits == 0xFFC0_0000
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func floatText(_ bits: UInt32) -> String {
        if bits == 0x7FC0_0000 { return "NaN" }
        if bits == 0xFFC0_0000 { return "NaN (sign bit set)" }
        if let finite = finiteText(bits) { return finite }
        let value = Float(bitPattern: bits)
        if value.isNaN { return String(format: "NaN (0x%08X)", bits) }
        if value.isInfinite { return value.sign == .minus ? "-infinity" : "infinity" }
        return String(format: "0x%08X", bits)
    }

    /// Finite values in the office capture: -1, 1, 3, 23.017, 100, and 0.
    /// Near-integers that are not exact (the misaligned -2.000015 pattern) are rejected.
    private static func finiteText(_ bits: UInt32) -> String? {
        if bits == 0 { return "0" }
        let value = Float(bitPattern: bits)
        if value.isNaN || value.isInfinite { return nil }
        let magnitude = abs(value)
        if magnitude < 0.5 || magnitude > 500 { return nil }
        let nearest = value.rounded()
        let distance = abs(value - nearest)
        if distance < 0.001 && distance > 0.0001 { return nil }
        if distance <= 0.0001 {
            return String(Int(nearest))
        }
        return String(format: "%.3f", value)
    }
}
