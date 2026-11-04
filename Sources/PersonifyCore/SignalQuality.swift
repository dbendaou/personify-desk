import Foundation

/// Distance words for a BLE RSSI in dBm, shown beside the signal bars.
/// Very close is −60 or stronger, Close is −70 or stronger, Far is −80 or stronger, and anything weaker is Out of reach.
public enum SignalQuality: String, Equatable, Sendable {
    case veryClose
    case close
    case far
    case outOfReach

    public var title: String {
        switch self {
        case .veryClose: "Very close"
        case .close: "Close"
        case .far: "Far"
        case .outOfReach: "Out of reach"
        }
    }

    /// 0...1 for an SF Symbol such as `cellularbars`.
    public var barLevel: Double {
        switch self {
        case .veryClose: 1
        case .close: 0.75
        case .far: 0.5
        case .outOfReach: 0.25
        }
    }

    public static func from(rssi: Int) -> SignalQuality {
        if rssi >= -60 { return .veryClose }
        if rssi >= -70 { return .close }
        if rssi >= -80 { return .far }
        return .outOfReach
    }
}
