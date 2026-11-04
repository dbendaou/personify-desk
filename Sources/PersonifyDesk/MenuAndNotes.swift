import AppKit
import PersonifyCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle("Ask before sending", isOn: Binding(
                get: { model.askBeforeSending },
                set: { model.setAskBeforeSending($0) }
            ))
            Section("Room") {
                if model.visibleDevices.isEmpty {
                    Text("No rooms in range.")
                } else {
                    ForEach(model.visibleDevices) { device in
                        Button(device.displayName) { model.chooseRoom(device.id) }
                    }
                }
            }
            Section("Pairing code") {
                if let roomID = model.openedRoomID ?? model.chosenRoomIdentifier() {
                    Text(model.deviceName(roomID))
                    TextField("Pairing code", text: Binding(
                        get: { model.pairingPINDraft },
                        set: { model.pairingPINDraft = Pin.sanitize($0) }
                    ))
                    HStack {
                        Button("Save") { model.savePINDraft(for: roomID) }
                        Button("Forget") { model.forgetPIN(roomID) }
                    }
                    Text("Used the next time this room connects. A sheet appears only when pairing fails or the room asks for a code that is not saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open a room to edit its pairing code.")
                }
                let ids = (try? model.pins.deviceIDs()) ?? []
                if ids.isEmpty {
                    Text("No pairing codes are saved.")
                }
                Button("Forget all pairing codes") { model.forgetAllPINs() }
                    .disabled(ids.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .padding()
        .onAppear {
            if let id = model.openedRoomID ?? model.chosenRoomIdentifier() {
                model.loadPINDraft(for: id)
            }
        }
    }
}
