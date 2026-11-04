import Foundation
import Testing

@testable import PersonifyCore

private func vendorUUID(_ short: String) -> String {
    "\(short)-0000-0000-0000-00137E5A8EEF"
}

private func fixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(name).hex")
    let hex = try String(contentsOf: url, encoding: .utf8)
    return try Hex.decode(hex)
}

@Test func personifyAdvertisementsAreRecognized() {
    let service = vendorUUID("00010000")
    let room = RoomRecognition.evaluate(name: "Room A", serviceUUIDs: [service], companyIDs: [838])
    #expect(room.isLikelyRoomDevice)
    #expect(room.signals.contains("service 00137E5A8EEF"))
    #expect(room.signals.contains("company 0x0346"))

    let other = RoomRecognition.evaluate(name: "Room B", serviceUUIDs: [service], companyIDs: [838])
    #expect(other.isLikelyRoomDevice)

    let nameOnly = RoomRecognition.evaluate(name: "Room A", serviceUUIDs: [], companyIDs: [])
    #expect(nameOnly.isLikelyRoomDevice == false)

    let lounge = RoomRecognition.evaluate(name: "Lounge", serviceUUIDs: [], companyIDs: [])
    #expect(lounge.isLikelyRoomDevice == false)
}

@Test func configCharacteristicsMatchTheRoomCapture() throws {
    let groups2 = try fixture("00010002")
    let reading2 = VendorValueDecoder.decode(uuid: vendorUUID("00010002"), data: groups2)
    #expect(reading2?.groups.map(\.name) == (1...8).map { "Group\($0)" })
    #expect(reading2?.groups.map(\.index) == [0, 2, 4, 6, 8, 10, 12, 14])
    #expect(reading2?.groups.first?.trailingHex == "15021f27")

    let groups3 = try fixture("00010003")
    let reading3 = VendorValueDecoder.decode(uuid: vendorUUID("00010003"), data: groups3)
    #expect(reading3?.groups.map(\.name) == reading2?.groups.map(\.name))
    #expect(reading3?.groups.map(\.index) == reading2?.groups.map(\.index))
    #expect(reading3?.groups.first?.trailingHex == "1f27")

    let header = try fixture("00010001")
    let reading1 = VendorValueDecoder.decode(uuid: vendorUUID("00010001"), data: header)
    #expect(reading1?.groups.isEmpty == true)
    #expect(reading1?.lines.contains { $0.contains("No group-name records") } == true)
    #expect(reading1?.lines.contains { $0.contains("0d 00 16 00") } == true)

    let tail = try fixture("00010004")
    let reading4 = VendorValueDecoder.decode(uuid: vendorUUID("00010004"), data: tail)
    #expect(reading4?.lines == ["TLV type 0x88, length 1, value 00."])
}

@Test func liveFloatsMatchTheRoomCapture() throws {
    let second = try fixture("00020002")
    let reading2 = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020002"), data: second))
    #expect(reading2.floatSlots.count == 26)
    #expect(reading2.floatSlots[0].text == "NaN")
    #expect(reading2.floatSlots[0].bits == 0x7FC0_0000)
    #expect(reading2.floatSlots[1].text == "100")
    #expect(reading2.floatSlots[1].bits == 0x42C8_0000)
    #expect(reading2.floatSlots[2].text == "NaN (sign bit set)")
    #expect(reading2.floatSlots[2].bits == 0xFFC0_0000)
    #expect(reading2.floatSlots[4].text == "0")

    let third = try fixture("00020003")
    let reading3 = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020003"), data: third))
    #expect(reading3.floatSlots.count == 36)
    #expect(reading3.floatSlots[0].text == "0")
    #expect(reading3.floatSlots[2].text == "NaN")
    #expect(reading3.floatSlots[3].text == "NaN")

    let first = try fixture("00020001")
    let reading1 = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020001"), data: first))
    let texts = reading1.floatSlots.map(\.text)
    #expect(texts.contains("-1"))
    #expect(texts.contains("1"))
    #expect(texts.contains("3"))
    #expect(texts.contains("23.017"))
    #expect(texts.contains("NaN"))
    #expect(texts.contains("byte FF"))
}

@Test func snapshotDiffShowsTheFloatSlotThatMovedAndIgnoresUnchangedValues() throws {
    let uuid = vendorUUID("00020002")
    let beforeValue = try Hex.decode("0000c07f0000c8420000c0ff0000c842")
    var moved = [UInt8](beforeValue)
    moved[4] = 0x00
    moved[5] = 0x00
    moved[6] = 0x48
    moved[7] = 0x42
    let same = Data([0x00])
    let changes = SnapshotComparison.diff(
        before: [uuid: beforeValue, "stable": same],
        after: [uuid: Data(moved), "stable": same]
    )
    #expect(changes.map(\.uuid) == [uuid])
    #expect(changes.first?.summary.contains("slot 1 100 → 50") == true)
}

@Test func personifyListMatchesCompany838OrTheAdvertisedService() {
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: [], companyIDs: [838]))
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: [], companyIDs: [0x0346]))
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: [vendorUUID("00010000")], companyIDs: []))
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: ["180D"], companyIDs: [0x004C]) == false)
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: [vendorUUID("00020001")], companyIDs: []) == false)
    #expect(PersonifyVendor.isPersonifyAdvertisement(serviceUUIDs: [vendorUUID("00020003")], companyIDs: [76]) == false)
}

@Test func confirmedTemperatureFieldsUseAbsoluteBytes() throws {
    let before = try fixture("00020001-room-a-before")
    let after = try fixture("00020001-room-a-after")
    #expect([UInt8](before[12..<16]) == [0xC0, 0x7F, 0x00, 0x00])
    #expect([UInt8](after[12..<16]) == [0xC0, 0x7F, 0x00, 0x00])
    #expect([UInt8](before[14..<18]) == [0x00, 0x00, 0x00, 0xBF])
    #expect([UInt8](after[14..<18]) == [0x00, 0x00, 0xC0, 0xBF])
    #expect([UInt8](before[25..<29]) == [UInt8](after[25..<29]))
    let changed = zip(before, after).enumerated().compactMap { index, pair in pair.0 == pair.1 ? nil : index }
    #expect(changed == [16])

    let earlier = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020001"), data: before))
    let later = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020001"), data: after))
    #expect(earlier.lines.contains("Confirmed setpoint offset: -0.5 °C from the base temperature (range -3 to +3 °C). Little-endian float32 0xbf000000 at absolute bytes 14-17."))
    #expect(later.lines.contains("Confirmed setpoint offset: -1.5 °C from the base temperature (range -3 to +3 °C). Little-endian float32 0xbfc00000 at absolute bytes 14-17."))
    let room = "Confirmed room temperature: 21.615 °C. Little-endian float32 at absolute bytes 27-30."
    #expect(earlier.lines.contains(room))
    #expect(later.lines.contains(room))
    let fan = "Confirmed fan: Off. Little-endian float32 2 at absolute bytes 18-21."
    let bounds = "Float32 at absolute bytes 22-25: 2. Role is not known."
    #expect(earlier.lines.contains(fan))
    #expect(later.lines.contains(fan))
    #expect(earlier.lines.contains(bounds))
    #expect(later.lines.contains(bounds))

    let sample = try fixture("00020001")
    let reading = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020001"), data: sample))
    #expect(reading.lines.contains("Confirmed setpoint offset: -1 °C from the base temperature (range -3 to +3 °C). Little-endian float32 0xbf800000 at absolute bytes 14-17."))
    #expect(reading.lines.contains("Confirmed room temperature: 23.017 °C. Little-endian float32 at absolute bytes 27-30."))
    #expect(reading.lines.contains("Confirmed fan: Auto. Little-endian float32 1 at absolute bytes 18-21."))
    #expect(reading.lines.contains("Float32 at absolute bytes 22-25: 3. Role is not known."))

    var drifted = [UInt8](sample)
    drifted[28] &+= 1
    drifted[29] &+= 1
    let moved = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020001"), data: Data(drifted)))
    #expect(reading.lines.first { $0.hasPrefix("Confirmed room temperature") } != moved.lines.first { $0.hasPrefix("Confirmed room temperature") })
    #expect(reading.lines.first { $0.hasPrefix("Confirmed setpoint offset") } == moved.lines.first { $0.hasPrefix("Confirmed setpoint offset") })
}

@Test func blindPositionIsFloatZeroOfEach00020003Record() throws {
    let unset = try fixture("00020003")
    let idle = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020003"), data: unset))
    let idleLines = idle.lines.filter { $0.hasPrefix("Group ") }
    #expect(idleLines.count == 9)
    #expect(idleLines.allSatisfy { $0.hasSuffix(": 0% closed.") })

    let lights = try fixture("00020002")
    let other = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020002"), data: lights))
    #expect(other.lines.contains { $0.hasPrefix("Group ") && $0.contains("% closed") } == false)

    let beforeMove = try fixture("00020003-room-a-idle")
    let afterMove = try fixture("00020003-room-a-set")
    let hidden = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020003"), data: beforeMove))
    let set = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020003"), data: afterMove))
    #expect(hidden.lines.filter { $0.hasPrefix("Group ") }.allSatisfy { $0.contains("is not present") })
    #expect(hidden.lines.contains("Group 2 is not present."))
    #expect(set.lines.contains("Group 1: 60% closed."))
    #expect(set.lines.contains("Group 2: 60% closed."))
    #expect(set.lines.contains("Group 3 is not present."))
    #expect(set.lines.contains("Group 9 is not present."))

    let changes = VendorValueDecoder.diff(uuid: vendorUUID("00020003"), before: beforeMove, after: afterMove)
    #expect(changes == [
        CaptureChange(index: 0, before: "NaN", after: "60"),
        CaptureChange(index: 4, before: "NaN (sign bit set)", after: "60"),
    ])

    var opened = [UInt8](afterMove)
    for index in [0, 1, 2, 3, 16, 17, 18, 19] {
        opened[index] = 0
    }
    let fullyOpen = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020003"), data: Data(opened)))
    #expect(fullyOpen.lines.contains("Group 1: 0% closed."))
    #expect(fullyOpen.lines.contains("Group 2: 0% closed."))
    let openedChanges = VendorValueDecoder.diff(uuid: vendorUUID("00020003"), before: afterMove, after: Data(opened))
    #expect(openedChanges == [
        CaptureChange(index: 0, before: "60", after: "0"),
        CaptureChange(index: 4, before: "60", after: "0"),
    ])
}

@Test func lightLevelAtBytes8Through11IsConfirmedOnOff() throws {
    var on = Data(count: 12)
    on[8] = 0x00
    on[9] = 0x00
    on[10] = 0xC8
    on[11] = 0x42
    #expect([UInt8](on[8..<12]) == [0x00, 0x00, 0xC8, 0x42])
    let lit = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020002"), data: on))
    #expect(lit.lines.contains("Confirmed light level, group 2: 100% (on). Little-endian float32 at absolute bytes 8-11."))

    var off = on
    off[8] = 0
    off[9] = 0
    off[10] = 0
    off[11] = 0
    let dark = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020002"), data: off))
    #expect(dark.lines.contains("Confirmed light level, group 2: 0% (off). Little-endian float32 at absolute bytes 8-11."))

    let backOn = try #require(VendorValueDecoder.decode(uuid: vendorUUID("00020002"), data: on))
    #expect(backOn.lines.contains("Confirmed light level, group 2: 100% (on). Little-endian float32 at absolute bytes 8-11."))

    let toggled = VendorValueDecoder.diff(uuid: vendorUUID("00020002"), before: on, after: off)
    #expect(toggled == [CaptureChange(index: 2, before: "100", after: "0")])

    let temperature = vendorUUID("00020001")
    let light = vendorUUID("00020002")
    let beforeTemperature = try fixture("00020001-room-a-before")
    let afterTemperature = try fixture("00020001-room-a-after")
    let covered = SnapshotComparison.covering(latest: [light: off], readBatch: [temperature: afterTemperature])
    #expect(covered[light] == off)
    #expect(covered[temperature] == afterTemperature)
    let both = SnapshotComparison.diff(
        before: [light: on, temperature: beforeTemperature],
        after: covered
    )
    #expect(both.map(\.uuid).sorted() == [light, temperature].sorted())
    #expect(both.contains { $0.summary.contains("00020002") && $0.summary.contains("100 → 0") })
    #expect(both.contains { $0.summary.contains("00020001") })
}

@Test func floatDiffReportsOnlyTheSlotThatMoved() throws {
    let before = try Hex.decode("0000c07f0000c8420000c0ff0000c842")
    var afterBytes = [UInt8](before)
    afterBytes[4] = 0x00
    afterBytes[5] = 0x00
    afterBytes[6] = 0x48
    afterBytes[7] = 0x42
    let changes = VendorValueDecoder.diff(uuid: vendorUUID("00020002"), before: before, after: Data(afterBytes))
    #expect(changes == [CaptureChange(index: 1, before: "100", after: "50")])
}
