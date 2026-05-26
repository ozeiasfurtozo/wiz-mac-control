import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            controls
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("WiZ Light Bar")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.discover()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Search for WiZ devices")
                .disabled(model.isDiscovering)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Manual IP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("192.168.1.50", text: $model.manualIPAddress)
                        .textFieldStyle(.roundedBorder)
                    Button("Use") {
                        model.useManualAddress()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            List(selection: Binding(
                get: { model.selectedDevice },
                set: { device in
                    if let device {
                        model.select(device)
                    }
                }
            )) {
                ForEach(model.devices) { device in
                    DeviceRow(device: device)
                        .tag(device)
                }
            }
            .overlay {
                if model.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No devices")
                            .font(.headline)
                        Text("Search or enter the IP address.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 300)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.selectedDevice?.displayName ?? "No light bar selected")
                        .font(.largeTitle.weight(.semibold))
                    Text(model.selectedDevice?.ipAddress ?? "Connect a WiZ device to enable controls.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("On", isOn: Binding(
                    get: { model.lightState.isOn },
                    set: { model.setPower($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!model.canSend)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    ControlSection(title: "Brightness") {
                        Slider(
                            value: Binding(
                                get: { Double(model.lightState.dimming) },
                                set: { model.setDimming($0) }
                            ),
                            in: 10...100,
                            step: 1
                        )
                        Text("\(model.lightState.dimming)%")
                            .font(.title3.monospacedDigit().weight(.medium))
                    }

                    ControlSection(title: "Temperature") {
                        Slider(
                            value: Binding(
                                get: { Double(model.lightState.temperature) },
                                set: { model.setTemperature($0) }
                            ),
                            in: 2200...6500,
                            step: 50
                        )
                        Text("\(model.lightState.temperature) K")
                            .font(.title3.monospacedDigit().weight(.medium))
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    ControlSection(title: "Color") {
                        ColorPicker(
                            "RGB",
                            selection: Binding(
                                get: { model.lightState.color },
                                set: { model.setColor($0) }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 64, height: 36)

                        Text("R \(model.lightState.red)  G \(model.lightState.green)  B \(model.lightState.blue)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
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
                }
            }

            ControlSection(title: "Scenes") {
                HStack(spacing: 12) {
                    Picker("Preset", selection: $model.selectedSceneID) {
                        ForEach(WiZScene.presets) { scene in
                            Text(scene.name).tag(scene.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)

                    Button {
                        model.applySelectedScene()
                    } label: {
                        Label("Apply", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSend)

                    Spacer()

                    Text(model.currentSceneName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("Speed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { Double(model.lightState.speed) },
                            set: { model.setSceneSpeed($0) }
                        ),
                        in: 20...200,
                        step: 1
                    )

                    Text("\(model.lightState.speed)%")
                        .font(.callout.monospacedDigit().weight(.medium))
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Spacer()

            HStack {
                Button {
                    Task {
                        await model.refreshState()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canSend)

                Spacer()

                if model.isDiscovering || model.isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(28)
    }
}

private struct DeviceRow: View {
    let device: WiZDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.displayName)
                .font(.headline)
            Text(device.ipAddress)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if !device.firmwareVersion.isEmpty {
                Text("Firmware \(device.firmwareVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
        .padding(16)
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
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
            }
        }
        .buttonStyle(.bordered)
    }
}
