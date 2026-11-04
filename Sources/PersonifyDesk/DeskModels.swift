import Foundation
import PersonifyCore

enum ConnectForm {
    /// Starting text when this Mac has no saved code for the device.
    /// The operator asked for this editable suggestion. It is not sent until they connect.
    static let unsavedSuggestion = "999996"
}

enum AppVersion {
    static let current = "1.0.0"
}

enum DeskSection: String, CaseIterable, Identifiable, Hashable {
    case rooms
    case explorer
    case notes
    case controller

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rooms: "Rooms"
        case .explorer: "Explorer"
        case .notes: "Notes"
        case .controller: "Controller record"
        }
    }

    var symbol: String {
        switch self {
        case .rooms: "square.grid.2x2.fill"
        case .explorer: "dot.radiowaves.left.and.right"
        case .notes: "text.book.closed"
        case .controller: "doc.text"
        }
    }

    var developer: Bool { self != .rooms }
}

enum RoomLink: Equatable {
    case notConnected
    case connecting
    case findingControls
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .notConnected: "Not connected"
        case .connecting: "Connecting…"
        case .findingControls: "Finding controls…"
        case .ready: "Connected"
        case .failed: "Couldn't connect"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .connecting, .findingControls: "antenna.radiowaves.left.and.right"
        case .notConnected: "circle"
        }
    }

    /// Detail for the red banner. Progress and the normal disconnected state stay in the header only.
    var errorDetail: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

enum BluetoothPhase: Equatable {
    case starting
    case ready
    case poweredOff
    case unauthorized
    case unsupported
    case resetting
}

enum LinkState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var peripheralName: String?
    var advertisement: Advertisement
    var rssi: Int
    var connectable: Bool
    var lastSeen: Date
    var lastRSSIEvent: Date?
    var link: LinkState

    var displayName: String {
        advertisement.localName ?? peripheralName ?? "Unnamed device"
    }

    var recognition: RoomRecognition {
        RoomRecognition.evaluate(
            name: displayName,
            serviceUUIDs: advertisement.serviceUUIDs,
            companyIDs: advertisement.manufacturerRecords.map(\.companyID)
        )
    }
}

enum CapturePhase: Equatable {
    case idle
    case baseline
    case compare
}

struct DeviceValueSnapshot: Identifiable, Equatable {
    var id = UUID()
    var takenAt = Date()
    var label: String
    var values: [String: Data]
}

struct PendingWrite: Equatable {
    var characteristicID: String
    var uuid: String
    var frames: [Data]
    var spacingMilliseconds: Int

    var hex: String {
        frames.map { Hex.encode($0, spaced: true) }.joined(separator: "\n")
    }
}

struct LocalGroup: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
}

struct GATTCharNode: Identifiable, Equatable {
    var id: String
    var uuid: String
    var properties: [String]
    var propertyMask: UInt
    var descriptors: [String]
    var value: Data?
    var notifying: Bool
    var status: String?

    var title: String {
        AssignedNumbers.characteristicName(uuid: uuid) ?? "Vendor characteristic"
    }

    var canRead: Bool { propertyMask & 0x02 != 0 }
    var canWrite: Bool { propertyMask & 0x08 != 0 }
    var canWriteWithoutResponse: Bool { propertyMask & 0x04 != 0 }
    var canSubscribe: Bool { propertyMask & 0x30 != 0 }
}

struct GATTServiceNode: Identifiable, Equatable {
    var id: String
    var uuid: String
    var characteristics: [GATTCharNode]

    var title: String {
        AssignedNumbers.serviceName(uuid: uuid) ?? "Vendor service"
    }
}

struct SavedLayout: Codable {
    var lights: [LocalGroup]
    var blinds: [LocalGroup]
}
