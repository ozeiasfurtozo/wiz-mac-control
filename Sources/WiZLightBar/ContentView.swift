import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusBanner
                deviceControls

                if model.selectedDevice != nil {
                    powerControls
                    modeSelector
                    activeModeControls
                }

                footer
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.lightState.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.title2)
                .foregroundStyle(model.lightState.isOn ? .yellow : .secondary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("WiZ Light Bar")
                    .font(.headline.weight(.semibold))
                Text(model.selectedDevice?.ipAddress ?? "No device selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.discover()
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderless)
            .help("Search for WiZ devices")
            .disabled(model.isDiscovering)
        }
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.isDiscovering || model.isSending {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var deviceControls: some View {
        ControlSection(title: "Device") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Selected", selection: selectedDevice) {
                    Text("None").tag(Optional<WiZDevice>.none)
                    ForEach(model.devices) { device in
                        Text(device.displayName).tag(Optional(device))
                    }
                }
                .disabled(model.devices.isEmpty)

                HStack(spacing: 8) {
                    TextField("192.168.1.50", text: $model.manualIPAddress)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            model.useManualAddress()
                        }

                    Button("Use") {
                        model.useManualAddress()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if model.devices.isEmpty {
                    Text("Search the network or enter the IP address manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var powerControls: some View {
        ControlSection(title: "Power") {
            HStack(spacing: 12) {
                Toggle("On", isOn: Binding(
                    get: { model.lightState.isOn },
                    set: { model.setPower($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!model.canSend)

                Spacer()

                Button {
                    Task {
                        await model.refreshState()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .help("Refresh state")
                .disabled(!model.canSend)
            }
        }
    }

    private var modeSelector: some View {
        Picker("Mode", selection: Binding(
            get: { model.selectedControlMode },
            set: { model.setControlMode($0) }
        )) {
            ForEach(LightControlMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var activeModeControls: some View {
        switch model.selectedControlMode {
        case .ambilight:
            ambilightControls
        case .color:
            lightControls
        case .scenes:
            sceneControls
        }
    }

    private var lightControls: some View {
        ControlSection(title: "Color") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Brightness")
                        Spacer()
                        Text("\(model.lightState.dimming)%")
                            .font(.callout.monospacedDigit().weight(.medium))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(model.lightState.dimming) },
                            set: { model.setDimming($0) }
                        ),
                        in: 10...100,
                        step: 1
                    )
                    .disabled(!model.canSend)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text("\(model.lightState.temperature) K")
                            .font(.callout.monospacedDigit().weight(.medium))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(model.lightState.temperature) },
                            set: { model.setTemperature($0) }
                        ),
                        in: 2200...6500,
                        step: 50
                    )
                    .disabled(!model.canSend)
                }

                HStack(spacing: 12) {
                    ColorPicker(
                        "RGB",
                        selection: Binding(
                            get: { model.lightState.color },
                            set: { model.setColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .disabled(!model.canSend)

                    Text("R \(model.lightState.red)  G \(model.lightState.green)  B \(model.lightState.blue)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack(spacing: 8) {
                    PresetButton(title: "Warm", color: .orange) {
                        model.setTemperature(2700)
                    }
                    PresetButton(title: "Neutral", color: .yellow) {
                        model.setTemperature(4000)
                    }
                    PresetButton(title: "Cool", color: .cyan) {
                        model.setTemperature(6500)
                    }
                }
                .disabled(!model.canSend)
            }
        }
    }

    private var ambilightControls: some View {
        ControlSection(title: "Ambilight") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Toggle("Two zones", isOn: Binding(
                        get: { model.isAmbilightEnabled },
                        set: { model.setAmbilightEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(model.selectedDevice == nil)

                    Spacer()
                }

                HStack(spacing: 12) {
                    ZonePreview(title: "Zone A", color: model.ambilightZoneAColor.color)
                    ZonePreview(title: "Zone B", color: model.ambilightZoneBColor.color)
                }

                HStack(spacing: 8) {
                    Picker("Monitor", selection: Binding(
                        get: { model.selectedAmbilightDisplayID },
                        set: { model.setAmbilightDisplay($0) }
                    )) {
                        ForEach(model.ambilightDisplays) { display in
                            Text(display.displayName).tag(display.id)
                        }
                    }
                    .disabled(model.ambilightDisplays.isEmpty)

                    Button {
                        model.refreshAmbilightDisplays()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh monitors")
                }

                Toggle("Swap A/B", isOn: Binding(
                    get: { model.isAmbilightZoneMappingSwapped },
                    set: { model.setAmbilightZoneMappingSwapped($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(model.selectedDevice == nil)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Side offset")
                        Spacer()
                        Text("\(Int(model.ambilightSideOffset)) px")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { model.ambilightSideOffset },
                            set: { model.setAmbilightSideOffset($0) }
                        ),
                        in: 0...360,
                        step: 1
                    )
                    .disabled(model.selectedDevice == nil)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top/bottom offset")
                        Spacer()
                        Text("\(Int(model.ambilightVerticalOffset)) px")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { model.ambilightVerticalOffset },
                            set: { model.setAmbilightVerticalOffset($0) }
                        ),
                        in: 0...360,
                        step: 1
                    )
                    .disabled(model.selectedDevice == nil)
                }

                Text("Zone A follows the left side of the screen; Zone B follows the right side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isAmbilightZoneMappingSwapped {
                    Text("Swapped: Zone A follows right, Zone B follows left.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !model.hasScreenCapturePermission {
                    HStack(spacing: 8) {
                        Text("Screen Recording permission required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Open Settings") {
                            model.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var sceneControls: some View {
        ControlSection(title: "Scenes") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("Preset", selection: $model.selectedSceneID) {
                        ForEach(WiZScene.presets) { scene in
                            Text(scene.name).tag(scene.id)
                        }
                    }
                    .disabled(!model.canSend)

                    Button {
                        model.applySelectedScene()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Apply scene")
                    .disabled(!model.canSend)
                }

                HStack(spacing: 8) {
                    Text(model.currentSceneName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Slider(
                        value: Binding(
                            get: { Double(model.lightState.speed) },
                            set: { model.setSceneSpeed($0) }
                        ),
                        in: 20...200,
                        step: 1
                    )
                    .frame(maxWidth: 160)
                    .disabled(!model.canSend)

                    Text("\(model.lightState.speed)%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Button("Quit WiZ Light Bar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var selectedDevice: Binding<WiZDevice?> {
        Binding(
            get: { model.selectedDevice },
            set: { device in
                if let device {
                    model.select(device)
                }
            }
        )
    }
}

private struct ZonePreview: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: 34, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.separator, lineWidth: 1)
                )
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PresetButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(title)
            }
        }
        .buttonStyle(.bordered)
    }
}
