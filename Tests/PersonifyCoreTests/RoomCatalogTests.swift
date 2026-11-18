import Foundation
import Testing

@testable import PersonifyCore

@Test func rssiInsideOneBucketAndUnderTheDeadbandIsIgnored() {
    #expect(RoomCatalog.rssiIsMeaningful(from: -66, to: -69) == false)
    #expect(RoomCatalog.rssiIsMeaningful(from: -55, to: -59) == false)
    #expect(RoomCatalog.rssiIsMeaningful(from: -66, to: -66) == false)
    #expect(RoomCatalog.rssiIsMeaningful(from: -55, to: -50))
    #expect(RoomCatalog.rssiIsMeaningful(from: -70, to: -71))
    #expect(RoomCatalog.rssiIsMeaningful(from: -80, to: -81))
    #expect(RoomCatalog.rssiIsMeaningful(from: -66, to: -71))
}

@Test func roomListIsCachedAcrossAdvertisementJitterAndSortedOncePerPublish() {
    var catalog = RoomCatalog()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let atlas = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let borealis = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let cedar = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    #expect(catalog.note(id: borealis, name: "Borealis", rssi: -66, contentChanged: true, now: start) == .presence)
    #expect(catalog.note(id: atlas, name: "Atlas", rssi: -66, contentChanged: true, now: start) == .presence)
    #expect(catalog.note(id: cedar, name: "Cedar Room", rssi: -80, contentChanged: false, now: start) == .presence)
    #expect(catalog.sorted.map(\.name) == ["Atlas", "Borealis", "Cedar Room"])

    var published = 0
    for step in 0..<40 {
        let when = start.addingTimeInterval(Double(step) * 0.05)
        for (id, name) in [(atlas, "Atlas"), (borealis, "Borealis"), (cedar, "Cedar Room")] {
            let rssi = (id == cedar) ? -80 + (step % 3) - 1 : -66 + (step % 3) - 1
            let change = catalog.note(id: id, name: name, rssi: rssi, contentChanged: false, now: when)
            if change != .none { published += 1 }
        }
    }
    #expect(published == 0)
    #expect(catalog.sorted.map(\.rssi) == [-66, -66, -80])
    #expect(catalog.flush(now: start.addingTimeInterval(0.4)) == .none)
    #expect(catalog.sorted.map(\.rssi) == [-66, -66, -80])
}

@Test func aMeaningfulSignalPublishesAtMostOncePerSecondAndKeepsTheLatestReading() {
    var catalog = RoomCatalog()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let room = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    #expect(catalog.note(id: room, name: "SDR1 411", rssi: -66, contentChanged: false, now: start) == .presence)

    #expect(catalog.note(id: room, name: "SDR1 411", rssi: -72, contentChanged: false, now: start.addingTimeInterval(0.2)) == .none)
    #expect(catalog.flush(now: start.addingTimeInterval(0.5)) == .none)
    #expect(catalog.sorted.map(\.rssi) == [-66])

    #expect(catalog.note(id: room, name: "SDR1 411", rssi: -74, contentChanged: false, now: start.addingTimeInterval(0.8)) == .none)
    #expect(catalog.flush(now: start.addingTimeInterval(1.0)) == .signal)
    #expect(catalog.sorted.map(\.rssi) == [-74])

    #expect(catalog.note(id: room, name: "SDR1 411", rssi: -88, contentChanged: false, now: start.addingTimeInterval(1.2)) == .none)
    #expect(catalog.flush(now: start.addingTimeInterval(1.4)) == .none)
    #expect(catalog.sorted.map(\.rssi) == [-74])
    #expect(catalog.flush(now: start.addingTimeInterval(2.0)) == .signal)
    #expect(catalog.sorted.map(\.rssi) == [-88])
}

@Test func aRoomNameChangePublishesImmediatelyAndAQuietRoomDropsOut() {
    var catalog = RoomCatalog()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let room = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    let other = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    catalog.note(id: room, name: "OpenSp 2 MAZA", rssi: -70, contentChanged: false, now: start)
    catalog.note(id: other, name: "SDR1 411", rssi: -62, contentChanged: false, now: start)

    let renamed = catalog.note(id: room, name: "Open Space 2", rssi: -71, contentChanged: false, now: start.addingTimeInterval(0.2))
    #expect(renamed == .signal)
    #expect(catalog.sorted.map(\.name) == ["SDR1 411", "Open Space 2"])

    catalog.note(id: other, name: "SDR1 411", rssi: -62, contentChanged: false, now: start.addingTimeInterval(40))
    #expect(catalog.flush(now: start.addingTimeInterval(45.1)) == .none)
    #expect(catalog.sorted.map(\.id) == [other, room])
    #expect(catalog.flush(now: start.addingTimeInterval(45.2)) == .presence)
    #expect(catalog.sorted.map(\.id) == [other])
    #expect(catalog.flush(now: start.addingTimeInterval(85)) == .presence)
    #expect(catalog.sorted.isEmpty)
}

@Test func elevenRoomsJitteringDoesNotRebuildTheCachedOrder() {
    var catalog = RoomCatalog()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let ids = (0..<11).map { index in
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }
    for (index, id) in ids.enumerated() {
        let change = catalog.note(id: id, name: "Room \(index)", rssi: -50, contentChanged: false, now: start)
        #expect(change == .presence)
    }
    let cached = catalog.sorted
    for step in 1...50 {
        let when = start.addingTimeInterval(Double(step) * 0.02)
        for (index, id) in ids.enumerated() {
            let change = catalog.note(id: id, name: "Room \(index)", rssi: -50 + (step % 3) - 1, contentChanged: false, now: when)
            #expect(change == .none)
        }
    }
    #expect(catalog.sorted == cached)
    #expect(catalog.flush(now: start.addingTimeInterval(0.5)) == .none)
    for (index, id) in ids.enumerated() {
        catalog.note(id: id, name: "Room \(index)", rssi: -40, contentChanged: false, now: start.addingTimeInterval(0.8))
    }
    #expect(catalog.flush(now: start.addingTimeInterval(1)) == .signal)
    #expect(catalog.sorted.map(\.rssi).allSatisfy { $0 == -40 })
    let names = catalog.sorted.map(\.name)
    #expect(names.count == 11)
    for pair in zip(names, names.dropFirst()) {
        #expect(pair.0.localizedStandardCompare(pair.1) != .orderedDescending)
    }
}
