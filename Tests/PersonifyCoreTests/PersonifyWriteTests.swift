import Foundation
import Testing

@testable import PersonifyCore

@Test func capturedFramesMatchThePacketLoggerBytes() throws {
    #expect(Hex.encode(PersonifyWrite.setpointOffset(-2.5)) == "00020e00000020c0")
    #expect(Hex.encode(PersonifyWrite.lightLevel(0)) == "0102000000000000")
    #expect(Hex.encode(PersonifyWrite.lightLevel(100)) == "010200000000c842")
    let blind1 = try #require(PersonifyWrite.blindClosed(number: 1, percent: 3))
    let blind8 = try #require(PersonifyWrite.blindClosed(number: 8, percent: 3))
    #expect(Hex.encode(blind1) == "0202100000004040")
    #expect(Hex.encode(blind8) == "0202800000004040")
}

@Test func setpointOffsetClampsToHalfDegreesAndIgnoresField18() {
    #expect(PersonifyWrite.clampedOffset(4) == 3)
    #expect(PersonifyWrite.clampedOffset(-4) == -3)
    #expect(PersonifyWrite.clampedOffset(0.25) == 0.5)
    #expect(PersonifyWrite.clampedOffset(-0.25) == -0.5)
    #expect(PersonifyWrite.setpointOffset(9)[2] == 0x0E)
    #expect(PersonifyWrite.setpointOffset(4) != PersonifyWrite.fanSpeed(.speed(3)))
}

@Test func fanSpeedMapsOfficialAutoOffAndThreeSpeeds() {
    #expect(FanSetting.auto.wireValue == 1)
    #expect(FanSetting.off.wireValue == 2)
    #expect(FanSetting.speed(1).wireValue == 3)
    #expect(FanSetting.speed(2).wireValue == 4)
    #expect(FanSetting.speed(3).wireValue == 5)
    #expect(FanSetting.speed(0).wireValue == 3)
    #expect(FanSetting.speed(8).wireValue == 5)
    #expect(FanSetting.from(wire: 1) == .auto)
    #expect(FanSetting.from(wire: 2) == .off)
    #expect(FanSetting.from(wire: 3) == .speed(1))
    #expect(FanSetting.from(wire: 4) == .speed(2))
    #expect(FanSetting.from(wire: 5) == .speed(3))
    #expect(FanSetting.from(wire: 0) == nil)
    #expect(FanSetting.from(wire: 6) == nil)
    #expect(FanSetting.from(wire: 1.4) == nil)
    #expect(Hex.encode(PersonifyWrite.fanSpeed(.auto)) == "000212000000803f")
    #expect(Hex.encode(PersonifyWrite.fanSpeed(.off)) == "0002120000000040")
    #expect(Hex.encode(PersonifyWrite.fanSpeed(.speed(1))) == "0002120000004040")
    #expect(Hex.encode(PersonifyWrite.fanSpeed(.speed(2))) == "0002120000008040")
    #expect(Hex.encode(PersonifyWrite.fanSpeed(.speed(3))) == "000212000000a040")
    #expect(PersonifyWrite.fanSpeed(.off)[0] == 0x00)
    #expect(PersonifyWrite.fanSpeed(.off)[2] == PersonifyWrite.fanField)
    #expect(FanSetting.auto.title == "Auto")
    #expect(FanSetting.off.title == "Off")
    #expect(FanSetting.speed(2).title == "2")
}

@Test func allBlindsAreEightFramesSixtyMillisecondsApartInTheCaller() {
    let frames = PersonifyWrite.allBlindsClosed(3)
    #expect(frames.count == 8)
    #expect(frames.map { $0[2] } == [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80])
    #expect(PersonifyWrite.blindClosed(number: 0, percent: 3) == nil)
    #expect(PersonifyWrite.blindClosed(number: 9, percent: 50) == nil)
    #expect(Hex.encode(PersonifyWrite.lightLevel(150)) == Hex.encode(PersonifyWrite.lightLevel(100)))
    #expect(Hex.encode(PersonifyWrite.lightLevel(-5)) == Hex.encode(PersonifyWrite.lightLevel(0)))
    #expect(PersonifyWrite.blindSequenceSpacingMilliseconds == 60)
}

@Test func signalQualityUsesTheSidebarThresholds() {
    #expect(SignalQuality.from(rssi: -40) == .veryClose)
    #expect(SignalQuality.from(rssi: -60) == .veryClose)
    #expect(SignalQuality.from(rssi: -61) == .close)
    #expect(SignalQuality.from(rssi: -70) == .close)
    #expect(SignalQuality.from(rssi: -71) == .far)
    #expect(SignalQuality.from(rssi: -80) == .far)
    #expect(SignalQuality.from(rssi: -81) == .outOfReach)
    #expect(SignalQuality.from(rssi: -95).title == "Out of reach")
    #expect(SignalQuality.veryClose.title == "Very close")
    #expect(SignalQuality.close.title == "Close")
    #expect(SignalQuality.far.title == "Far")
    #expect(SignalQuality.veryClose.barLevel > SignalQuality.close.barLevel)
    #expect(SignalQuality.close.barLevel > SignalQuality.far.barLevel)
    #expect(SignalQuality.far.barLevel > SignalQuality.outOfReach.barLevel)
}

@Test func pairingSheetStaysDownUntilACodeIsNeeded() {
    #expect(PairingFlow.initialConnect(savedPIN: "123456") == .savedPIN("123456"))
    #expect(PairingFlow.initialConnect(savedPIN: " 123456 ") == .savedPIN("123456"))
    #expect(PairingFlow.initialConnect(savedPIN: nil) == .withoutPIN)
    #expect(PairingFlow.initialConnect(savedPIN: "  ") == .withoutPIN)
    #expect(PairingFlow.sheetTrigger(savedPIN: "123456", authenticationFailed: false, deviceRequestedPIN: true) == nil)
    #expect(PairingFlow.sheetTrigger(savedPIN: nil, authenticationFailed: false, deviceRequestedPIN: true) == .pinRequired)
    #expect(PairingFlow.sheetTrigger(savedPIN: "123456", authenticationFailed: true, deviceRequestedPIN: false) == .authenticationFailed)
    #expect(PairingFlow.sheetTrigger(savedPIN: nil, authenticationFailed: false, deviceRequestedPIN: false) == nil)
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBErrorDomain", code: 14))
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBErrorDomain", code: 15))
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBATTErrorDomain", code: 5))
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBATTErrorDomain", code: 15))
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBErrorDomain", code: 6) == false)
    #expect(PairingFlow.isAuthenticationFailure(domain: "CBATTErrorDomain", code: 3) == false)
}

@Test func sliderReleaseIsDebounced() {
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(ControlDebounce.shouldSend(lastFire: nil, now: start))
    #expect(ControlDebounce.shouldSend(lastFire: start, now: start.addingTimeInterval(0.27)) == false)
    #expect(ControlDebounce.shouldSend(lastFire: start, now: start.addingTimeInterval(0.30)))
}

@Test func lastSelectedRoomIsRestoredOnlyWhenItIsInRange() {
    var list = RoomList()
    #expect(list.launchTarget(visibleIDs: ["room-a", "room-b"]) == nil)
    list.select("room-a", name: "Room A")
    list.select("room-b", name: "Room B")
    #expect(list.lastSelectedID == "room-b")
    #expect(list.launchTarget(visibleIDs: ["room-a", "room-b"]) == "room-b")
    #expect(list.launchTarget(visibleIDs: ["room-a", "room-c"]) == nil)
    let stored = try? JSONEncoder().encode(list)
    let restored = try? JSONDecoder().decode(RoomList.self, from: stored ?? Data())
    #expect(restored?.lastSelectedID == "room-b")
    #expect(restored?.lastSelectedName == "Room B")
}

@Test func favoritesAreAddedRemovedAndDoNotChangeTheLaunchRoom() throws {
    var list = RoomList()
    #expect(list.favoriteNames.isEmpty)
    list.select("room-a", name: "Room A")
    list.select("room-b", name: "Room B")
    list.setFavorite(name: "  Room A  ", true)
    #expect(list.isFavorite(name: "Room A"))
    #expect(list.launchTarget(visibleIDs: ["room-a", "room-b"]) == "room-b")
    list.setFavorite(name: "Room B", true)
    let visible = [
        RoomList.VisibleRoom(id: "room-a", name: "Room A"),
        RoomList.VisibleRoom(id: "room-b", name: "Room B"),
        RoomList.VisibleRoom(id: "room-c", name: "Room C"),
    ]
    let starred = list.sidebar(visible: visible)
    #expect(starred.favorites == ["room-b", "room-a"])
    #expect(starred.recent.isEmpty)
    #expect(starred.nearby == ["room-c"])
    list.setFavorite(name: "Room A", false)
    #expect(list.isFavorite(name: "Room A") == false)
    let after = list.sidebar(visible: visible)
    #expect(after.favorites == ["room-b"])
    #expect(after.recent == ["room-a"])
    #expect(after.nearby == ["room-c"])
    #expect(list.launchTarget(visibleIDs: ["room-a", "room-c"]) == nil)
    let legacy = Data(#"{"lastSelectedID":"room-a","pinnedIDs":["room-a"],"recentIDs":["room-a"]}"#.utf8)
    let decoded = try JSONDecoder().decode(RoomList.self, from: legacy)
    #expect(decoded.favoriteNames.isEmpty)
    #expect(decoded.lastSelectedID == "room-a")
    for index in 0..<6 {
        list.select("room-\(index)", name: "Room \(index)")
    }
    #expect(list.recentIDs.count == RoomList.recentCapacity)
    #expect(list.recentIDs.first == "room-5")
}

@Test func roomControlsResetOnSelectionAndReadTheFan() {
    var cache = ["room-a": RoomControls()]
    cache["room-a"]?.lightPercent = 100
    cache["room-a"]?.blindsClosed[1] = 15
    cache["room-a"]?.offsetCelsius = -1
    cache["room-a"]?.fanSetting = .speed(2)
    let switched = RoomControlBook.select("room-b", showing: "room-a", cache: cache)
    #expect(switched["room-a"]?.lightPercent == 100)
    #expect(switched["room-b"]?.lightPercent == nil)
    #expect(switched["room-b"]?.blindsClosed.isEmpty == true)
    #expect(switched["room-b"]?.offsetCelsius == nil)
    #expect(switched["room-b"]?.fanSetting == nil)
    let dropped = RoomControlBook.dropped("room-a", cache: switched)
    #expect(dropped["room-a"]?.lightPercent == nil)
    #expect(dropped["room-a"]?.fanSetting == .speed(2))

    var hvac = Data(count: 32)
    hvac[14] = 0x00
    hvac[15] = 0x00
    hvac[16] = 0x20
    hvac[17] = 0xC0
    hvac[18] = 0x00
    hvac[19] = 0x00
    hvac[20] = 0x00
    hvac[21] = 0x40
    hvac[27] = 0x00
    hvac[28] = 0x00
    hvac[29] = 0xB8
    hvac[30] = 0x41
    let hvacRead = RoomControlBook.apply(shortUUID: "00020001", data: hvac, to: RoomControls(), controlBusy: false)
    #expect(hvacRead.0.offsetCelsius == -2.5)
    #expect(hvacRead.0.temperatureCelsius == 23)
    #expect(hvacRead.0.fanSetting == .off)
    #expect(hvacRead.0.measuredFan == .off)
    #expect(hvacRead.unknownNote == nil)
    #expect(LiveRoomReading.fanSetting(hvac) == .off)

    var held = RoomControls()
    held.fanSetting = .speed(1)
    let busy = RoomControlBook.apply(shortUUID: "00020001", data: hvac, to: held, controlBusy: true)
    #expect(busy.0.fanSetting == .speed(1))
    #expect(busy.0.measuredFan == .off)
    #expect(busy.0.revertedToMeasured().fanSetting == .off)

    var lights = Data(count: 12)
    lights[8] = 0x00
    lights[9] = 0x00
    lights[10] = 0xC8
    lights[11] = 0x42
    let lightRead = RoomControlBook.apply(shortUUID: "00020002", data: lights, to: hvacRead.0, controlBusy: false)
    #expect(lightRead.0.lightPercent == 100)

    var blinds = Data(count: 16 * 8)
    for record in 0..<8 {
        blinds[record * 16] = 0x00
        blinds[record * 16 + 1] = 0x00
        blinds[record * 16 + 2] = 0x70
        blinds[record * 16 + 3] = 0x41
    }
    let blindRead = RoomControlBook.apply(shortUUID: "00020003", data: blinds, to: lightRead.0, controlBusy: false)
    #expect(blindRead.0.blindsClosed[1] == 15)
    #expect(blindRead.0.blindsClosed[8] == 15)
    #expect(blindRead.0.allBlindsClosed == 15)

    var mixed = blinds
    mixed[0] = 0x00
    mixed[1] = 0x00
    mixed[2] = 0xC0
    mixed[3] = 0x7F
    let nanBlind = RoomControlBook.apply(shortUUID: "00020003", data: mixed, to: blindRead.0, controlBusy: false)
    #expect(nanBlind.0.blindsClosed[1] == nil)
    #expect(nanBlind.0.blindGroups == Array(2...8))
    #expect(nanBlind.0.allBlindsClosed == 15)
    #expect(PersonifyVendor.liveStatusHandles["00020001"] == 0x1C)
    #expect(PersonifyVendor.liveStatusHandles["00020002"] == 0x1F)
    #expect(PersonifyVendor.liveStatusHandles["00020003"] == 0x22)
}

@Test func liveReadingUsesConfirmedAbsoluteBytes() {
    var hvac = Data(count: 32)
    hvac[14] = 0x00
    hvac[15] = 0x00
    hvac[16] = 0x20
    hvac[17] = 0xC0
    hvac[27] = 0x00
    hvac[28] = 0x00
    hvac[29] = 0xB8
    hvac[30] = 0x41
    #expect(LiveRoomReading.setpointOffset(hvac) == -2.5)
    #expect(LiveRoomReading.roomTemperature(hvac) == 23)
    #expect(LiveRoomReading.fanSetting(hvac) == nil)
    for (wire, setting) in [(1.0, FanSetting.auto), (2.0, .off), (3.0, .speed(1)), (4.0, .speed(2)), (5.0, .speed(3))] {
        var sample = hvac
        var bits = Float(wire).bitPattern
        for index in 0..<4 {
            sample[18 + index] = UInt8(bits & 0xFF)
            bits >>= 8
        }
        #expect(LiveRoomReading.fanSetting(sample) == setting)
    }

    var lights = Data(count: 12)
    lights[8] = 0x00
    lights[9] = 0x00
    lights[10] = 0xC8
    lights[11] = 0x42
    #expect(LiveRoomReading.lightLevel(lights) == 100)

    var blinds = Data(count: 32)
    blinds[0] = 0x00
    blinds[1] = 0x00
    blinds[2] = 0x40
    blinds[3] = 0x40
    #expect(LiveRoomReading.blindClosed(blinds).first ?? nil == 3)
}

@Test func aSingleBlindGroupTreatsNaNRecordsAsAbsent() throws {
    let six = try #require(PersonifyWrite.blindClosed(number: 1, percent: 6))
    let open = try #require(PersonifyWrite.blindClosed(number: 1, percent: 0))
    #expect(Hex.encode(six) == "020210000000c040")
    #expect(Hex.encode(open) == "0202100000000000")
    #expect(six[2] == 0x10)

    var reading = Data(count: 16 * 8)
    reading[0] = 0x00
    reading[1] = 0x00
    reading[2] = 0xC0
    reading[3] = 0x40
    for record in 1..<8 {
        reading[record * 16] = 0x00
        reading[record * 16 + 1] = 0x00
        reading[record * 16 + 2] = 0xC0
        reading[record * 16 + 3] = 0x7F
    }
    #expect(LiveRoomReading.blindGroups(reading) == [1])
    #expect(LiveRoomReading.blindClosed(reading)[0] == 6)
    let applied = RoomControlBook.apply(shortUUID: "00020003", data: reading, to: RoomControls(), controlBusy: false)
    #expect(applied.0.blindGroups == [1])
    #expect(applied.0.blindsClosed[1] == 6)
    #expect(applied.0.blindsClosed[2] == nil)
    #expect(applied.0.allBlindsClosed == 6)
    let frames = PersonifyWrite.blindsClosed(percent: 0, groups: applied.0.blindGroups ?? [])
    #expect(frames.count == 1)
    #expect(Hex.encode(frames[0]) == "0202100000000000")
    #expect(RoomControls().blindGroups == nil)
}

@Test func blindsStayUsableUntilTheGroupReadSettles() {
    #expect(BlindReadWatch.allWriteGroups(nil) == [1])
    #expect(BlindReadWatch.allWriteGroups([]) == [1])
    #expect(BlindReadWatch.allWriteGroups([1, 3]) == [1, 3])
    #expect(BlindReadWatch.showsGroupPicker(nil) == false)
    #expect(BlindReadWatch.showsGroupPicker([1]) == false)
    #expect(BlindReadWatch.showsGroupPicker([1, 2]))
    #expect(BlindReadWatch.timeout == 4)

    let first = BlindReadWatch.advance(from: .awaitingFirst, groupsKnown: false)
    #expect(first.0 == .awaitingRetry)
    #expect(first.reread)
    let second = BlindReadWatch.advance(from: first.0, groupsKnown: false)
    #expect(second.0 == .failed)
    #expect(second.reread == false)
    let arrived = BlindReadWatch.advance(from: .awaitingRetry, groupsKnown: true)
    #expect(arrived.0 == .ready)
    #expect(arrived.reread == false)
}
