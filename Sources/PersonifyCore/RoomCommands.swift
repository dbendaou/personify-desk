import Foundation

public enum LightPower: Equatable, Sendable, Codable {
    case on
    case off
    case level(Double)
}

public enum SunblindAction: Equatable, Sendable, Codable {
    case up
    case down
    case stop
    case position(Double)
}

/// Occupant actions named in public Allure, nLight, and my PERSONIFY descriptions.
/// The associated values are local requests. They are not device opcodes.
public enum RoomCommand: Equatable, Sendable, Codable {
    case setTemperatureSetpoint(celsius: Double)
    case setHVACMode(label: String)
    case setFanAuto
    case setFanSlider(unitInterval: Double)
    case setLight(groupID: Int, groupName: String, power: LightPower)
    case setSunblind(groupID: Int, groupName: String, action: SunblindAction)
    case recallScene(name: String)

    public var summary: String {
        switch self {
        case .setTemperatureSetpoint(let celsius):
            return String(format: "Temperature setpoint request %.1f °C", celsius)
        case .setHVACMode(let label):
            return "HVAC mode request \(label)"
        case .setFanAuto:
            return "Fan auto request"
        case .setFanSlider(let unitInterval):
            return String(format: "Fan slider request %.0f%%", unitInterval * 100)
        case .setLight(let groupID, let groupName, let power):
            return "Light \(groupName) (#\(groupID)) \(power.summary)"
        case .setSunblind(let groupID, let groupName, let action):
            return "Sunblind \(groupName) (#\(groupID)) \(action.summary)"
        case .recallScene(let name):
            return "Scene request \(name)"
        }
    }
}

extension LightPower {
    var summary: String {
        switch self {
        case .on: "on"
        case .off: "off"
        case .level(let value): String(format: "level %.0f%%", value * 100)
        }
    }
}

extension SunblindAction {
    var summary: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .stop: "stop"
        case .position(let value): String(format: "position %.0f%%", value * 100)
        }
    }
}

public enum EncoderStatus: String, Equatable, Sendable, Codable {
    /// No sourced byte layout exists, so nothing is written.
    case wireEncodingUnavailable
    /// A sourced layout exists and has not been checked against a capture from this device.
    case unverified
    /// Checked against a capture or a published specification for this device.
    case verified
}

public struct CommandAttempt: Equatable, Sendable {
    public var summary: String
    public var sent: Bool
    public var reason: String
    public var status: EncoderStatus

    public init(summary: String, sent: Bool, reason: String, status: EncoderStatus) {
        self.summary = summary
        self.sent = sent
        self.reason = reason
        self.status = status
    }
}

public struct UnavailableRoomEncoder: Sendable {
    public init() {}

    public static let reason =
        "No public BLE GATT encoding was found for my PERSONIFY or the Distech and nLight room devices. The request was kept on this Mac and was not written to the device."

    public func attempt(_ command: RoomCommand) -> CommandAttempt {
        CommandAttempt(
            summary: command.summary,
            sent: false,
            reason: Self.reason,
            status: .wireEncodingUnavailable
        )
    }
}
