import Foundation
import Testing

@testable import PersonifyCore

@Test func explorerLogWritesOffTheCallerAndRotatesPastTheCap() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("personify-explorer-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = ExplorerLog(directory: root, maxFileBytes: 220, maxFileCount: 2)
    let start = Date(timeIntervalSince1970: 1_763_337_600)
    log.record(time: start, kind: "rssi", deviceID: "room-0", message: "probe", data: ["rssi": .int(-70)])
    #expect(log.lastAppendWasOnCurrentThread() == false)
    for index in 1..<10 {
        log.record(
            time: start.addingTimeInterval(Double(index)),
            kind: "rssi",
            deviceID: "room-\(index)",
            message: "OpenSp 2 MAZA \(index) at -70 dBm",
            data: ["rssi": .int(-70)]
        )
    }
    log.flush()

    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    #expect(files.count == 2)
    let active = try #require(files.first {
        $0.lastPathComponent.range(of: #"^explorer-\d{8}\.jsonl$"#, options: .regularExpression) != nil
    })
    let activeText = try String(contentsOf: active, encoding: .utf8)
    #expect(activeText.contains("\"kind\":\"rssi\""))
    #expect(activeText.hasSuffix("\n"))
    for file in files {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
        #expect(size <= 220 + 400)
        let text = try String(contentsOf: file, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let data = Data(line.utf8)
            let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
            #expect(object["kind"] != nil)
            #expect(object["message"] != nil)
        }
    }
}
