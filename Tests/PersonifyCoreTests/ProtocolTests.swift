import Foundation
import Testing

@testable import PersonifyCore

@Test func hexRoundTripAndPrefixes() throws {
    let data = Data([0x0D, 0x18, 0xFF])
    #expect(Hex.encode(data) == "0d18ff")
    #expect(Hex.encode(data, spaced: true) == "0d 18 ff")
    #expect(try Hex.decode("0d18ff") == data)
    #expect(try Hex.decode("0x0D 0x18, 0xFF") == data)
    #expect(try Hex.decode("") == Data())
    #expect(throws: HexError.oddLength) { try Hex.decode("abc") }
    #expect(throws: HexError.self) { try Hex.decode("zz") }
}

@Test func advertisementPrimerVector() {
    let bytes = Data([
        0x02, 0x01, 0x06,
        0x03, 0x03, 0x0D, 0x18,
        0x06, 0x09, 0x50, 0x75, 0x6C, 0x73, 0x65,
        0x05, 0xFF, 0x59, 0x00, 0x01, 0x02,
    ])
    let advertisement = Advertisement.parse(adStructures: bytes)
    #expect(advertisement.warnings.isEmpty)
    #expect(advertisement.localName == "Pulse")
    #expect(advertisement.flags?.leGeneralDiscoverable == true)
    #expect(advertisement.flags?.leLimitedDiscoverable == false)
    #expect(advertisement.flags?.brEdrNotSupported == true)
    #expect(advertisement.serviceUUIDs == ["180D"])
    #expect(advertisement.manufacturerRecords.count == 1)
    #expect(advertisement.manufacturerRecords[0].companyID == 0x0059)
    #expect(advertisement.manufacturerRecords[0].companyName == "Nordic Semiconductor")
    #expect(advertisement.manufacturerRecords[0].payloadHex == "0102")
    #expect(advertisement.manufacturerRecords[0].iBeacon == nil)
}

@Test func advertisementKeepsEarlierFieldsWhenTruncated() {
    let bytes = Data([0x02, 0x01, 0x06, 0x05, 0x09, 0x41])
    let advertisement = Advertisement.parse(adStructures: bytes)
    #expect(advertisement.flags?.raw == 0x06)
    #expect(advertisement.warnings.contains { $0.contains("truncated") })
}

@Test func littleEndian128BitUUIDAndIBeacon() {
    var bytes = Data([0x11, 0x07])
    let littleEndian = Data([
        0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88,
        0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00,
    ])
    bytes.append(littleEndian)
    let advertisement = Advertisement.parse(adStructures: bytes)
    #expect(advertisement.serviceUUIDs == ["00112233-4455-6677-8899-AABBCCDDEEFF"])

    var manufacturer = Data([0x1A, 0xFF, 0x4C, 0x00, 0x02, 0x15])
    manufacturer.append(Data([
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    ]))
    manufacturer.append(contentsOf: [0x00, 0x01, 0x00, 0x02, 0xC5])
    let parsed = Advertisement.parse(adStructures: manufacturer)
    let beacon = parsed.manufacturerRecords.first?.iBeacon
    #expect(beacon?.uuid == "00112233-4455-6677-8899-AABBCCDDEEFF")
    #expect(beacon?.major == 1)
    #expect(beacon?.minor == 2)
    #expect(beacon?.measuredPower == -59)
    #expect(parsed.manufacturerRecords.first?.companyName == "Apple, Inc.")
}

@Test func sigDecodersUsePublishedLayouts() {
    let temperature = SIGDecoder.decode(uuid: "00002A6E-0000-1000-8000-00805F9B34FB", data: Data([0x2E, 0x09]))
    #expect(temperature?.summary == "23.50 °C")
    let cold = SIGDecoder.decode(uuid: "2A6E", data: Data([0x83, 0xFF]))
    #expect(cold?.summary == "-1.25 °C")
    let unknownTemperature = SIGDecoder.decode(uuid: "2A6E", data: Data([0x00, 0x80]))
    #expect(unknownTemperature?.summary == "value is not known")
    let humidity = SIGDecoder.decode(uuid: "2A6F", data: Data([0x8E, 0x12]))
    #expect(humidity?.summary == "47.50 %")
    let unknownHumidity = SIGDecoder.decode(uuid: "2A6F", data: Data([0xFF, 0xFF]))
    #expect(unknownHumidity?.summary == "value is not known")
    let battery = SIGDecoder.decode(uuid: "2A19", data: Data([87]))
    #expect(battery?.summary == "87%")
    let light = SIGDecoder.decode(uuid: "2AFB", data: Data([0xD2, 0x04, 0x00]))
    #expect(light?.summary == "12.34 lx")
    let name = SIGDecoder.decode(uuid: "2A29", data: Data("Distech Controls".utf8))
    #expect(name?.summary == "Distech Controls")
    #expect(SIGDecoder.decode(uuid: "2A6E", data: Data([0x01])) == nil)
    #expect(AssignedNumbers.serviceName(uuid: "0000180A-0000-1000-8000-00805F9B34FB") == "Device Information")
    #expect(AssignedNumbers.characteristicName(uuid: "2A6E") == "Temperature")
    #expect(bluetoothAlias("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") == "AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE")
}

@Test func propertyNamesFollowTheCoreAndCoreBluetoothBits() {
    #expect(GATTProperties.names(mask: 0x12) == ["read", "notify"])
    #expect(GATTProperties.names(mask: 0x08) == ["write"])
    #expect(GATTProperties.names(mask: 0x100) == ["notify-encryption-required"])
}

@Test func pinsAreOrdinaryDigitStrings() {
    #expect(Pin.validate("999995") == .accepted("999995"))
    #expect(Pin.validate("999996") == .accepted("999996"))
    #expect(Pin.validate("123456") == .accepted("123456"))
    #expect(Pin.validate("1234") == .accepted("1234"))
    #expect(Pin.validate("42") == .accepted("42"))
    #expect(Pin.validate(" 999-995 ") == .accepted("999995"))
    #expect(Pin.validate("12ab") == .notNumeric)
    #expect(Pin.validate("") == .empty)
    #expect(Pin.validate("   ") == .empty)
    #expect(Pin.validate(String(repeating: "1", count: 17)) == .tooLong)
    #expect(Pin.sanitize("999-996") == "999996")
    #expect(Pin.sanitize("ab12cd34") == "1234")
}

@Test func defaultsPinStoreKeepsCodesInTheGivenDefaults() throws {
    let suite = "personifydesk.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let store = DefaultsPinStore(defaults: defaults)
    try store.save("123456", deviceID: "desk-a")
    let reloaded = DefaultsPinStore(defaults: defaults)
    #expect(try reloaded.load(deviceID: "desk-a") == "123456")
    #expect(try reloaded.load(deviceID: "missing") == nil)
    try reloaded.forget(deviceID: "desk-a")
    #expect(try DefaultsPinStore(defaults: defaults).deviceIDs().isEmpty)
    defaults.removePersistentDomain(forName: suite)
}

@Test func memoryPinStoreRemembersPerDevice() throws {
    let store = MemoryPinStore()
    try store.save("123456", deviceID: "desk-a")
    try store.save("654321", deviceID: "desk-b")
    #expect(try store.load(deviceID: "desk-a") == "123456")
    try store.forget(deviceID: "desk-a")
    #expect(try store.load(deviceID: "desk-a") == nil)
    #expect(try store.deviceIDs() == ["desk-b"])
    try store.forgetAll()
    #expect(try store.deviceIDs().isEmpty)
}

@Test func nameHeuristicUsesProductWordsOnly() {
    #expect(RoomNameHeuristic.match("Allure UNITOUCH").matchedTerms.contains("unitouch"))
    #expect(RoomNameHeuristic.match("Allure UNITOUCH").matchedTerms.contains("allure"))
    #expect(RoomNameHeuristic.match("ECY-STAT-R-W-WB").isLikelyRoomDevice)
    #expect(RoomNameHeuristic.match("Lounge").isLikelyRoomDevice == false)
    #expect(RoomNameHeuristic.match(nil).matchedTerms.isEmpty)
}

@Test func addressCacheFindsASyntheticPeripheralEntry() {
    let plist: [String: Any] = [
        "CoreBluetoothCache": [
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE": [
                "DeviceAddress": "aa:bb:cc:dd:ee:ff",
                "Name": "Lounge",
            ],
        ],
    ]
    let address = BluetoothAddressCache.address(
        forPeripheralUUID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        in: plist
    )
    #expect(address == "AA-BB-CC-DD-EE-FF")
    #expect(BluetoothAddressCache.normalizeAddress("not-a-mac") == nil)
}

@Test func controllerJSONAndXMLMatchThePublishedShape() throws {
    let json = """
    {
      "resourceIndex": 2,
      "subnetId": 10,
      "name": "Room Device 2",
      "roomName": "Lounge",
      "modelType": 0,
      "bluetoothMode": 2,
      "pinCode": "246813",
      "uuid": "74be2bd-47e1-5995-889b-4f0316eed60a",
      "spaceOwners": ["Admin", "Operator"],
      "lightGroups": [
        {"id": 1, "index": 0, "name": "Group1", "displayName": "Ceiling", "enabled": true},
        {"id": 2, "index": 3, "name": "Group2", "displayName": "Wall", "enabled": false}
      ],
      "sunBlindGroups": [
        {"id": 3, "index": 2, "name": "Group3", "displayName": "West", "enabled": "true"}
      ]
    }
    """.data(using: .utf8)!
    let jsonDevices = try ControllerDocument.parse(json)
    #expect(jsonDevices.count == 1)
    #expect(jsonDevices[0].bluetoothMode == .commissioning)
    #expect(jsonDevices[0].modelType == .unitouch)
    #expect(jsonDevices[0].pinCode == "246813")
    #expect(jsonDevices[0].lightGroups.map(\.displayName) == ["Ceiling", "Wall"])
    #expect(jsonDevices[0].sunBlindGroups[0].enabled == true)
    #expect(jsonDevices[0].beaconNetworkUUID == "74be2bd-47e1-5995-889b-4f0316eed60a")

    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <BleRoomDevices>
      <BleRoomDevice>
        <ResourceIndex>1</ResourceIndex>
        <SubnetId>1</SubnetId>
        <Name>Room Device 1</Name>
        <RoomName>MS1</RoomName>
        <ModelType>100</ModelType>
        <BluetoothMode>3</BluetoothMode>
        <PinCode>999996</PinCode>
        <SpaceOwners />
        <LightGroups />
        <SunBlindGroups />
      </BleRoomDevice>
      <BleRoomDevice>
        <ResourceIndex>4</ResourceIndex>
        <SubnetId>3</SubnetId>
        <Name>Room Device 3</Name>
        <RoomName>Room Device 3</RoomName>
        <ModelType>4</ModelType>
        <BluetoothMode>4</BluetoothMode>
        <PinCode>1234567</PinCode>
        <LightGroups>
          <LightGroup>
            <Id>1</Id>
            <Index>0</Index>
            <Name>Group1</Name>
            <DisplayName>Group1</DisplayName>
            <Enabled>true</Enabled>
          </LightGroup>
        </LightGroups>
        <SunBlindGroups>
          <SunBlindGroup>
            <Id>3</Id>
            <Index>2</Index>
            <Name>Group3</Name>
            <DisplayName>Group3</DisplayName>
            <Enabled>true</Enabled>
          </SunBlindGroup>
        </SunBlindGroups>
      </BleRoomDevice>
    </BleRoomDevices>
    """.data(using: .utf8)!
    let xmlDevices = try ControllerDocument.parse(xml)
    #expect(xmlDevices.count == 2)
    #expect(xmlDevices[0].modelType == .undocumented(100))
    #expect(xmlDevices[0].bluetoothMode == .privateMode)
    #expect(xmlDevices[0].pinCode == "999996")
    #expect(xmlDevices[1].modelType == .ecMultiSensorBLE)
    #expect(xmlDevices[1].bluetoothMode == .undocumented(4))
    #expect(xmlDevices[1].lightGroups.count == 1)
    #expect(xmlDevices[1].sunBlindGroups[0].id == 3)

    let summary = try JSONEncoder().encode(jsonDevices[0].publicSummary())
    let summaryText = String(decoding: summary, as: UTF8.self)
    #expect(!summaryText.contains("246813"))
    #expect(!summaryText.contains("pinCode"))
}

@Test func roomCommandsAreRecordedAndNotEncoded() {
    let commands: [RoomCommand] = [
        .setTemperatureSetpoint(celsius: 21.5),
        .setHVACMode(label: "Heating"),
        .setFanAuto,
        .setFanSlider(unitInterval: 0.4),
        .setLight(groupID: 1, groupName: "Ceiling", power: .on),
        .setLight(groupID: 1, groupName: "Ceiling", power: .off),
        .setLight(groupID: 2, groupName: "Wall", power: .level(0.25)),
        .setSunblind(groupID: 3, groupName: "West", action: .up),
        .setSunblind(groupID: 3, groupName: "West", action: .down),
        .setSunblind(groupID: 3, groupName: "West", action: .stop),
        .setSunblind(groupID: 3, groupName: "West", action: .position(0.5)),
        .recallScene(name: "Meeting"),
    ]
    let encoder = UnavailableRoomEncoder()
    for command in commands {
        let attempt = encoder.attempt(command)
        #expect(attempt.sent == false)
        #expect(attempt.status == .wireEncodingUnavailable)
        #expect(attempt.reason == UnavailableRoomEncoder.reason)
        #expect(!attempt.summary.isEmpty)
    }
    #expect(!UnavailableRoomEncoder.reason.contains("999995"))
    #expect(!UnavailableRoomEncoder.reason.contains("999996"))
}

