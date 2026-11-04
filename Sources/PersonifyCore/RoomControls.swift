import Foundation

/// What the desk is allowed to show for one room. Nil means the device has not reported that field.
public struct RoomControls: Equatable, Sendable {
    public var lightPercent: Double?
    public var offsetCelsius: Double?
    public var fanSetting: FanSetting?
    /// Last fan reported by 00020001, including while a write is still in flight.
    public var measuredFan: FanSetting?
    public var blindsClosed: [Int: Double]
    /// nil until 00020003 has been read. Then the 1-based groups that are not NaN.
    public var blindGroups: [Int]?
    /// Slider position used before a group read, and for All when groups differ.
    public var blindDraftPercent: Double = 0
    public var temperatureCelsius: Double?
    public var measuredLight: Double?
    public var measuredOffset: Double?
    public var measuredBlinds: [Int: Double]
    /// True after a live status characteristic has been applied for this connection.
    public var hasLiveRead = false

    public init() {
        blindsClosed = [:]
        measuredBlinds = [:]
    }

    /// Known when every existing group has a percent and they match.
    public var allBlindsClosed: Double? {
        guard let groups = blindGroups, !groups.isEmpty else { return nil }
        let values = groups.compactMap { blindsClosed[$0] }
        guard values.count == groups.count, let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    public func revertedToMeasured() -> RoomControls {
        var copy = self
        copy.lightPercent = measuredLight
        copy.offsetCelsius = measuredOffset
        copy.blindsClosed = measuredBlinds
        copy.fanSetting = measuredFan
        return copy
    }
}

public enum RoomControlBook {
    /// The room being opened starts unknown so another room's sliders cannot carry over.
    public static func select(_ id: String, showing: String?, cache: [String: RoomControls]) -> [String: RoomControls] {
        var cache = cache
        if showing != id {
            cache[id] = cleared(keepingFan: cache[id])
        }
        return cache
    }

    public static func dropped(_ id: String, cache: [String: RoomControls]) -> [String: RoomControls] {
        var cache = cache
        cache[id] = cleared(keepingFan: cache[id])
        return cache
    }

    /// The last fan stays so a reconnect does not flash empty before the next 00020001 read.
    private static func cleared(keepingFan previous: RoomControls?) -> RoomControls {
        var fresh = RoomControls()
        fresh.fanSetting = previous?.fanSetting
        fresh.measuredFan = previous?.measuredFan
        fresh.blindDraftPercent = previous?.blindDraftPercent ?? 0
        return fresh
    }

    /// Fills the fields whose bytes are confirmed. Fan is the float at 00020001 bytes 18–21.
    public static func apply(shortUUID: String, data: Data, to controls: RoomControls, controlBusy: Bool) -> (RoomControls, unknownNote: String?) {
        var controls = controls
        switch shortUUID {
        case "00020001":
            controls.hasLiveRead = true
            if let temperature = LiveRoomReading.roomTemperature(data) {
                controls.temperatureCelsius = temperature
            }
            if let offset = LiveRoomReading.setpointOffset(data) {
                controls.measuredOffset = offset
                if !controlBusy { controls.offsetCelsius = offset }
            }
            if let fan = LiveRoomReading.fanSetting(data) {
                controls.measuredFan = fan
                if !controlBusy { controls.fanSetting = fan }
            }
            return (controls, nil)
        case "00020002":
            controls.hasLiveRead = true
            if let level = LiveRoomReading.lightLevel(data) {
                controls.measuredLight = level
                if !controlBusy { controls.lightPercent = level }
            }
            return (controls, nil)
        case "00020003":
            controls.hasLiveRead = true
            let readings = LiveRoomReading.blindClosed(data)
            let groups = LiveRoomReading.blindGroups(data)
            controls.blindGroups = groups
            let present = Set(groups)
            for (index, value) in readings.enumerated() {
                let number = index + 1
                if let value, present.contains(number) {
                    controls.measuredBlinds[number] = value
                    if !controlBusy { controls.blindsClosed[number] = value }
                } else {
                    controls.measuredBlinds.removeValue(forKey: number)
                    if !controlBusy { controls.blindsClosed.removeValue(forKey: number) }
                }
            }
            return (controls, nil)
        default:
            return (controls, nil)
        }
    }
}

/// How the desk treats blinds before and after the group list is known.
public enum BlindReadWatch: Equatable, Sendable {
    /// No read has been asked for yet.
    case idle
    /// The first explicit read is in flight.
    case awaitingFirst
    /// The one automatic retry is in flight.
    case awaitingRetry
    /// Groups were read.
    case ready
    /// The read did not arrive. The All control still works.
    case failed

    public static let timeout: TimeInterval = 4

    /// Groups written by All. Until a read names them, All sends group 1 only.
    public static func allWriteGroups(_ known: [Int]?) -> [Int] {
        guard let known, !known.isEmpty else { return [1] }
        return known
    }

    public static func showsGroupPicker(_ known: [Int]?) -> Bool {
        (known?.count ?? 0) > 1
    }

    /// A missing or failed read retries once, then stops. The controls stay usable either way.
    public static func advance(from state: BlindReadWatch, groupsKnown: Bool) -> (BlindReadWatch, reread: Bool) {
        if groupsKnown { return (.ready, false) }
        switch state {
        case .idle, .awaitingFirst:
            return (.awaitingRetry, true)
        case .awaitingRetry, .failed, .ready:
            return (.failed, false)
        }
    }
}
