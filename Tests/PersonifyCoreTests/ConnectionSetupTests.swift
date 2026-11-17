import Testing
@testable import PersonifyCore

@Test func liveFanAndBlindReadsAreNotBehindTheRestOfTheTable() {
    let services = [
        ConnectionSetup.ServicePlan(shortID: "00010000", characteristics: [
            .init(id: "config", shortUUID: "00010001", readable: true, notifies: false),
            .init(id: "names", shortUUID: "00010002", readable: true, notifies: false),
        ]),
        ConnectionSetup.ServicePlan(shortID: "00020000", characteristics: [
            .init(id: "hvac", shortUUID: "00020001", readable: true, notifies: true),
            .init(id: "lights", shortUUID: "00020002", readable: true, notifies: true),
            .init(id: "blinds", shortUUID: "00020003", readable: true, notifies: false),
            .init(id: "extra", shortUUID: "00020004", readable: true, notifies: false),
        ]),
        ConnectionSetup.ServicePlan(shortID: "00000000", characteristics: [
            .init(id: "write", shortUUID: "00000004", readable: false, notifies: false),
        ]),
        ConnectionSetup.ServicePlan(shortID: nil, characteristics: [
            .init(id: "manufacturer", shortUUID: nil, readable: true, notifies: false),
        ]),
    ]

    #expect(ConnectionSetup.orderedServiceIndexes(shortIDs: services.map(\.shortID)) == [1, 2, 0, 3])

    let ops = ConnectionSetup.sequence(services)
    #expect(Array(ops.prefix(7)) == [
        .discoverService(1),
        .read("hvac"),
        .read("lights"),
        .read("blinds"),
        .notify("hvac"),
        .notify("lights"),
        .discoverService(2),
    ])

    func index(of operation: ConnectionSetup.Operation) -> Int {
        ops.firstIndex(of: operation) ?? -1
    }

    let blinds = index(of: .read("blinds"))
    #expect(blinds > 0)
    #expect(index(of: .read("hvac")) < blinds)
    #expect(blinds < index(of: .read("config")))
    #expect(blinds < index(of: .read("names")))
    #expect(blinds < index(of: .read("extra")))
    #expect(blinds < index(of: .read("manufacturer")))
    #expect(blinds < index(of: .discoverDescriptors("hvac")))
    #expect(blinds < index(of: .discoverDescriptors("blinds")))
    #expect(index(of: .discoverService(2)) < index(of: .discoverService(0)))
    #expect(ops.contains(.read("write")) == false)
}

@Test func aServiceWithoutLiveValuesDoesNotReadAheadOfFanOrBlinds() {
    let split = ConnectionSetup.onDiscovered([
        .init(id: "names", shortUUID: "00010002", readable: true, notifies: false),
        .init(id: "blinds", shortUUID: "00020003", readable: true, notifies: true),
        .init(id: "hvac", shortUUID: "00020001", readable: true, notifies: false),
    ])
    #expect(split.now == [
        .read("hvac"),
        .read("blinds"),
        .notify("blinds"),
    ])
    #expect(split.later.first == .read("names"))
}

@Test func blindChipsStayHiddenUntilTheRoomReportsSeveralGroups() {
    #expect(BlindReadWatch.pickerGroups(nil) == [])
    #expect(BlindReadWatch.pickerGroups([]) == [])
    #expect(BlindReadWatch.pickerGroups([1]) == [])
    #expect(BlindReadWatch.pickerGroups([4, 1]) == [4, 1])
    #expect(RoomActionGate.fanEnabled(settingKnown: false))
    #expect(RoomActionGate.blindMotionEnabled(groupsKnown: false, percentKnown: false))
    #expect(BlindReadWatch.allWriteGroups(nil) == [1])
}
