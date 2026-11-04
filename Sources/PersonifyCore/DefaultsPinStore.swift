import Foundation

/// Pairing codes for this Mac, kept in UserDefaults and cached in memory.
/// The building PIN is not a secret, so it does not go through the login Keychain.
public final class DefaultsPinStore: PinStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: String]
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "personifydesk.pairingPins") {
        self.defaults = defaults
        self.key = key
        if let stored = defaults.dictionary(forKey: key) as? [String: String] {
            cache = stored
        } else {
            cache = [:]
        }
    }

    public func load(deviceID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[deviceID]
    }

    public func save(_ pin: String, deviceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        cache[deviceID] = pin
        persist()
    }

    public func forget(deviceID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: deviceID)
        persist()
    }

    public func deviceIDs() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return cache.keys.sorted()
    }

    public func forgetAll() throws {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        persist()
    }

    /// Used by the one-time migration. Does nothing when this device already has a code.
    public func importMigrated(_ values: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for (deviceID, pin) in values where cache[deviceID] == nil && !pin.isEmpty {
            cache[deviceID] = pin
            changed = true
        }
        if changed { persist() }
    }

    private func persist() {
        defaults.set(cache, forKey: key)
    }
}
