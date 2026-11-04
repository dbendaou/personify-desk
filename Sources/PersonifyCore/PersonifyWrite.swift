import Foundation

/// 8-byte write to `00000004`, taken from the 2026-11-03 PacketLogger capture.
/// `[type, 0x02, field, 0x00]` followed by a little-endian float32.
public enum PersonifyWrite {
    public static let operation: UInt8 = 0x02
    public static let setpointField: UInt8 = 0x0E
    public static let lightField: UInt8 = 0x00
    /// AC fan speed. See `fanSpeed(_:)`.
    public static let fanField: UInt8 = 0x12
    public static let blindSequenceSpacingMilliseconds = 60

    public enum Target: UInt8, Sendable {
        case ac = 0x00
        case light = 0x01
        case blind = 0x02
    }

    public static func frame(type: Target, field: UInt8, value: Float) -> Data {
        let bits = value.bitPattern
        return Data([
            type.rawValue,
            operation,
            field,
            0x00,
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ])
    }

    /// Setpoint offset in °C, clamped to −3...+3 in steps of 0.5. Field 0x0E.
    public static func setpointOffset(_ celsius: Double) -> Data {
        frame(type: .ac, field: setpointField, value: Float(clampedOffset(celsius)))
    }

    public static func clampedOffset(_ celsius: Double) -> Double {
        let clamped = min(3, max(-3, celsius))
        return (clamped / 0.5).rounded() * 0.5
    }

    /// Fan on field 0x12. The float is the same value read back at 00020001 bytes 18–21.
    public static func fanSpeed(_ setting: FanSetting) -> Data {
        frame(type: .ac, field: fanField, value: setting.wireValue)
    }

    /// Light level in percent, clamped to 0...100. Field 0x00.
    public static func lightLevel(_ percent: Double) -> Data {
        let clamped = min(100, max(0, percent))
        return frame(type: .light, field: lightField, value: Float(clamped))
    }

    /// Closed percent for group `number` in 1...8. Field nibble is the 1-based group index (`number << 4`).
    public static func blindClosed(number: Int, percent: Double) -> Data? {
        guard (1...8).contains(number) else { return nil }
        let clamped = min(100, max(0, percent))
        return frame(type: .blind, field: UInt8(number << 4), value: Float(clamped))
    }

    /// One frame per existing group. Groups outside 1...8 are skipped.
    public static func blindsClosed(percent: Double, groups: [Int]) -> [Data] {
        groups.compactMap { blindClosed(number: $0, percent: percent) }
    }

    /// Eight frames, group 1 through group 8, same closed percent.
    public static func allBlindsClosed(_ percent: Double) -> [Data] {
        blindsClosed(percent: percent, groups: Array(1...8))
    }
}

/// Official fan control: Auto, Off, and speeds 1...3.
///
/// Confirmed against the official app and a 00020001 read-back. Field 0x12 writes
/// `1.0` Auto, `2.0` Off, `3.0` speed 1, `4.0` speed 2, `5.0` speed 3, and the same
/// float is stored at absolute bytes 18–21. A speed outside 1...3 is clamped before it is written.
public enum FanSetting: Equatable, Sendable {
    case auto
    case off
    case speed(Int)

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .off: return "Off"
        case .speed(let step): return "\(min(3, max(1, step)))"
        }
    }

    /// Little-endian float written to field 0x12 and read at bytes 18–21.
    public var wireValue: Float {
        switch self {
        case .auto: return 1
        case .off: return 2
        case .speed(let step):
            return Float(min(3, max(1, step)) + 2)
        }
    }

    public static func from(wire value: Float) -> FanSetting? {
        let nearest = value.rounded()
        guard abs(value - nearest) < 0.01 else { return nil }
        switch Int(nearest) {
        case 1: return .auto
        case 2: return .off
        case 3: return .speed(1)
        case 4: return .speed(2)
        case 5: return .speed(3)
        default: return nil
        }
    }
}

/// Slider releases can fire twice. A short quiet period keeps one write.
public enum ControlDebounce {
    public static let releaseInterval: TimeInterval = 0.28

    public static func shouldSend(lastFire: Date?, now: Date, interval: TimeInterval = releaseInterval) -> Bool {
        guard let lastFire else { return true }
        return now.timeIntervalSince(lastFire) >= interval
    }
}

/// Last-opened room plus the names the user starred. Favorites start empty and are never filled automatically.
public struct RoomList: Equatable, Sendable, Codable {
    public static let recentCapacity = 5

    public struct VisibleRoom: Equatable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Sidebar: Equatable, Sendable {
        public var favorites: [String]
        public var recent: [String]
        public var nearby: [String]

        public init(favorites: [String], recent: [String], nearby: [String]) {
            self.favorites = favorites
            self.recent = recent
            self.nearby = nearby
        }
    }

    public var lastSelectedID: String?
    public var lastSelectedName: String?
    /// Most recently used first.
    public var recentIDs: [String]
    /// Advertised room names, in the order they were starred.
    public var favoriteNames: [String]

    public init() {
        recentIDs = []
        favoriteNames = []
    }

    public mutating func select(_ id: String, name: String) {
        lastSelectedID = id
        lastSelectedName = name
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > Self.recentCapacity {
            recentIDs = Array(recentIDs.prefix(Self.recentCapacity))
        }
    }

    public static func favoriteKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func setFavorite(name: String, _ favorite: Bool) {
        let key = Self.favoriteKey(name)
        guard !key.isEmpty else { return }
        if favorite {
            if !favoriteNames.contains(key) { favoriteNames.append(key) }
        } else {
            favoriteNames.removeAll { $0 == key }
        }
    }

    public func isFavorite(name: String) -> Bool {
        favoriteNames.contains(Self.favoriteKey(name))
    }

    /// Last selected room when it is visible. A favorite does not change this.
    public func launchTarget(visibleIDs: [String]) -> String? {
        guard let lastSelectedID, visibleIDs.contains(lastSelectedID) else { return nil }
        return lastSelectedID
    }

    /// Favorites, then other recent rooms, then everything else still in range.
    /// The open room leads its section. A room is listed once.
    public func sidebar(visible: [VisibleRoom]) -> Sidebar {
        let favoriteIDs = orderedFavorites(visible: visible)
        let favoriteSet = Set(favoriteIDs)
        let visibleIDs = Set(visible.map(\.id))
        let recent = recentIDs.filter { visibleIDs.contains($0) && !favoriteSet.contains($0) }
        let used = favoriteSet.union(recent)
        let nearby = visible.map(\.id).filter { !used.contains($0) }
        return Sidebar(favorites: favoriteIDs, recent: recent, nearby: nearby)
    }

    private func orderedFavorites(visible: [VisibleRoom]) -> [String] {
        var result: [String] = []
        if let lastSelectedID,
           let current = visible.first(where: { $0.id == lastSelectedID }),
           isFavorite(name: current.name) {
            result.append(lastSelectedID)
        }
        for name in favoriteNames {
            for room in visible where Self.favoriteKey(room.name) == name && !result.contains(room.id) {
                result.append(room.id)
            }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case lastSelectedID
        case lastSelectedName
        case recentIDs
        case favoriteNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSelectedID = try container.decodeIfPresent(String.self, forKey: .lastSelectedID)
        lastSelectedName = try container.decodeIfPresent(String.self, forKey: .lastSelectedName)
        recentIDs = try container.decodeIfPresent([String].self, forKey: .recentIDs) ?? []
        favoriteNames = try container.decodeIfPresent([String].self, forKey: .favoriteNames) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastSelectedID, forKey: .lastSelectedID)
        try container.encodeIfPresent(lastSelectedName, forKey: .lastSelectedName)
        try container.encode(recentIDs, forKey: .recentIDs)
        try container.encode(favoriteNames, forKey: .favoriteNames)
    }
}
