import Foundation

/// Cached sidebar of rooms that are actually in range.
///
/// Advertisements arrive many times a second. The catalog remembers every
/// sighting, and it rebuilds the sorted list only when a room appears, the
/// room's name or advertisement identity changes, the room drops out of range,
/// or the displayed signal moves by a meaningful amount. Signal refreshes are
/// also held to one publish per second.
public struct RoomCatalog: Equatable, Sendable {
    /// Rooms quiet for this long leave the sidebar. Matches the old in-range cutoff.
    public static let presenceTimeout: TimeInterval = 45
    /// Upper bound on how often a signal-only change can replace the sorted list.
    public static let flushInterval: TimeInterval = 1
    /// RSSI movement, in dBm, that is worth showing even inside one signal bucket.
    public static let rssiDeadband = 5

    public enum Change: Equatable, Sendable {
        case none
        case signal
        case presence
    }

    public struct RoomSighting: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var rssi: Int
        public var lastSeen: Date

        public init(id: UUID, name: String, rssi: Int, lastSeen: Date) {
            self.id = id
            self.name = name
            self.rssi = rssi
            self.lastSeen = lastSeen
        }
    }

    public private(set) var sorted: [RoomSighting] = []

    private struct Row: Equatable, Sendable {
        var name: String
        var latestRSSI: Int
        var displayedRSSI: Int
        var lastSeen: Date
    }

    private var rows: [UUID: Row] = [:]
    private var lastSignalPublish: Date?

    public init() {}

    /// True when the sidebar should show a new signal: the bucket changed, or
    /// the reading moved by at least `rssiDeadband`.
    public static func rssiIsMeaningful(from published: Int, to current: Int) -> Bool {
        if published == current { return false }
        if SignalQuality.from(rssi: published) != SignalQuality.from(rssi: current) { return true }
        return abs(published - current) >= rssiDeadband
    }

    /// Record one advertisement. A new room, a new name, or `contentChanged`
    /// updates the cached list immediately. RSSI jitter does not.
    @discardableResult
    public mutating func note(id: UUID, name: String, rssi: Int, contentChanged: Bool, now: Date) -> Change {
        if var row = rows[id] {
            row.latestRSSI = rssi
            row.lastSeen = now
            let nameChanged = row.name != name
            if nameChanged { row.name = name }
            rows[id] = row
            if contentChanged || nameChanged {
                rows[id]?.displayedRSSI = rssi
                lastSignalPublish = now
                rebuild()
                return .signal
            }
            return .none
        }
        rows[id] = Row(name: name, latestRSSI: rssi, displayedRSSI: rssi, lastSeen: now)
        lastSignalPublish = now
        rebuild()
        return .presence
    }

    /// Drop rooms that have gone quiet, and apply at most one pending signal
    /// refresh per `flushInterval`.
    public mutating func flush(now: Date) -> Change {
        let expired = dropExpired(now: now)
        let signalAllowed = lastSignalPublish == nil || now.timeIntervalSince(lastSignalPublish!) >= Self.flushInterval
        var signaled = false
        if signalAllowed {
            for id in Array(rows.keys) {
                guard var row = rows[id] else { continue }
                guard Self.rssiIsMeaningful(from: row.displayedRSSI, to: row.latestRSSI) else { continue }
                row.displayedRSSI = row.latestRSSI
                rows[id] = row
                signaled = true
            }
            if signaled { lastSignalPublish = now }
        }
        if expired || signaled { rebuild() }
        if expired { return .presence }
        if signaled { return .signal }
        return .none
    }

    private mutating func dropExpired(now: Date) -> Bool {
        let stale = rows.filter { now.timeIntervalSince($0.value.lastSeen) >= Self.presenceTimeout }.map(\.key)
        guard !stale.isEmpty else { return false }
        for id in stale { rows[id] = nil }
        return true
    }

    private mutating func rebuild() {
        sorted = rows.map { id, row in
            RoomSighting(id: id, name: row.name, rssi: row.displayedRSSI, lastSeen: row.lastSeen)
        }
        .sorted { lhs, rhs in
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
