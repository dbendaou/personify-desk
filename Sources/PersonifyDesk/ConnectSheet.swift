import PersonifyCore
import SwiftUI

struct ConnectSheet: View {
    @Environment(AppModel.self) private var model
    let deviceID: UUID
    @FocusState private var pinFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Text("Pairing code")
                .font(.headline)
            Text("\(model.deviceName(deviceID)) needs a pairing code. It is saved on this Mac for this room.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Pairing code", text: $model.pairingPINDraft)
                .textFieldStyle(.roundedBorder)
                .focused($pinFocused)
                .onChange(of: model.pairingPINDraft) { _, newValue in
                    let clean = Pin.sanitize(newValue)
                    if clean != newValue {
                        model.pairingPINDraft = clean
                    }
                }
            HStack {
                Button("Cancel") { model.cancelConnectSheet() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save and connect") { model.submitPairingPIN(for: deviceID) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.pinCanPair)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { pinFocused = true }
    }
}
