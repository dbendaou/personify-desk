import AppKit
import CoreBluetooth
import Foundation
import PersonifyCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let session: BluetoothSession
    @ObservationIgnored let pins: any PinStoring

    var section: DeskSection = .rooms
    var openedRoomID: UUID?
    /// A failure that is still current. Hidden while the room is connecting or ready.
    var staleRoomError: String?
    var deferredFrames: [Data] = []
    var deferredSpacing = 0
    var phase: BluetoothPhase = .starting
    var scanning = false
    var devices: [UUID: DiscoveredDevice] = [:]
    var selectedDeviceID: UUID?
    var services: [GATTServiceNode] = []
    var selectedCharacteristicID: String?
    var hexDraft = ""
    var statusLine = "Bluetooth is starting."
    var showingConnectSheet = false
    var connectDeviceID: UUID?
    var connectingDeviceID: UUID?
    var connectedDeviceID: UUID?
    var declinedPINPromptFor: UUID?
    var pairingPINDraft = ""
    var rememberPIN = true
    var pinIsSaved = false
    var activePIN: String?
    var comparisonValue: UInt32?
    var passkeyValue: UInt32?
    var sessionPINs: Set<String> = []
    var latestValues: [UUID: [String: Data]] = [:]
    var lightGroups: [LocalGroup] = []
    var blindGroups: [LocalGroup] = []
    var lightLevels: [Int: Double] = [:]
    var blindPositions: [Int: Double] = [:]
    var setpoint = 21.0
    var offsetCelsius = 0.0
    var lightPercent = 100.0
    var blindClosedPercent: [Int: Double] = Dictionary(uniqueKeysWithValues: (1...8).map { ($0, 0) })
    var allBlindsPercent = 0.0
    /// 0 moves every blind. 1...8 moves that blind only.
    var blindTarget = 0
    var hvacLabel = "Heating"
    var controllerText = ""
    var controllerMessage = "Paste a ble-room-devices JSON or XML document from the ECLYPSE REST API."
    var controllerRecords: [ControllerRoomDevice.PublicSummary] = []
    var importedPIN: String?
    var commandLine = "No request recorded yet."
    var pendingWrite: PendingWrite?
    var experimentHex = ""
    var snapshotWhenWriteCompletes = false
    var askBeforeSending = false
    var demoMode = false
    var blindWatch: BlindReadWatch = .idle
    private var blindWatchGeneration = 0
    var roomList = RoomList()
    var roomControls: [UUID: RoomControls] = [:]
    var toast: String?
    var pulse = 0
    private var lastSliderFire: Date?
    var controlBusy = false
    var quietLiveRead = false
    var measuredTemperature: Double?
    var measuredOffset: Double?
    var measuredLight: Double?
    var measuredBlinds: [Int: Double] = [:]
    @ObservationIgnored private var liveTimer: Timer?

    init() {
        let session = BluetoothSession()
        self.session = session
        let store = DefaultsPinStore()
        SilentPinMigration.migrateOnce(into: store)
        pins = store
        loadLayout()
        if UserDefaults.standard.object(forKey: Keys.askBeforeSending) == nil {
            askBeforeSending = false
        } else {
            askBeforeSending = UserDefaults.standard.bool(forKey: Keys.askBeforeSending)
        }
        loadRoomList()
        session.model = self
        if DemoLaunch.isEnabled {
            demoMode = true
            installDemoRooms()
            return
        }
        Task { @MainActor in
            session.start()
        }
        startLiveTimer()
    }

    var sortedDevices: [DiscoveredDevice] {
        devices.values.sorted { lhs, rhs in
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    var visibleDevices: [DiscoveredDevice] {
        sortedDevices.filter(isShown)
    }

    func isShown(_ device: DiscoveredDevice) -> Bool {
        PersonifyVendor.isPersonifyAdvertisement(
            serviceUUIDs: device.advertisement.serviceUUIDs,
            companyIDs: device.advertisement.manufacturerRecords.map(\.companyID)
        )
    }

    var selectedDevice: DiscoveredDevice? {
        guard let device = selectedDeviceID.flatMap({ devices[$0] }), isShown(device) else { return nil }
        return device
    }

    var pinCanPair: Bool {
        if case .accepted = Pin.validate(pairingPINDraft) { return true }
        return false
    }

    var controlsReady: Bool {
        guard let openedRoomID, connectedDeviceID == openedRoomID else { return false }
        return writeCharacteristic != nil
    }

    var writeCharacteristic: GATTCharNode? {
        services.flatMap(\.characteristics).first { PersonifyVendor.shortIdentifier($0.uuid) == "00000004" }
    }

    var roomLink: RoomLink {
        guard let id = openedRoomID else { return .notConnected }
        return link(for: id)
    }

    func link(for id: UUID) -> RoomLink {
        if demoMode, connectedDeviceID == id { return .ready }
        if connectedDeviceID == id {
            let discovered = services.contains { service in
                service.characteristics.contains { PersonifyVendor.shortIdentifier($0.uuid) == "00000004" }
            }
            return discovered ? .ready : .findingControls
        }
        if connectingDeviceID == id { return .connecting }
        if case .failed(let message) = devices[id]?.link { return .failed(message) }
        return .notConnected
    }

    /// Banner copy. A ready or in-progress link never keeps an old failure on screen.
    var roomError: String? {
        switch roomLink {
        case .ready, .connecting:
            return nil
        case .failed(let message):
            return message
        case .findingControls, .notConnected:
            return staleRoomError
        }
    }

    func deviceName(_ id: UUID) -> String {
        devices[id]?.displayName ?? "Room device"
    }

    func toggleScan() {
        if demoMode { return }
        if scanning {
            session.stopScan()
        } else {
            session.startScan()
        }
    }

    func askForPIN(_ id: UUID) {
        guard declinedPINPromptFor != id else { return }
        selectedDeviceID = id
        connectDeviceID = id
        let saved = (try? pins.load(deviceID: id.uuidString)) ?? nil
        if let saved, !saved.isEmpty {
            pairingPINDraft = saved
            pinIsSaved = true
        } else {
            pairingPINDraft = ConnectForm.unsavedSuggestion
            pinIsSaved = false
        }
        rememberPIN = true
        showingConnectSheet = true
        showMainWindow()
    }

    func deviceRequestedPIN(_ id: UUID) {
        let saved = (try? pins.load(deviceID: id.uuidString)) ?? nil
        guard PairingFlow.sheetTrigger(savedPIN: saved, authenticationFailed: false, deviceRequestedPIN: true) != nil else { return }
        askForPIN(id)
    }

    func pairingFailed(_ id: UUID) {
        guard PairingFlow.sheetTrigger(savedPIN: nil, authenticationFailed: true, deviceRequestedPIN: false) != nil else { return }
        staleRoomError = "Pairing failed. Enter the code for \(deviceName(id))."
        statusLine = staleRoomError ?? "Pairing failed."
        askForPIN(id)
    }

    func loadPINDraft(for id: UUID) {
        if let saved = try? pins.load(deviceID: id.uuidString), !saved.isEmpty {
            pairingPINDraft = saved
            pinIsSaved = true
        } else {
            pairingPINDraft = ""
            pinIsSaved = false
        }
    }

    func savePINDraft(for id: UUID) {
        switch Pin.validate(pairingPINDraft) {
        case .accepted(let digits):
            do {
                try pins.save(digits, deviceID: id.uuidString)
                pinIsSaved = true
                pairingPINDraft = digits
                statusLine = "Saved the pairing code for \(deviceName(id))."
            } catch {
                statusLine = error.localizedDescription
            }
        case .empty:
            do {
                try pins.forget(deviceID: id.uuidString)
                pinIsSaved = false
                statusLine = "Cleared the pairing code for \(deviceName(id))."
            } catch {
                statusLine = error.localizedDescription
            }
        case .notNumeric:
            statusLine = "The pairing code needs to be digits."
        case .tooLong:
            statusLine = "Bluetooth pairing codes are at most 16 digits."
        }
    }

    func submitPairingPIN(for id: UUID) {
        declinedPINPromptFor = nil
        rememberPIN = true
        connect(id, usePIN: true)
    }

    func forgetPIN(_ id: UUID) {
        do {
            try pins.forget(deviceID: id.uuidString)
            statusLine = "Forgot the saved pairing code."
        } catch {
            statusLine = error.localizedDescription
        }
        if connectDeviceID == id || selectedDeviceID == id || openedRoomID == id {
            pairingPINDraft = ""
            pinIsSaved = false
        }
    }

    func forgetAllPINs() {
        do {
            try pins.forgetAll()
            pinIsSaved = false
            pairingPINDraft = ""
            statusLine = "Forgot every saved pairing code."
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func connect(_ id: UUID, usePIN: Bool) {
        if usePIN {
            switch Pin.validate(pairingPINDraft) {
            case .accepted(let digits):
                activePIN = digits
                sessionPINs.insert(digits)
                do {
                    if rememberPIN {
                        try pins.save(digits, deviceID: id.uuidString)
                        pinIsSaved = true
                    } else {
                        try pins.forget(deviceID: id.uuidString)
                        pinIsSaved = false
                    }
                } catch {
                    statusLine = error.localizedDescription
                }
                session.updatePIN(digits)
            case .empty:
                reportRoomError("Enter a numeric pairing code. Nothing was sent.")
                return
            case .notNumeric:
                reportRoomError("The pairing code needs to be digits. Nothing was sent.")
                return
            case .tooLong:
                reportRoomError("Bluetooth pairing codes are at most 16 digits. Nothing was sent.")
                return
            }
        } else {
            activePIN = nil
        }
        declinedPINPromptFor = nil
        showingConnectSheet = false
        comparisonValue = nil
        passkeyValue = nil
        session.connect(id: id, pin: usePIN ? activePIN : nil)
    }

    func setPhase(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            phase = .ready
            statusLine = "Bluetooth is on."
            if !scanning { session.startScan() }
            considerAutoConnect()
        case .poweredOff:
            phase = .poweredOff
            scanning = false
            statusLine = "Bluetooth is off. Turn it on in System Settings."
        case .unauthorized:
            phase = .unauthorized
            scanning = false
            statusLine = "Bluetooth access is off for Personify Desk. Enable com.local.personifydesk in System Settings → Privacy & Security → Bluetooth."
        case .unsupported:
            phase = .unsupported
            statusLine = "This Mac does not have Bluetooth Low Energy."
        case .resetting:
            phase = .resetting
            statusLine = "Bluetooth is resetting."
        default:
            phase = .starting
            statusLine = "Bluetooth is starting."
        }
        log(kind: "state", message: statusLine)
    }

    func upsert(
        id: UUID,
        peripheralName: String?,
        advertisement: Advertisement,
        rssi: Int,
        connectable: Bool,
        rawFields: [String: JSONValue]
    ) {
        let now = Date()
        var device = devices[id] ?? DiscoveredDevice(
            id: id,
            peripheralName: peripheralName,
            advertisement: advertisement,
            rssi: rssi,
            connectable: connectable,
            lastSeen: now,
            lastRSSIEvent: nil,
            link: .idle
        )
        let contentChanged = device.advertisement != advertisement || devices[id] == nil
        device.peripheralName = peripheralName
        device.advertisement = advertisement
        device.rssi = rssi
        device.connectable = connectable
        device.lastSeen = now
        let shown = isShown(device)
        var loggedKind: String?
        if shown && contentChanged {
            loggedKind = "advertisement"
            device.lastRSSIEvent = now
        } else if shown && (device.lastRSSIEvent == nil || now.timeIntervalSince(device.lastRSSIEvent ?? now) > 10) {
            loggedKind = "rssi"
            device.lastRSSIEvent = now
        }
        devices[id] = device
        if loggedKind == "advertisement" {
            log(
                kind: "advertisement",
                deviceID: id.uuidString,
                message: "\(device.displayName) at \(rssi) dBm",
                data: rawFields.merging(["rssi": .int(rssi)]) { _, new in new }
            )
        } else if loggedKind == "rssi" {
            log(kind: "rssi", deviceID: id.uuidString, message: "\(device.displayName) \(rssi) dBm", data: ["rssi": .int(rssi)])
        }
        considerAutoConnect()
    }

    func markConnecting(_ id: UUID) {
        connectingDeviceID = id
        connectedDeviceID = nil
        services = []
        devices[id]?.link = .connecting
        selectedDeviceID = id
        resetControls(for: id)
        clearRoomError()
        statusLine = "Connecting to \(deviceName(id))."
    }

    func markConnected(_ id: UUID) {
        connectingDeviceID = nil
        connectedDeviceID = id
        devices[id]?.link = .connected
        clearRoomError()
        statusLine = "Connected to \(deviceName(id)). Reading every readable characteristic."
        log(kind: "connected", deviceID: id.uuidString, message: statusLine)
        beginBlindGroupRead()
    }

    func beginBlindGroupRead() {
        blindWatchGeneration += 1
        blindWatch = .awaitingFirst
        session.readBlindGroups()
        scheduleBlindWatch(generation: blindWatchGeneration)
    }

    func retryBlindGroups() {
        beginBlindGroupRead()
    }

    func blindGroupsDidArrive() {
        blindWatch = .ready
        blindWatchGeneration += 1
    }

    func blindGroupsReadFailed() {
        let next = BlindReadWatch.advance(from: blindWatch, groupsKnown: false)
        blindWatch = next.0
        if next.reread {
            session.readBlindGroups()
            scheduleBlindWatch(generation: blindWatchGeneration)
        }
    }

    private func scheduleBlindWatch(generation: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BlindReadWatch.timeout))
            guard generation == self.blindWatchGeneration else { return }
            guard self.openedRoomID.flatMap({ self.controls(for: $0).blindGroups }) == nil else {
                self.blindWatch = .ready
                return
            }
            let next = BlindReadWatch.advance(from: self.blindWatch, groupsKnown: false)
            self.blindWatch = next.0
            if next.reread {
                self.session.readBlindGroups()
                self.scheduleBlindWatch(generation: generation)
            }
        }
    }

    func markFailed(_ id: UUID, message: String, authentication: Bool = false) {
        connectingDeviceID = nil
        devices[id]?.link = .failed(message)
        staleRoomError = message
        deferredFrames = []
        deferredSpacing = 0
        statusLine = message
        log(kind: "error", deviceID: id.uuidString, message: message)
        resetControls(for: id)
        if authentication {
            pairingFailed(id)
        } else {
            showToast(message)
        }
    }

    func markDisconnected(_ id: UUID, message: String?) {
        if connectedDeviceID == id { connectedDeviceID = nil }
        if connectingDeviceID == id { connectingDeviceID = nil }
        services = []
        let text = message ?? "Disconnected."
        devices[id]?.link = .idle
        resetControls(for: id)
        statusLine = text
        log(kind: "disconnect", deviceID: id.uuidString, message: text)
        scheduleReconnect()
    }

    func updateCharacteristic(_ id: String, _ body: (inout GATTCharNode) -> Void) {
        for serviceIndex in services.indices {
            guard let charIndex = services[serviceIndex].characteristics.firstIndex(where: { $0.id == id }) else { continue }
            body(&services[serviceIndex].characteristics[charIndex])
        }
    }

    func log(kind _: String, deviceID _: String? = nil, message _: String, data _: [String: JSONValue] = [:]) {}

    func notePairing(_ message: String) {
        statusLine = message
    }

    func logValue(id _: String, uuid: String, data: Data?, error _: String?, kind _: String) {
        guard let data, let connectedDeviceID else { return }
        let previous = latestValues[connectedDeviceID]?[uuid]
        var values = latestValues[connectedDeviceID] ?? [:]
        values[uuid] = data
        latestValues[connectedDeviceID] = values
        absorbLive(uuid: uuid, data: data, changed: previous != data)
    }

    func logWrite(id _: String, data _: Data, note _: String) {}

    func takeSnapshot() {
        session.readAllReadable(label: "Snapshot")
    }

    func sealSnapshot(deviceID: UUID, label: String, values: [String: Data]) {
        if !values.isEmpty {
            var merged = latestValues[deviceID] ?? [:]
            for (key, value) in values { merged[key] = value }
            latestValues[deviceID] = merged
        }
        if label == "Live" {
            quietLiveRead = false
        }
        if label.hasPrefix("After write") {
            controlBusy = false
            applyMeasured()
        }
    }

    func noteCaptureSample(uuid _: String, data _: Data, kind _: String) {}

    func queueWrite(characteristicID _: String, uuid _: String, hex _: String) {
        pendingWrite = nil
        statusLine = "Writes are off, except a confirmed experiment to 00000004."
    }

    func queueExperiment(hex: String) {
        do {
            let data = try Hex.decode(hex)
            guard !data.isEmpty else {
                statusLine = "Enter the hex to write. Nothing was sent."
                return
            }
            proposeFrames([data])
        } catch {
            statusLine = "Hex needs an even number of digits. Nothing was sent."
        }
    }

    func proposeFrames(_ frames: [Data], spacingMilliseconds: Int = 0) {
        guard !frames.isEmpty else { return }
        let target = openedRoomID ?? selectedDeviceID
        guard let target else {
            noteRoomFailure("Choose a room first. Nothing was sent.")
            return
        }
        guard connectedDeviceID == target, let characteristic = writeCharacteristic else {
            deferredFrames = frames
            deferredSpacing = spacingMilliseconds
            let waiting = connectedDeviceID == target
                ? "Finding 00000004 on \(deviceName(target)). This command stays queued until the control appears."
                : "Not connected to \(deviceName(target)). Connect, then this command can be sent."
            statusLine = waiting
            if connectedDeviceID != target, connectingDeviceID != target {
                connectSilently(target)
            }
            return
        }
        pendingWrite = PendingWrite(characteristicID: characteristic.id, uuid: characteristic.uuid, frames: frames, spacingMilliseconds: spacingMilliseconds)
        statusLine = askBeforeSending ? "Confirm before this change is sent." : "Sending."
        clearRoomError()
        if askBeforeSending {
            showMainWindow()
        } else {
            confirmPendingWrite()
        }
    }

    func flushDeferredWrite() {
        if writeCharacteristic != nil { clearRoomError() }
        guard !deferredFrames.isEmpty, writeCharacteristic != nil, connectedDeviceID == openedRoomID else { return }
        let frames = deferredFrames
        let spacing = deferredSpacing
        deferredFrames = []
        deferredSpacing = 0
        proposeFrames(frames, spacingMilliseconds: spacing)
    }

    func noteRoomFailure(_ message: String) {
        staleRoomError = message
        statusLine = message
        deferredFrames = []
        deferredSpacing = 0
    }

    func reportRoomError(_ message: String) {
        staleRoomError = message
        statusLine = message
    }

    func clearRoomError() {
        staleRoomError = nil
    }

    func cancelConnectSheet() {
        declinedPINPromptFor = connectDeviceID
        showingConnectSheet = false
        if !deferredFrames.isEmpty, connectedDeviceID == nil {
            noteRoomFailure("Connection cancelled. Nothing was sent.")
        }
    }

    func proposeOffset() {
        proposeFrames([PersonifyWrite.setpointOffset(offsetCelsius)])
    }

    func proposeLight(_ percent: Double) {
        lightPercent = min(100, max(0, percent))
        proposeFrames([PersonifyWrite.lightLevel(lightPercent)])
    }

    func proposeBlind(number: Int) {
        guard let frame = PersonifyWrite.blindClosed(number: number, percent: blindClosedPercent[number] ?? 0) else { return }
        proposeFrames([frame])
    }

    func proposeAllBlinds() {
        guard let id = openedRoomID else { return }
        let controls = controls(for: id)
        let groups = BlindReadWatch.allWriteGroups(controls.blindGroups)
        let percent = controls.allBlindsClosed ?? controls.blindDraftPercent
        proposeFrames(
            PersonifyWrite.blindsClosed(percent: percent, groups: groups),
            spacingMilliseconds: PersonifyWrite.blindSequenceSpacingMilliseconds
        )
    }

    /// 0 writes every known group, or group 1 before the list arrives. A positive number is that group.
    func activeBlindTarget() -> Int {
        guard let id = openedRoomID else { return 0 }
        let groups = controls(for: id).blindGroups
        if let groups, groups.count == 1 { return groups[0] }
        if let groups, blindTarget != 0, groups.contains(blindTarget) { return blindTarget }
        return 0
    }

    func setFan(_ setting: FanSetting) {
        guard let id = openedRoomID else { return }
        var controls = self.controls(for: id)
        controls.fanSetting = setting
        roomControls[id] = controls
        proposeFrames([PersonifyWrite.fanSpeed(setting)])
    }

    func displayedBlindPercent() -> Double {
        guard let id = openedRoomID else { return 0 }
        let controls = self.controls(for: id)
        switch activeBlindTarget() {
        case 0:
            return controls.allBlindsClosed ?? controls.blindDraftPercent
        case let number:
            return controls.blindsClosed[number] ?? controls.blindDraftPercent
        }
    }

    func setDisplayedLight(_ value: Double) {
        guard let id = openedRoomID else { return }
        var controls = self.controls(for: id)
        let clamped = min(100, max(0, value.rounded()))
        controls.lightPercent = clamped
        roomControls[id] = controls
        lightPercent = clamped
    }

    func setDisplayedBlindPercent(_ value: Double) {
        guard let id = openedRoomID else { return }
        let clamped = min(100, max(0, value.rounded()))
        var controls = self.controls(for: id)
        controls.blindDraftPercent = clamped
        allBlindsPercent = clamped
        switch activeBlindTarget() {
        case 0:
            for group in BlindReadWatch.allWriteGroups(controls.blindGroups) where controls.blindGroups != nil {
                controls.blindsClosed[group] = clamped
                blindClosedPercent[group] = clamped
            }
        case let number:
            controls.blindsClosed[number] = clamped
            blindClosedPercent[number] = clamped
        }
        roomControls[id] = controls
    }

    func cancelExperiment() {
        guard pendingWrite != nil else { return }
        pendingWrite = nil
        controlBusy = false
        applyMeasured()
        statusLine = "Cancelled. Nothing was sent."
    }

    func confirmPendingWrite() {
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        guard PersonifyVendor.shortIdentifier(pending.uuid) == "00000004" else {
            statusLine = "Only the room control can be written."
            return
        }
        guard let dataFrames = pending.frames.isEmpty ? nil : pending.frames else { return }
        statusLine = "Sending, then reading the room."
        controlBusy = true
        session.writeFrames(dataFrames, id: pending.characteristicID, spacingMilliseconds: pending.spacingMilliseconds)
    }

    func stage(_ command: RoomCommand) {
        let attempt = UnavailableRoomEncoder().attempt(command)
        commandLine = "\(attempt.summary). \(attempt.reason)"
        statusLine = commandLine
        log(
            kind: "command",
            deviceID: selectedDeviceID?.uuidString,
            message: commandLine,
            data: [
                "summary": .string(attempt.summary),
                "sent": .bool(false),
                "status": .string(attempt.status.rawValue),
            ]
        )
    }

    func importController() {
        guard let data = controllerText.data(using: .utf8) else {
            controllerMessage = "The paste could not be read as text."
            return
        }
        do {
            let parsed = try ControllerDocument.parse(data)
            controllerRecords = parsed.map { $0.publicSummary() }
            var lights: [LocalGroup] = []
            var blinds: [LocalGroup] = []
            for device in parsed {
                for group in device.lightGroups where group.enabled != false {
                    let name = group.displayName ?? group.name ?? "Light"
                    let id = uniqueID(group.id ?? group.index ?? lights.count + 1, existing: lights)
                    lights.append(LocalGroup(id: id, name: name))
                }
                for group in device.sunBlindGroups where group.enabled != false {
                    let name = group.displayName ?? group.name ?? "Sunblind"
                    let id = uniqueID(group.id ?? group.index ?? blinds.count + 1, existing: blinds)
                    blinds.append(LocalGroup(id: id, name: name))
                }
            }
            if !lights.isEmpty { lightGroups = lights }
            if !blinds.isEmpty { blindGroups = blinds }
            importedPIN = parsed.compactMap(\.pinCode).first { !$0.isEmpty }
            saveLayout()
            let rooms = parsed.compactMap(\.roomName).joined(separator: ", ")
            controllerMessage = rooms.isEmpty
                ? "Loaded \(parsed.count) room device record(s)."
                : "Loaded records for \(rooms)."
        } catch {
            controllerMessage = String(describing: error)
        }
    }

    func useImportedPIN() {
        guard let importedPIN else { return }
        guard let id = openedRoomID ?? selectedDeviceID else {
            statusLine = "Choose a room before saving the code from the controller record."
            return
        }
        switch Pin.validate(importedPIN) {
        case .accepted(let digits):
            do {
                try pins.save(digits, deviceID: id.uuidString)
                pairingPINDraft = digits
                pinIsSaved = true
                sessionPINs.insert(digits)
                statusLine = "Saved the code from the controller record for \(deviceName(id))."
            } catch {
                statusLine = error.localizedDescription
            }
        case .empty, .notNumeric, .tooLong:
            statusLine = "The controller record did not contain a usable pairing code."
        }
    }

    func addLight() {
        let id = (lightGroups.map(\.id).max() ?? 0) + 1
        lightGroups.append(LocalGroup(id: id, name: "Light \(id)"))
        saveLayout()
    }

    func addBlind() {
        let id = (blindGroups.map(\.id).max() ?? 0) + 1
        blindGroups.append(LocalGroup(id: id, name: "Sunblind \(id)"))
        saveLayout()
    }

    func removeLight(_ id: Int) {
        lightGroups.removeAll { $0.id == id }
        saveLayout()
    }

    func removeBlind(_ id: Int) {
        blindGroups.removeAll { $0.id == id }
        saveLayout()
    }

    func chooseRoom(_ id: UUID) {
        guard let device = devices[id] else { return }
        declinedPINPromptFor = nil
        roomList.select(id.uuidString, name: device.displayName)
        saveRoomList()
        if !demoMode {
            roomControls = mapControls(RoomControlBook.select(id.uuidString, showing: openedRoomID?.uuidString, cache: controlCache()))
        }
        openedRoomID = id
        selectedDeviceID = id
        if demoMode {
            connectedDeviceID = id
            devices[id]?.link = .connected
            return
        }
        if connectedDeviceID == id || connectingDeviceID == id { return }
        if connectedDeviceID != nil || connectingDeviceID != nil {
            session.disconnectCurrent()
        }
        connectSilently(id)
    }

    func considerAutoConnect() {
        guard phase == .ready, !showingConnectSheet else { return }
        let visible = roomsInRange.map(\.id.uuidString)
        guard let chosen = roomList.launchTarget(visibleIDs: visible), let id = UUID(uuidString: chosen) else { return }
        if declinedPINPromptFor == id { return }
        if openedRoomID != nil, openedRoomID != id { return }
        if connectedDeviceID == id || connectingDeviceID == id {
            openedRoomID = id
            return
        }
        if connectedDeviceID != nil || connectingDeviceID != nil { return }
        openedRoomID = id
        selectedDeviceID = id
        connectSilently(id)
    }

    func connectSilently(_ id: UUID) {
        let saved = (try? pins.load(deviceID: id.uuidString)) ?? nil
        switch PairingFlow.initialConnect(savedPIN: saved) {
        case .savedPIN(let pin):
            pairingPINDraft = pin
            pinIsSaved = true
            rememberPIN = true
            activePIN = pin
            sessionPINs.insert(pin)
            session.updatePIN(pin)
            session.connect(id: id, pin: pin)
        case .withoutPIN:
            pinIsSaved = false
            activePIN = nil
            session.connect(id: id, pin: nil)
        }
    }

    private func scheduleReconnect() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard self.connectedDeviceID == nil, self.connectingDeviceID == nil, !self.showingConnectSheet else { return }
            self.considerAutoConnect()
        }
    }

    var presenceTitle: String {
        guard let id = openedRoomID else { return "Not connected" }
        return presenceTitle(for: id)
    }

    func connectionStateTitle(for id: UUID) -> String {
        switch link(for: id) {
        case .connecting, .findingControls: "Connecting…"
        case .ready: "Connected"
        case .notConnected, .failed: "Not connected"
        }
    }

    func presenceTitle(for id: UUID) -> String {
        switch link(for: id) {
        case .connecting, .findingControls:
            return "Connecting…"
        case .ready:
            return "Connected to \(deviceName(id))"
        case .notConnected, .failed:
            return "Out of range"
        }
    }

    /// Advertisements older than this are treated as out of range.
    var roomsInRange: [DiscoveredDevice] {
        let now = Date()
        return visibleDevices.filter { now.timeIntervalSince($0.lastSeen) < 45 }
    }

    func roomIsInRange(_ id: UUID) -> Bool {
        roomsInRange.contains { $0.id == id }
    }

    private var roomsInRangeListed: [RoomList.VisibleRoom] {
        roomsInRange.map { RoomList.VisibleRoom(id: $0.id.uuidString, name: $0.displayName) }
    }

    var favoriteDevices: [DiscoveredDevice] {
        devicesInOrder(roomList.sidebar(visible: roomsInRangeListed).favorites)
    }

    var recentDevices: [DiscoveredDevice] {
        devicesInOrder(roomList.sidebar(visible: roomsInRangeListed).recent)
    }

    func setFavorite(_ id: UUID, _ favorite: Bool) {
        guard let name = devices[id]?.displayName else { return }
        roomList.setFavorite(name: name, favorite)
        saveRoomList()
    }

    func isFavorite(_ id: UUID) -> Bool {
        guard let name = devices[id]?.displayName else { return false }
        return roomList.isFavorite(name: name)
    }

    private func devicesInOrder(_ ids: [String]) -> [DiscoveredDevice] {
        let byID = Dictionary(uniqueKeysWithValues: roomsInRange.map { ($0.id.uuidString, $0) })
        return ids.compactMap { byID[$0] }
    }

    func controls(for id: UUID) -> RoomControls {
        roomControls[id] ?? RoomControls()
    }

    func toggleLight() {
        setLightOn(lightPercent <= 0.5)
    }

    func setLightOn(_ on: Bool) {
        guard let id = openedRoomID else { return }
        var controls = self.controls(for: id)
        let current = controls.lightPercent ?? 0
        let next = on ? (current > 0.5 ? current : 100) : 0
        controls.lightPercent = next
        roomControls[id] = controls
        lightPercent = next
        pulseFeedback()
        proposeLight(next)
    }

    func setBlindPreset(number: Int?, percent: Double) {
        guard let id = openedRoomID else { return }
        var controls = self.controls(for: id)
        if let number {
            controls.blindsClosed[number] = percent
            roomControls[id] = controls
            blindClosedPercent[number] = percent
            pulseFeedback()
            proposeBlind(number: number)
        } else {
            let groups = BlindReadWatch.allWriteGroups(controls.blindGroups)
            controls.blindDraftPercent = percent
            for group in groups where controls.blindGroups != nil {
                controls.blindsClosed[group] = percent
            }
            roomControls[id] = controls
            allBlindsPercent = percent
            for group in groups { blindClosedPercent[group] = percent }
            pulseFeedback()
            proposeAllBlinds()
        }
    }

    func releaseSlider(number: Int?, lights: Bool) {
        let now = Date()
        guard ControlDebounce.shouldSend(lastFire: lastSliderFire, now: now) else { return }
        lastSliderFire = now
        pulseFeedback()
        if lights {
            if let id = openedRoomID { lightPercent = controls(for: id).lightPercent ?? lightPercent }
            proposeLight(lightPercent)
        } else if let number {
            proposeBlind(number: number)
        } else {
            proposeAllBlinds()
        }
    }

    func releaseBlindSlider() {
        let target = activeBlindTarget()
        if target == 0 {
            releaseSlider(number: nil, lights: false)
        } else {
            releaseSlider(number: target, lights: false)
        }
    }

    func setBlindQuick(_ percent: Double) {
        let target = activeBlindTarget()
        if target == 0 {
            setBlindPreset(number: nil, percent: percent)
        } else {
            setBlindPreset(number: target, percent: percent)
        }
    }

    func chosenRoomIdentifier() -> UUID? {
        openedRoomID
    }

    func showToast(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            if self.toast == message { self.toast = nil }
        }
    }

    private func pulseFeedback() {
        pulse += 1
    }

    func setAskBeforeSending(_ enabled: Bool) {
        askBeforeSending = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.askBeforeSending)
    }

    func openRoom(_ id: UUID) {
        chooseRoom(id)
    }

    func closeRoom() {
        openedRoomID = nil
    }

    func temperature(for id: UUID) -> Double? {
        if let temperature = roomControls[id]?.temperatureCelsius { return temperature }
        guard let values = latestValues[id] else { return connectedDeviceID == id ? measuredTemperature : nil }
        for (uuid, data) in values where PersonifyVendor.shortIdentifier(uuid) == "00020001" {
            return LiveRoomReading.roomTemperature(data)
        }
        return connectedDeviceID == id ? measuredTemperature : nil
    }

    func connectionLabel(for device: DiscoveredDevice) -> String {
        if connectedDeviceID == device.id { return "Connected" }
        if connectingDeviceID == device.id { return "Connecting…" }
        switch device.link {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .failed: return "Couldn't connect"
        }
    }

    private func absorbLive(uuid: String, data: Data, changed: Bool) {
        guard let connectedDeviceID, let short = PersonifyVendor.shortIdentifier(uuid) else { return }
        let current = controls(for: connectedDeviceID)
        let applied = RoomControlBook.apply(shortUUID: short, data: data, to: current, controlBusy: controlBusy)
        roomControls[connectedDeviceID] = applied.0
        if let offset = applied.0.offsetCelsius { offsetCelsius = offset }
        if let level = applied.0.lightPercent { lightPercent = level }
        measuredOffset = applied.0.measuredOffset
        measuredLight = applied.0.measuredLight
        measuredTemperature = applied.0.temperatureCelsius
        measuredBlinds = applied.0.measuredBlinds
        for (number, value) in applied.0.blindsClosed {
            blindClosedPercent[number] = value
        }
        if short == "00020003" {
            if let all = applied.0.allBlindsClosed {
                roomControls[connectedDeviceID]?.blindDraftPercent = all
                allBlindsPercent = all
            }
            blindGroupsDidArrive()
        }
    }

    func applyMeasured() {
        guard let id = connectedDeviceID ?? openedRoomID else { return }
        let controls = self.controls(for: id).revertedToMeasured()
        roomControls[id] = controls
        if let measuredOffset { offsetCelsius = measuredOffset }
        if let measuredLight { lightPercent = measuredLight }
        for (number, value) in measuredBlinds {
            blindClosedPercent[number] = value
        }
    }

    private func resetControls(for id: UUID) {
        roomControls = mapControls(RoomControlBook.dropped(id.uuidString, cache: controlCache()))
    }

    private func controlCache() -> [String: RoomControls] {
        Dictionary(uniqueKeysWithValues: roomControls.map { ($0.key.uuidString, $0.value) })
    }

    private func mapControls(_ cache: [String: RoomControls]) -> [UUID: RoomControls] {
        Dictionary(uniqueKeysWithValues: cache.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func installDemoRooms() {
        struct Sample {
            var name: String
            var rssi: Int
            var light: Double
            var offset: Double
            var temperature: Double
            var fan: FanSetting?
            var blinds: [Int: Double]
        }
        let samples = [
            Sample(name: "Atlas", rssi: -52, light: 100, offset: 0, temperature: 23, fan: .off, blinds: [1: 0, 2: 35]),
            Sample(name: "Borealis", rssi: -66, light: 70, offset: -0.5, temperature: 21.5, fan: .speed(1), blinds: [1: 50]),
            Sample(name: "Cedar Room", rssi: -74, light: 0, offset: 1, temperature: 22, fan: nil, blinds: [1: 100, 2: 100, 3: 80]),
            Sample(name: "Open Space East", rssi: -88, light: 40, offset: 0.5, temperature: 24, fan: .speed(2), blinds: [1: 6]),
        ]
        var ids: [String: UUID] = [:]
        for sample in samples {
            let id = UUID()
            ids[sample.name] = id
            devices[id] = DiscoveredDevice(
                id: id,
                peripheralName: sample.name,
                advertisement: Advertisement(
                    localName: sample.name,
                    serviceUUIDs: ["00010000-0000-0000-0000-00137E5A8EEF"]
                ),
                rssi: sample.rssi,
                connectable: true,
                lastSeen: Date(),
                lastRSSIEvent: nil,
                link: .idle
            )
            var controls = RoomControls()
            controls.hasLiveRead = true
            controls.lightPercent = sample.light
            controls.offsetCelsius = sample.offset
            controls.temperatureCelsius = sample.temperature
            controls.fanSetting = sample.fan
            controls.blindGroups = sample.blinds.keys.sorted()
            controls.blindsClosed = sample.blinds
            controls.measuredLight = sample.light
            controls.measuredOffset = sample.offset
            controls.measuredBlinds = sample.blinds
            roomControls[id] = controls
        }
        roomList = RoomList()
        roomList.setFavorite(name: "Atlas", true)
        if let cedar = ids["Cedar Room"] { roomList.select(cedar.uuidString, name: "Cedar Room") }
        if let borealis = ids["Borealis"] { roomList.select(borealis.uuidString, name: "Borealis") }
        guard let atlas = ids["Atlas"] else { return }
        roomList.select(atlas.uuidString, name: "Atlas")
        openedRoomID = atlas
        selectedDeviceID = atlas
        connectedDeviceID = atlas
        devices[atlas]?.link = .connected
        phase = .ready
        statusLine = "Demo rooms. Bluetooth is not running."
    }

    private func loadRoomList() {
        UserDefaults.standard.removeObject(forKey: Keys.favoriteRoom)
        UserDefaults.standard.removeObject(forKey: Keys.favoriteExplicit)
        if let data = UserDefaults.standard.data(forKey: Keys.roomList),
           let stored = try? JSONDecoder().decode(RoomList.self, from: data) {
            roomList = stored
        }
    }

    private func saveRoomList() {
        if demoMode { return }
        if let data = try? JSONEncoder().encode(roomList) {
            UserDefaults.standard.set(data, forKey: Keys.roomList)
        }
    }

    private func startLiveTimer() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.session.refreshLiveIfIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func nudgeOffset(_ delta: Double) {
        guard let id = openedRoomID else { return }
        var controls = self.controls(for: id)
        guard let current = controls.offsetCelsius else { return }
        let next = PersonifyWrite.clampedOffset(current + delta)
        controls.offsetCelsius = next
        roomControls[id] = controls
        offsetCelsius = next
        proposeOffset()
    }

    func nudgeSetpoint(_ delta: Double) {
        nudgeOffset(delta)
    }

    private func uniqueID(_ preferred: Int, existing: [LocalGroup]) -> Int {
        var candidate = preferred
        while existing.contains(where: { $0.id == candidate }) {
            candidate += 1
        }
        return candidate
    }

    private func loadLayout() {
        guard let data = UserDefaults.standard.data(forKey: Keys.layout),
              let layout = try? JSONDecoder().decode(SavedLayout.self, from: data) else { return }
        lightGroups = layout.lights
        blindGroups = layout.blinds
    }

    private func saveLayout() {
        let layout = SavedLayout(lights: lightGroups, blinds: blindGroups)
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: Keys.layout)
        }
    }

    private func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

enum DemoLaunch {
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment["PERSONIFY_DEMO"]
        return ProcessInfo.processInfo.arguments.contains("--demo") || environment == "1"
    }
}

private enum Keys {
        static let layout = "personifydesk.layout"
        static let askBeforeSending = "personifydesk.askBeforeSending"
        static let favoriteRoom = "personifydesk.favoriteRoom"
        static let favoriteExplicit = "personifydesk.favoriteExplicit"
        static let roomList = "personifydesk.roomList"
    }
}
