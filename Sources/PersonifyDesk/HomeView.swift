import AppKit
import PersonifyCore
import SwiftUI

struct HomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var favoriteDevices: [DiscoveredDevice] { model.favoriteDevices }

    private var recentDevices: [DiscoveredDevice] { model.recentDevices }

    private var nearbyDevices: [DiscoveredDevice] {
        let used = Set(favoriteDevices.map(\.id) + recentDevices.map(\.id))
        return model.roomsInRange.filter { !used.contains($0.id) }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { model.openedRoomID },
            set: { id in
                guard let id else { return }
                model.chooseRoom(id)
            }
        )) {
            Section("Favorites") {
                if favoriteDevices.isEmpty {
                    Text("Star a room to keep it here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(favoriteDevices) { device in
                    roomRow(device)
                }
            }
            if !recentDevices.isEmpty {
                Section("Recent") {
                    ForEach(recentDevices) { device in
                        roomRow(device)
                    }
                }
            }
            Section("Nearby") {
                if model.roomsInRange.isEmpty {
                    Text("No rooms in range")
                        .foregroundStyle(.secondary)
                }
                ForEach(nearbyDevices) { device in
                    roomRow(device)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func roomRow(_ device: DiscoveredDevice) -> some View {
        let quality = SignalQuality.from(rssi: device.rssi)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars", variableValue: quality.barLevel)
                    Text(quality.title)
                }
                .font(.caption)
                .foregroundStyle(qualityColor(quality))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signal, \(quality.title)")
            }
            Spacer(minLength: 0)
            favoriteButton(device.id)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .tag(device.id)
        .padding(.vertical, 4)
        .contextMenu {
            Button(model.isFavorite(device.id) ? "Remove from Favorites" : "Add to Favorites") {
                model.setFavorite(device.id, !model.isFavorite(device.id))
            }
        }
    }

    private func favoriteButton(_ id: UUID) -> some View {
        Button {
            model.setFavorite(id, !model.isFavorite(id))
        } label: {
            Image(systemName: model.isFavorite(id) ? "star.fill" : "star")
                .foregroundStyle(model.isFavorite(id) ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(model.isFavorite(id) ? "Remove from Favorites" : "Add to Favorites")
    }

    private func qualityColor(_ quality: SignalQuality) -> Color {
        switch quality {
        case .veryClose, .close: .green
        case .far: .orange
        case .outOfReach: .secondary
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.openedRoomID, model.roomIsInRange(id) {
            RoomDashboard(roomID: id)
        } else {
            ContentUnavailableView {
                Label("No room selected", systemImage: "door.left.hand.open")
            } description: {
                Text(emptyDetail)
            }
        }
    }

    private var emptyDetail: String {
        if model.roomsInRange.isEmpty {
            return "No rooms are in range."
        }
        if let name = model.roomList.lastSelectedName {
            return "\(name) is not in range. Choose a room from Nearby."
        }
        return "Choose a room from Nearby."
    }
}

private struct RoomDashboard: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID

    private var controlsReady: Bool {
        model.controls(for: roomID).hasLiveRead && model.link(for: roomID) == .ready
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.deviceName(roomID))
                            .font(.largeTitle.weight(.semibold))
                        Text(statusLine)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        model.setFavorite(roomID, !model.isFavorite(roomID))
                    } label: {
                        Image(systemName: model.isFavorite(roomID) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(model.isFavorite(roomID) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(model.isFavorite(roomID) ? "Remove from Favorites" : "Add to Favorites")
                }
                if let error = model.roomError, model.openedRoomID == roomID {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 16) {
                    LightTile(roomID: roomID, enabled: controlsReady)
                        .opacity(controlsReady ? 1 : 0.5)
                        .disabled(!controlsReady)
                    FanTile(roomID: roomID)
                    ClimateTile(roomID: roomID, enabled: controlsReady)
                        .opacity(controlsReady ? 1 : 0.5)
                        .disabled(!controlsReady)
                }
                BlindsCard(roomID: roomID)
                BrightnessCard(roomID: roomID, enabled: controlsReady)
                    .opacity(controlsReady ? 1 : 0.5)
                    .disabled(!controlsReady)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("\(model.deviceName(roomID)) · \(model.connectionStateTitle(for: roomID))")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusLine: String {
        switch model.link(for: roomID) {
        case .connecting, .findingControls:
            return "Connecting…"
        case .ready:
            if let temperature = model.temperature(for: roomID) {
                return "Connected · \(String(format: "%.1f°", temperature)) inside"
            }
            return "Connected"
        case .notConnected, .failed:
            return "Not connected"
        }
    }
}

private struct LightTile: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID
    let enabled: Bool

    private var level: Double? { model.controls(for: roomID).lightPercent }
    private var on: Bool { (level ?? 0) > 0.5 }
    private var ink: Color { on && level != nil ? Color(red: 0.16, green: 0.12, blue: 0.04) : .primary }

    var body: some View {
        Button {
            guard enabled, level != nil else { return }
            model.setLightOn(!on)
        } label: {
            VStack(spacing: 8) {
                if level == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.monochrome)
                }
                Text(level.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("Lights")
                    .font(.headline)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? AnyShapeStyle(Color(red: 0.99, green: 0.76, blue: 0.22)) : AnyShapeStyle(.regularMaterial))
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled || level == nil)
    }
}

private struct FanTile: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID

    private var setting: FanSetting? { model.controls(for: roomID).fanSetting }
    private var running: Bool {
        if case .speed = setting { return true }
        return false
    }

    private var selectedInk: Color { Color(red: 0.10, green: 0.34, blue: 0.72) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "fan.fill")
                .font(.system(size: 22))
                .foregroundStyle(running ? Color.white : Color.primary)
            Text("Fan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(running ? Color.white : Color.primary)
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    fanChoice(.off, title: "Off")
                    fanChoice(.speed(1), title: "1")
                    fanChoice(.speed(2), title: "2")
                    fanChoice(.speed(3), title: "3")
                }
                .padding(2)
                .background {
                    Capsule().fill(track)
                }
                fanChoice(.auto, title: "Auto", showsTrack: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(running ? AnyShapeStyle(Color(red: 0.16, green: 0.48, blue: 0.82)) : AnyShapeStyle(.regularMaterial))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fan")
    }

    private var track: Color {
        running ? Color.white.opacity(0.18) : Color.primary.opacity(0.08)
    }

    private func fanChoice(_ value: FanSetting, title: String, showsTrack: Bool = false) -> some View {
        let selected = setting == value
        return Button {
            model.setFan(value)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? selectedInk : (running ? Color.white : Color.primary))
                .background {
                    Capsule().fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(showsTrack ? track : Color.clear))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == .auto ? "Auto" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ClimateTile: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID
    let enabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                Text(temperatureText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text("Climate")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if offset == nil {
                    ProgressView()
                        .controlSize(.small)
                }
                StepButton(symbol: "minus", enabled: enabled && (offset ?? 0) > -2.99 && offset != nil) {
                    model.nudgeOffset(-0.5)
                }
                Text(offsetText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .frame(minWidth: 72)
                StepButton(symbol: "plus", enabled: enabled && (offset ?? 0) < 2.99 && offset != nil) {
                    model.nudgeOffset(0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var temperatureText: String {
        guard let temperature = model.temperature(for: roomID) else { return "—" }
        return String(format: "%.0f°", temperature)
    }

    private var offset: Double? { model.controls(for: roomID).offsetCelsius }

    private var offsetText: String {
        guard let offset else { return "Offset —" }
        if abs(offset) < 0.05 { return "Offset +0" }
        let formatted = String(format: "%+.1f", offset).replacingOccurrences(of: "-", with: "−")
        return "Offset \(formatted)"
    }
}

private struct StepButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct BlindsCard: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID

    private var groups: [Int]? { model.controls(for: roomID).blindGroups }
    private var closed: Double { model.displayedBlindPercent() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Blinds", systemImage: "blinds.horizontal.closed")
                .font(.headline)
            CapsuleFillSlider(
                value: closed,
                tint: Color(red: 0.22, green: 0.48, blue: 0.96),
                label: String(format: "%.0f%% closed", closed),
                enabled: true,
                onChange: { model.setDisplayedBlindPercent($0) },
                onCommit: { model.releaseBlindSlider() }
            )
            if BlindReadWatch.showsGroupPicker(groups) {
                HStack(spacing: 6) {
                    blindPill("All", target: 0)
                    ForEach(groups ?? [], id: \.self) { number in
                        blindPill("Group \(number)", target: number)
                    }
                }
            }
            if model.blindWatch == .failed {
                Button("Couldn't read groups · Retry") { model.retryBlindGroups() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                wideButton("Open", symbol: "chevron.up") { model.setBlindQuick(0) }
                wideButton("Close", symbol: "chevron.down") { model.setBlindQuick(100) }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func blindPill(_ title: String, target: Int) -> some View {
        let selected = model.blindTarget == target
        return Button {
            model.blindTarget = target
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? Color.primary.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func wideButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BrightnessCard: View {
    @Environment(AppModel.self) private var model
    let roomID: UUID
    let enabled: Bool

    private var level: Double? { model.controls(for: roomID).lightPercent }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.1))
                Text("Brightness")
                    .font(.headline)
                Text(level.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)
            if let level {
                CapsuleFillSlider(
                    value: level,
                    tint: Color(red: 0.99, green: 0.76, blue: 0.18),
                    label: "",
                    labelInk: Color(red: 0.16, green: 0.12, blue: 0.04),
                    enabled: enabled,
                    onChange: { model.setDisplayedLight($0) },
                    onCommit: { model.releaseSlider(number: nil, lights: true) }
                )
            } else {
                UnknownSlider(title: "—")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct UnknownSlider: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 36)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

private struct CapsuleFillSlider: View {
    var value: Double
    var tint: Color
    var label: String
    var labelInk: Color = .white
    var enabled: Bool
    var onChange: (Double) -> Void
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = min(100, max(0, value))
            let fill = max(36, width * clamped / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: fill)
                if !label.isEmpty {
                    Text(label)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(clamped > 28 ? labelInk : Color.primary)
                        .padding(.leading, 16)
                }
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .frame(width: 28, height: 28)
                    .offset(x: min(max(4, fill - 32), width - 32))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        let x = min(max(0, gesture.location.x), width)
                        onChange((x / width * 100).rounded())
                    }
                    .onEnded { _ in
                        guard enabled else { return }
                        onCommit()
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel(label.isEmpty ? "Brightness" : "Blinds")
        .accessibilityValue(String(format: "%.0f percent", value))
    }
}

struct ConfirmSendSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Send to the room?", systemImage: "paperplane.fill")
                .font(.title2.weight(.semibold))
            Text("The room will use the values shown on the desk.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelExperiment() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send") { model.confirmPendingWrite() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(.regularMaterial)
    }
}
