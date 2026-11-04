import CoreBluetooth
import Foundation
import PairingBridge
import PersonifyCore

@MainActor
final class BluetoothSession: NSObject {
    weak var model: AppModel?
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var characteristics: [String: CBCharacteristic] = [:]
    private var idByObject: [ObjectIdentifier: String] = [:]
    private var bridge: PDSPairingBridge?
    private var lastDisconnect: (UUID, TimeInterval, String)?
    private var readBatch: ReadBatch?
    private var queuedFrames: [Data] = []
    private var queuedFrameID: String?
    private var queuedSpacingMilliseconds = 0
    private var writeGeneration = 0

    private struct ReadBatch {
        var deviceID: UUID
        var label: String
        var outstanding: Set<String>
        var values: [String: Data]
    }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startScan() {
        guard central?.state == .poweredOn else {
            model?.statusLine = "Bluetooth is not ready to scan."
            return
        }
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        model?.scanning = true
        model?.statusLine = "Scanning for advertisements."
        model?.log(kind: "scan", message: "Scan started.")
    }

    func stopScan() {
        central?.stopScan()
        model?.scanning = false
        model?.statusLine = "Scan stopped."
        model?.log(kind: "scan", message: "Scan stopped.")
    }

    func connect(id: UUID, pin: String?) {
        guard let peripheral = peripherals[id] else {
            model?.statusLine = "Out of range."
            return
        }
        disconnectCurrent()
        peripheral.delegate = self
        model?.markConnecting(id)
        if let pin {
            startPairing(id: id, pin: pin)
        }
        central?.connect(peripheral, options: nil)
        model?.log(kind: "connect", deviceID: id.uuidString, message: "GATT connection requested.")
    }

    func disconnectCurrent() {
        bridge?.stop()
        bridge = nil
        guard let id = model?.connectedDeviceID ?? model?.connectingDeviceID, let peripheral = peripherals[id] else {
            return
        }
        central?.cancelPeripheralConnection(peripheral)
    }

    func updatePIN(_ pin: String) {
        bridge?.updatePIN(pin)
    }

    func replyToComparison(_ accept: Bool) {
        bridge?.replyToConfirmation(accept)
        model?.comparisonValue = nil
    }

    func read(_ id: String) {
        guard let characteristic = characteristics[id], let peripheral = characteristic.service?.peripheral else { return }
        peripheral.readValue(for: characteristic)
    }

    func setNotify(_ enabled: Bool, id: String) {
        guard let characteristic = characteristics[id], let peripheral = characteristic.service?.peripheral else { return }
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    func readLiveValues() {
        readAllReadable(label: "Snapshot")
    }

    func readAllReadable(label: String) {
        guard let deviceID = model?.connectedDeviceID else {
            model?.statusLine = "Connect to a room controller before taking a snapshot."
            return
        }
        var batch = ReadBatch(deviceID: deviceID, label: label, outstanding: [], values: [:])
        for characteristic in characteristics.values where characteristic.properties.contains(.read) {
            guard let peripheral = characteristic.service?.peripheral else { continue }
            guard let id = idByObject[ObjectIdentifier(characteristic)] else { continue }
            batch.outstanding.insert(id)
            peripheral.readValue(for: characteristic)
            model?.log(
                kind: "read-request",
                deviceID: deviceID.uuidString,
                message: "Read requested \(characteristic.uuid.uuidString) (\(label))."
            )
        }
        readBatch = batch
        if batch.outstanding.isEmpty {
            readBatch = nil
            model?.sealSnapshot(deviceID: deviceID, label: label, values: [:])
        } else {
            model?.statusLine = "\(label): reading \(batch.outstanding.count) characteristics."
        }
    }

    func readLiveCharacteristics(label: String) {
        model?.quietLiveRead = (label == "Live")
        guard let deviceID = model?.connectedDeviceID else {
            model?.statusLine = "Connect to a room controller before reading 0002xxxx."
            return
        }
        var batch = ReadBatch(deviceID: deviceID, label: label, outstanding: [], values: [:])
        for (id, characteristic) in characteristics where PersonifyVendor.isLiveValue(characteristic.uuid.uuidString) && characteristic.properties.contains(.read) {
            guard let peripheral = characteristic.service?.peripheral else { continue }
            batch.outstanding.insert(id)
            peripheral.readValue(for: characteristic)
            model?.log(
                kind: "read-request",
                deviceID: deviceID.uuidString,
                message: "Read requested \(characteristic.uuid.uuidString) (\(label))."
            )
        }
        readBatch = batch
        if label == "Live" {
            if batch.outstanding.isEmpty {
                readBatch = nil
                model?.quietLiveRead = false
            }
            return
        }
        if batch.outstanding.isEmpty {
            readBatch = nil
            model?.sealSnapshot(deviceID: deviceID, label: label, values: [:])
            model?.statusLine = "00020001, 00020002, and 00020003 were not available to read."
        } else {
            model?.statusLine = "\(label): reading \(batch.outstanding.count) live characteristics."
        }
    }

    @discardableResult
    func readBlindGroups() -> Bool {
        guard let characteristic = characteristics.values.first(where: {
            PersonifyVendor.shortIdentifier($0.uuid.uuidString) == "00020003"
        }) else { return false }
        guard characteristic.properties.contains(.read), let peripheral = characteristic.service?.peripheral else { return false }
        peripheral.readValue(for: characteristic)
        return true
    }

    func refreshLiveIfIdle() {
        guard readBatch == nil, model?.connectedDeviceID != nil, model?.controlBusy == false else { return }
        readLiveCharacteristics(label: "Live")
    }

    func subscribeAll() {
        for characteristic in characteristics.values {
            let mask = characteristic.properties.rawValue
            guard mask & 0x10 != 0 || mask & 0x20 != 0 else { continue }
            characteristic.service?.peripheral?.setNotifyValue(true, for: characteristic)
        }
        model?.log(kind: "subscribe", deviceID: model?.connectedDeviceID?.uuidString, message: "Subscribed to every notifying characteristic.")
    }

    func writeFrames(_ frames: [Data], id: String, spacingMilliseconds: Int) {
        writeGeneration += 1
        queuedFrames = frames
        queuedFrameID = id
        queuedSpacingMilliseconds = spacingMilliseconds
        sendNextFrame(generation: writeGeneration, delayed: false)
    }

    private func sendNextFrame(generation: Int, delayed: Bool) {
        guard generation == writeGeneration, let id = queuedFrameID else { return }
        guard !queuedFrames.isEmpty else {
            queuedFrameID = nil
            readLiveCharacteristics(label: "After write")
            return
        }
        let data = queuedFrames.removeFirst()
        let delay = delayed ? queuedSpacingMilliseconds : 0
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard generation == self.writeGeneration else { return }
            self.submitWrite(data, id: id)
        }
    }

    private func submitWrite(_ data: Data, id: String) {
        guard let characteristic = characteristics[id], let peripheral = characteristic.service?.peripheral else {
            writeGeneration += 1
            queuedFrames = []
            queuedFrameID = nil
            model?.statusLine = "00000004 is no longer available. Nothing further was sent."
            model?.log(kind: "write", deviceID: model?.connectedDeviceID?.uuidString, message: model?.statusLine ?? "00000004 is no longer available.")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        model?.logWrite(id: characteristic.uuid.uuidString, data: data, note: "Write With Response \(Hex.encode(data, spaced: true))")
    }

    func write(_ data: Data, id: String) {
        guard let characteristic = characteristics[id], let peripheral = characteristic.service?.peripheral else { return }
        let mask = characteristic.properties.rawValue
        if mask & 0x08 != 0 {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            model?.logWrite(id: id, data: data, note: "Write with response submitted.")
            if PersonifyVendor.shortIdentifier(characteristic.uuid.uuidString) == "00000004" {
                model?.snapshotWhenWriteCompletes = true
                readLiveCharacteristics(label: "After write submitted")
            }
        } else if mask & 0x04 != 0 {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            model?.logWrite(id: id, data: data, note: "Write without response submitted.")
            if PersonifyVendor.shortIdentifier(characteristic.uuid.uuidString) == "00000004" {
                readLiveCharacteristics(label: "After write")
            }
        } else {
            model?.statusLine = "That characteristic is not writable."
        }
    }

    private func startPairing(id: UUID, pin: String) {
        guard let address = BluetoothAddressLookup.address(for: id) else {
            model?.notePairing("CoreBluetooth does not provide this device's Bluetooth address, and it is not in the local Bluetooth cache. GATT discovery is starting.")
            return
        }
        let bridge = PDSPairingBridge(address: address, pin: pin)
        nonisolated(unsafe) let session = self
        bridge.onLog = { message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    session.model?.notePairing(message)
                }
            }
        }
        bridge.onNumericComparison = { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    session.model?.comparisonValue = value
                    session.model?.notePairing("Confirm the number if it matches the device.")
                }
            }
        }
        bridge.onPasskeyDisplay = { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    session.model?.passkeyValue = value
                    session.model?.notePairing("Enter the generated passkey on the device if it asks.")
                }
            }
        }
        bridge.onPINRequired = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    session.model?.deviceRequestedPIN(id)
                }
            }
        }
        bridge.onPairingFailed = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    session.model?.pairingFailed(id)
                }
            }
        }
        self.bridge = bridge
        do {
            try bridge.start()
        } catch {
            model?.notePairing("The pairing API did not start (\(error.localizedDescription)). GATT discovery is still starting.")
        }
    }

    fileprivate func ingest(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int) {
        peripherals[peripheral.identifier] = peripheral
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        let advertisement = Self.advertisement(from: advertisementData, fallbackName: peripheral.name)
        model?.upsert(
            id: peripheral.identifier,
            peripheralName: peripheral.name,
            advertisement: advertisement,
            rssi: rssi,
            connectable: connectable,
            rawFields: Self.jsonFields(advertisementData)
        )
    }

    fileprivate func resetLink() {
        characteristics.removeAll()
        idByObject.removeAll()
        bridge?.stop()
        bridge = nil
    }

    private static func advertisement(from dictionary: [String: Any], fallbackName: String?) -> Advertisement {
        var advertisement = Advertisement()
        if let name = dictionary[CBAdvertisementDataLocalNameKey] as? String {
            advertisement.localName = name
        } else {
            advertisement.localName = fallbackName
        }
        var uuids = uuidStrings(dictionary[CBAdvertisementDataServiceUUIDsKey])
        uuids.append(contentsOf: uuidStrings(dictionary[CBAdvertisementDataOverflowServiceUUIDsKey]))
        advertisement.serviceUUIDs = uuids
        advertisement.solicitedServiceUUIDs = uuidStrings(dictionary[CBAdvertisementDataSolicitedServiceUUIDsKey])
        if let data = dictionary[CBAdvertisementDataManufacturerDataKey] as? Data {
            advertisement.manufacturerRecords = [ManufacturerRecord.parse(companyPrefixed: data)]
        }
        if let power = dictionary[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            advertisement.txPower = power.intValue
        }
        if let serviceData = dictionary[CBAdvertisementDataServiceDataKey] as? [AnyHashable: Any] {
            for (key, value) in serviceData {
                let uuid = (key as? CBUUID)?.uuidString ?? String(describing: key)
                let payload = (value as? Data) ?? Data()
                advertisement.serviceData.append(ServiceDataRecord(uuid: uuid, payloadHex: Hex.encode(payload)))
            }
        }
        return advertisement
    }

    private static func uuidStrings(_ value: Any?) -> [String] {
        if let list = value as? [CBUUID] {
            return list.map(\.uuidString)
        }
        if let list = value as? NSArray {
            return list.compactMap { ($0 as? CBUUID)?.uuidString }
        }
        return []
    }

    private static func jsonFields(_ dictionary: [String: Any]) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        for (key, value) in dictionary {
            fields[key] = jsonValue(value)
        }
        return fields
    }

    private static func jsonValue(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let data as Data:
            return .string(Hex.encode(data, spaced: true))
        case let uuid as CBUUID:
            return .string(uuid.uuidString)
        case let number as NSNumber:
            return .string(number.stringValue)
        case let list as [Any]:
            return .array(list.map(jsonValue))
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues(jsonValue))
        case let dictionary as [AnyHashable: Any]:
            var object: [String: JSONValue] = [:]
            for (key, item) in dictionary {
                object[String(describing: key)] = jsonValue(item)
            }
            return .object(object)
        default:
            return .string(String(describing: value))
        }
    }

    fileprivate func remember(_ characteristic: CBCharacteristic, serviceUUID: String, index: Int) -> GATTCharNode {
        let id = "\(serviceUUID)|\(index)|\(characteristic.uuid.uuidString)"
        characteristics[id] = characteristic
        idByObject[ObjectIdentifier(characteristic)] = id
        let mask = UInt(characteristic.properties.rawValue)
        return GATTCharNode(
            id: id,
            uuid: characteristic.uuid.uuidString,
            properties: GATTProperties.names(mask: mask),
            propertyMask: mask,
            descriptors: [],
            value: characteristic.value,
            notifying: characteristic.isNotifying,
            status: nil
        )
    }

    fileprivate func identifier(for characteristic: CBCharacteristic) -> String? {
        idByObject[ObjectIdentifier(characteristic)]
    }
}

extension BluetoothSession: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        nonisolated(unsafe) let central = central
        MainActor.assumeIsolated {
            self.model?.setPhase(central.state)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        nonisolated(unsafe) let peripheral = peripheral
        nonisolated(unsafe) let advertisementData = advertisementData
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            self.ingest(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let peripheral = peripheral
        MainActor.assumeIsolated {
            peripheral.delegate = self
            self.model?.markConnected(peripheral.identifier)
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        let message = error.map { Self.bluetoothErrorSummary($0) } ?? "The connection failed. No NSError was provided."
        let authentication = error.map { Self.isAuthentication($0) } ?? false
        MainActor.assumeIsolated {
            self.model?.markFailed(peripheral.identifier, message: message, authentication: authentication)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        let message = Self.disconnectSummary(error)
        MainActor.assumeIsolated {
            self.noteDisconnect(peripheral.identifier, message: message)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        nonisolated(unsafe) let peripheral = peripheral
        let message = Self.disconnectSummary(error, reconnecting: isReconnecting)
        MainActor.assumeIsolated {
            self.noteDisconnect(peripheral.identifier, message: message)
        }
    }

    private func noteDisconnect(_ id: UUID, message: String) {
        let now = Date().timeIntervalSince1970
        if let last = lastDisconnect, last.0 == id, now - last.1 < 0.5 {
            if message.contains("code "), !last.2.contains("code ") {
                model?.log(kind: "disconnect", deviceID: id.uuidString, message: message)
            }
            return
        }
        lastDisconnect = (id, now, message)
        if let batch = readBatch, batch.deviceID == id, !batch.outstanding.isEmpty {
            model?.log(
                kind: "read-request",
                deviceID: id.uuidString,
                message: "\(batch.outstanding.count) reads were still outstanding when the link dropped."
            )
        }
        readBatch = nil
        resetLink()
        model?.markDisconnected(id, message: message)
    }

    nonisolated private static func disconnectSummary(_ error: Error?, reconnecting: Bool = false) -> String {
        if reconnecting {
            let detail = error.map { bluetoothErrorSummary($0) } ?? "No NSError was provided."
            return "The link dropped and macOS is reconnecting. \(detail)"
        }
        guard let error else { return "Disconnected. No NSError was provided." }
        return "Disconnected. \(bluetoothErrorSummary(error))"
    }

    nonisolated static func bluetoothErrorSummary(_ error: Error) -> String {
        let ns = error as NSError
        let known: String
        if ns.domain == CBErrorDomain {
            known = cbErrorNames[ns.code] ?? "unlisted CBError"
        } else if ns.domain == CBATTErrorDomain {
            known = attErrorNames[ns.code] ?? "unlisted CBATTError"
        } else {
            known = ns.localizedDescription
        }
        return "\(ns.domain) code \(ns.code) (\(known)). \(ns.localizedDescription)"
    }

    nonisolated private static let cbErrorNames: [Int: String] = [
        0: "unknown",
        1: "invalidParameters",
        2: "invalidHandle",
        3: "notConnected",
        4: "outOfSpace",
        5: "operationCancelled",
        6: "connectionTimeout",
        7: "peripheralDisconnected",
        8: "uuidNotAllowed",
        9: "alreadyAdvertising",
        10: "connectionFailed",
        11: "connectionLimitReached",
        12: "unknownDevice",
        13: "operationNotSupported",
        14: "peerRemovedPairingInformation",
        15: "encryptionTimedOut",
        16: "tooManyLEPairedDevices",
    ]

    nonisolated private static let attErrorNames: [Int: String] = [
        1: "invalidHandle",
        2: "readNotPermitted",
        3: "writeNotPermitted",
        5: "insufficientAuthentication",
        6: "requestNotSupported",
        7: "invalidOffset",
        8: "insufficientAuthorization",
        13: "invalidAttributeValueLength",
        14: "unlikelyError",
        15: "insufficientEncryption",
        17: "insufficientResources",
    ]
}

extension BluetoothSession: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        let message = error.map(Self.describe)
        MainActor.assumeIsolated {
            if let message {
                self.model?.reportRoomError(message)
                self.model?.statusLine = message
                self.model?.log(kind: "error", deviceID: peripheral.identifier.uuidString, message: message)
            }
            self.model?.services = []
            for service in peripheral.services ?? [] {
                let node = GATTServiceNode(id: service.uuid.uuidString, uuid: service.uuid.uuidString, characteristics: [])
                self.model?.services.append(node)
                peripheral.discoverCharacteristics(nil, for: service)
            }
            self.model?.log(
                kind: "services",
                deviceID: peripheral.identifier.uuidString,
                message: "Discovered \(peripheral.services?.count ?? 0) services."
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        nonisolated(unsafe) let service = service
        let message = error.map(Self.describe)
        MainActor.assumeIsolated {
            if let message {
                self.model?.reportRoomError(message)
                self.model?.statusLine = message
                self.model?.log(kind: "error", deviceID: peripheral.identifier.uuidString, message: message)
            }
            let serviceID = service.uuid.uuidString
            var nodes: [GATTCharNode] = []
            for (index, characteristic) in (service.characteristics ?? []).enumerated() {
                let node = self.remember(characteristic, serviceUUID: serviceID, index: index)
                nodes.append(node)
                peripheral.discoverDescriptors(for: characteristic)
                let short = PersonifyVendor.shortIdentifier(characteristic.uuid.uuidString)
                if short == "00020001" || short == "00020002" || short == "00020003" {
                    let mask = characteristic.properties
                    if mask.contains(.notify) || mask.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                }
            }
            self.enqueueReads(nodes.map(\.id), on: peripheral, label: "After discovery")
            if nodes.contains(where: { PersonifyVendor.shortIdentifier($0.uuid) == "00020003" }) {
                self.readBlindGroups()
            }
            if let model = self.model, let index = model.services.firstIndex(where: { $0.uuid == serviceID }) {
                model.services[index].characteristics = nodes
                model.flushDeferredWrite()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        nonisolated(unsafe) let characteristic = characteristic
        MainActor.assumeIsolated {
            guard let id = self.identifier(for: characteristic) else { return }
            let names = (characteristic.descriptors ?? []).map { descriptor in
                let alias = AssignedNumbers.descriptorName(uuid: descriptor.uuid.uuidString)
                return alias.map { "\($0) (\(descriptor.uuid.uuidString))" } ?? descriptor.uuid.uuidString
            }
            self.model?.updateCharacteristic(id) { node in
                node.descriptors = names
            }
            for descriptor in characteristic.descriptors ?? [] where bluetoothAlias(descriptor.uuid.uuidString) == "2901" {
                peripheral.readValue(for: descriptor)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        nonisolated(unsafe) let characteristic = characteristic
        let message = error.map(Self.describe)
        let authentication = error.map { Self.isAuthentication($0) } ?? false
        let value = characteristic.value
        MainActor.assumeIsolated {
            guard let id = self.identifier(for: characteristic) else { return }
            self.model?.updateCharacteristic(id) { node in
                node.value = value
                node.status = message
            }
            let kind = characteristic.isNotifying ? "notify" : "read"
            self.model?.logValue(id: id, uuid: characteristic.uuid.uuidString, data: value, error: message, kind: kind)
            if message == nil, let value {
                self.model?.noteCaptureSample(uuid: characteristic.uuid.uuidString, data: value, kind: kind)
            }
            if authentication {
                self.model?.pairingFailed(peripheral.identifier)
            }
            if PersonifyVendor.shortIdentifier(characteristic.uuid.uuidString) == "00020003", error != nil {
                self.model?.blindGroupsReadFailed()
            }
            self.completeRead(id: id, uuid: characteristic.uuid.uuidString, data: message == nil ? value : nil)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let peripheral = peripheral
        nonisolated(unsafe) let characteristic = characteristic
        let message = error.map(Self.describe) ?? "Write completed."
        let authentication = error.map { Self.isAuthentication($0) } ?? false
        MainActor.assumeIsolated {
            guard let id = self.identifier(for: characteristic) else { return }
            self.model?.updateCharacteristic(id) { node in
                node.status = message
            }
            self.model?.log(kind: "write", deviceID: self.model?.connectedDeviceID?.uuidString, message: message, data: ["characteristic": .string(characteristic.uuid.uuidString)])
            if self.queuedFrameID != nil {
                if error != nil {
                    self.writeGeneration += 1
                    self.queuedFrames = []
                    self.queuedFrameID = nil
                    self.model?.controlBusy = false
                    self.model?.applyMeasured()
                    if authentication {
                        self.model?.pairingFailed(peripheral.identifier)
                    } else {
                        self.model?.showToast(message)
                    }
                    self.readLiveCharacteristics(label: "After write failed")
                } else {
                    self.sendNextFrame(generation: self.writeGeneration, delayed: true)
                }
            } else if self.model?.snapshotWhenWriteCompletes == true {
                self.model?.snapshotWhenWriteCompletes = false
                self.readLiveCharacteristics(label: "After write completed")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let characteristic = characteristic
        let message = error.map(Self.describe)
        let notifying = characteristic.isNotifying
        MainActor.assumeIsolated {
            guard let id = self.identifier(for: characteristic) else { return }
            self.model?.updateCharacteristic(id) { node in
                node.notifying = notifying
                node.status = message
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        nonisolated(unsafe) let descriptor = descriptor
        MainActor.assumeIsolated {
            let text: String
            if let value = descriptor.value as? String {
                text = value
            } else if let data = descriptor.value as? Data, let string = String(data: data, encoding: .utf8) {
                text = string
            } else {
                text = String(describing: descriptor.value ?? "")
            }
            self.model?.log(
                kind: "descriptor",
                deviceID: self.model?.connectedDeviceID?.uuidString,
                message: "Descriptor \(descriptor.uuid.uuidString): \(text)"
            )
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        bluetoothErrorSummary(error)
    }

    nonisolated private static func isAuthentication(_ error: Error) -> Bool {
        let ns = error as NSError
        return PairingFlow.isAuthenticationFailure(domain: ns.domain, code: ns.code)
    }

    private func enqueueReads(_ ids: [String], on peripheral: CBPeripheral, label: String) {
        let readable = ids.compactMap { id -> (String, CBCharacteristic)? in
            guard let characteristic = characteristics[id], characteristic.properties.contains(.read) else { return nil }
            return (id, characteristic)
        }
        guard !readable.isEmpty else { return }
        var batch = readBatch ?? ReadBatch(deviceID: peripheral.identifier, label: label, outstanding: [], values: [:])
        if batch.deviceID != peripheral.identifier || batch.label != label {
            batch = ReadBatch(deviceID: peripheral.identifier, label: label, outstanding: [], values: [:])
        }
        for (id, characteristic) in readable {
            batch.outstanding.insert(id)
            peripheral.readValue(for: characteristic)
            model?.log(
                kind: "read-request",
                deviceID: peripheral.identifier.uuidString,
                message: "Read requested \(characteristic.uuid.uuidString) (\(label))."
            )
        }
        readBatch = batch
        model?.statusLine = "\(label): reading \(batch.outstanding.count) characteristics."
    }

    private func completeRead(id: String, uuid: String, data: Data?) {
        guard var batch = readBatch, batch.outstanding.contains(id) else { return }
        batch.outstanding.remove(id)
        if let data {
            batch.values[uuid] = data
        }
        if batch.outstanding.isEmpty {
            let finished = batch
            readBatch = nil
            model?.sealSnapshot(deviceID: finished.deviceID, label: finished.label, values: finished.values)
        } else {
            readBatch = batch
        }
    }
}
