import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HomeScreen()
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 8, y: 3)
                        .padding(.bottom, 18)
                }
            }
            .sheet(isPresented: Binding(
                get: { model.showingConnectSheet },
                set: { model.showingConnectSheet = $0 }
            )) {
                if let id = model.connectDeviceID {
                    ConnectSheet(deviceID: id)
                }
            }
            .sheet(isPresented: Binding(
                get: { model.askBeforeSending && model.pendingWrite != nil },
                set: { if !$0 { model.cancelExperiment() } }
            )) {
                ConfirmSendSheet()
            }
            .tint(Color(red: 0.02, green: 0.42, blue: 0.46))
            .frame(minWidth: 760, minHeight: 520)
    }
}
