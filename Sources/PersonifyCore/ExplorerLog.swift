import Dispatch
import Foundation

/// Append-only explorer log at `~/Library/Logs/PersonifyDesk/explorer-YYYYMMDD.jsonl`.
///
/// `record` returns without touching the disk. A serial queue writes the line,
/// rotates the active file once it would pass `maxFileBytes`, and deletes the
/// oldest files past `maxFileCount`.
public final class ExplorerLog: @unchecked Sendable {
    public static let defaultMaxFileBytes = 512 * 1024
    public static let defaultMaxFileCount = 4

    public static func defaultDirectory() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Logs/PersonifyDesk", isDirectory: true)
    }

    private struct Event: Sendable {
        var time: Date
        var kind: String
        var deviceID: String?
        var message: String
        var data: [String: JSONValue]
    }

    private struct Line: Encodable {
        var time: String
        var kind: String
        var deviceID: String?
        var message: String
        var data: [String: JSONValue]
    }

    private let queue = DispatchQueue(label: "com.local.personifydesk.explorer-log", qos: .utility)
    private let directory: URL
    private let maxFileBytes: Int
    private let maxFileCount: Int
    private let encoder: JSONEncoder
    /// Set on the writer queue inside `append`. Tests compare it with the caller.
    private var appendThread: Thread?

    public init(
        directory: URL,
        maxFileBytes: Int = ExplorerLog.defaultMaxFileBytes,
        maxFileCount: Int = ExplorerLog.defaultMaxFileCount
    ) {
        self.directory = directory
        self.maxFileBytes = max(1, maxFileBytes)
        self.maxFileCount = max(1, maxFileCount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    /// Queue one JSONL record. Safe to call from the main thread; the file
    /// work happens on the writer queue.
    public func record(
        time: Date = Date(),
        kind: String,
        deviceID: String? = nil,
        message: String,
        data: [String: JSONValue] = [:]
    ) {
        let event = Event(time: time, kind: kind, deviceID: deviceID, message: message, data: data)
        queue.async { [self] in
            self.append(event)
        }
    }

    /// Block until records queued before this call have been written.
    public func flush() {
        queue.sync {}
    }

    /// True when the most recent append ran on this thread. `queue.sync` can
    /// run inline, so this compares the thread stored by `append` instead.
    public func lastAppendWasOnCurrentThread() -> Bool {
        let caller = Thread.current
        return queue.sync { self.appendThread == caller }
    }

    private func append(_ event: Event) {
        let line = Line(
            time: Self.timestamp(event.time),
            kind: event.kind,
            deviceID: event.deviceID,
            message: event.message,
            data: event.data
        )
        appendThread = Thread.current
        guard var payload = try? encoder.encode(line) else { return }
        payload.append(0x0A)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let active = directory.appendingPathComponent("explorer-\(Self.dayStamp(event.time)).jsonl")
        let currentSize = fileSize(active)
        if currentSize > 0, currentSize + payload.count > maxFileBytes {
            rotate(active, now: event.time)
        }
        if !fileManager.fileExists(atPath: active.path) {
            _ = fileManager.createFile(atPath: active.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: active) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } catch {
            return
        }
        prune()
    }

    private func rotate(_ active: URL, now: Date) {
        let stamp = Self.secondStamp(now)
        var destination = directory.appendingPathComponent("explorer-\(stamp).jsonl")
        var suffix = 2
        let fileManager = FileManager.default
        while fileManager.fileExists(atPath: destination.path), suffix < 50 {
            destination = directory.appendingPathComponent("explorer-\(stamp)-\(suffix).jsonl")
            suffix += 1
        }
        try? fileManager.moveItem(at: active, to: destination)
    }

    private func prune() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let logs = urls.filter { $0.lastPathComponent.hasPrefix("explorer-") && $0.pathExtension == "jsonl" }
        guard logs.count > maxFileCount else { return }
        let sorted = logs.sorted { lhs, rhs in
            let left = modificationDate(lhs)
            let right = modificationDate(rhs)
            if left != right { return left < right }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
        for url in sorted.prefix(sorted.count - maxFileCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func fileSize(_ url: URL) -> Int {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        return size ?? 0
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func timestamp(_ date: Date) -> String {
        stamp("yyyy-MM-dd'T'HH:mm:ss'Z'", date)
    }

    private static func dayStamp(_ date: Date) -> String {
        stamp("yyyyMMdd", date)
    }

    private static func secondStamp(_ date: Date) -> String {
        stamp("yyyyMMdd-HHmmss", date)
    }

    private static func stamp(_ format: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
