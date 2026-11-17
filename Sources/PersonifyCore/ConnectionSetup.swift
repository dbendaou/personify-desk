import Foundation

/// GATT traffic after a room connects.
///
/// CoreBluetooth runs one ATT procedure at a time on a peripheral. `readValue`,
/// `setNotifyValue`, and `discoverDescriptors` all share that queue, and the
/// order they are submitted is the order they finish. Fan and climate share
/// `00020001`. Lights are `00020002`. Blinds are `00020003`. Those three have
/// to be read before descriptor walks and before the larger `0001xxxx` values,
/// or the desk sits on the fan and blind tiles until the rest of the table
/// has been walked.
public enum ConnectionSetup {
    /// Short ids whose current value drives the room controls.
    public static let liveShortIDs = ["00020001", "00020002", "00020003"]

    public struct Characteristic: Equatable, Sendable {
        public var id: String
        public var shortUUID: String?
        public var readable: Bool
        public var notifies: Bool

        public init(id: String, shortUUID: String?, readable: Bool, notifies: Bool) {
            self.id = id
            self.shortUUID = shortUUID
            self.readable = readable
            self.notifies = notifies
        }
    }

    public struct ServicePlan: Equatable, Sendable {
        public var shortID: String?
        public var characteristics: [Characteristic]

        public init(shortID: String?, characteristics: [Characteristic]) {
            self.shortID = shortID
            self.characteristics = characteristics
        }
    }

    public enum Operation: Equatable, Sendable {
        /// Discover characteristics of the service at this index in the original list.
        case discoverService(Int)
        case read(String)
        case notify(String)
        case discoverDescriptors(String)
    }

    public static func isLive(_ shortUUID: String?) -> Bool {
        guard let shortUUID else { return false }
        return liveShortIDs.contains(shortUUID)
    }

    /// Live-value services first (`0002xxxx`), then the write service (`0000xxxx`).
    /// Anything else, including standard services such as Device Information, waits.
    public static func serviceRank(_ shortID: String?) -> Int {
        guard let shortID else { return 2 }
        if shortID.hasPrefix("0002") { return 0 }
        if shortID.hasPrefix("0000") { return 1 }
        return 2
    }

    public static func orderedServiceIndexes(shortIDs: [String?]) -> [Int] {
        shortIDs.indices.sorted { lhs, rhs in
            let rank = serviceRank(shortIDs[lhs])
            let other = serviceRank(shortIDs[rhs])
            if rank != other { return rank < other }
            return lhs < rhs
        }
    }

    /// Reads and notifications to submit immediately, and work that must wait
    /// until every service has been walked. Notifications follow the reads so a
    /// CCCD write cannot cut in front of the first value.
    public static func onDiscovered(_ characteristics: [Characteristic]) -> (now: [Operation], later: [Operation]) {
        var now: [Operation] = []
        var leadIDs: [String] = []
        for short in liveShortIDs {
            for item in characteristics where item.readable && item.shortUUID == short {
                leadIDs.append(item.id)
                now.append(.read(item.id))
            }
        }
        var notified: [String] = []
        for short in liveShortIDs {
            for item in characteristics where item.notifies && item.shortUUID == short && !notified.contains(item.id) {
                notified.append(item.id)
                now.append(.notify(item.id))
            }
        }
        let lead = Set(leadIDs)
        var later: [Operation] = []
        for item in characteristics where item.readable && !lead.contains(item.id) {
            later.append(.read(item.id))
        }
        for item in characteristics {
            later.append(.discoverDescriptors(item.id))
        }
        return (now, later)
    }

    /// The order the session keeps: discover a service, read any live values on it,
    /// subscribe, then move on. Bulk reads and descriptor discovery run only after that walk.
    public static func sequence(_ services: [ServicePlan]) -> [Operation] {
        var operations: [Operation] = []
        var later: [Operation] = []
        for index in orderedServiceIndexes(shortIDs: services.map(\.shortID)) {
            operations.append(.discoverService(index))
            let split = onDiscovered(services[index].characteristics)
            operations.append(contentsOf: split.now)
            later.append(contentsOf: split.later)
        }
        operations.append(contentsOf: later)
        return operations
    }
}
