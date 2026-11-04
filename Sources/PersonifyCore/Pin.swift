import Foundation

public enum PinValidation: Equatable, Sendable {
    case accepted(String)
    case empty
    case notNumeric
    case tooLong
}

public enum Pin {
    /// Bluetooth PIN field size in the Core Specification / IOBluetooth `BluetoothPINCode`.
    public static let maximumOctets = 16

    public static func sanitize(_ raw: String) -> String {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        return String(digits.prefix(maximumOctets))
    }

    public static func validate(_ raw: String) -> PinValidation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let separators = CharacterSet(charactersIn: " -\u{00A0}")
        let kept = trimmed.unicodeScalars.filter { !separators.contains($0) }
        if kept.isEmpty { return .empty }
        let digitsOnly = kept.allSatisfy { scalar in
            guard scalar.isASCII else { return false }
            return Character(scalar).isNumber
        }
        if !digitsOnly { return .notNumeric }
        if kept.count > maximumOctets { return .tooLong }
        return .accepted(String(String.UnicodeScalarView(kept)))
    }
}

public protocol PinStoring: Sendable {
    func load(deviceID: String) throws -> String?
    func save(_ pin: String, deviceID: String) throws
    func forget(deviceID: String) throws
    func deviceIDs() throws -> [String]
    func forgetAll() throws
}

public final class MemoryPinStore: PinStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func load(deviceID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[deviceID]
    }

    public func save(_ pin: String, deviceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[deviceID] = pin
    }

    public func forget(deviceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: deviceID)
    }

    public func deviceIDs() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.sorted()
    }

    public func forgetAll() throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}
