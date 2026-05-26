import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [WiZDevice] = []
    @Published var selectedDevice: WiZDevice?
    @Published var manualIPAddress: String = ""
    @Published var lightState = WiZLightState()
    @Published var selectedSceneID = WiZScene.presets[0].id
    @Published var isDiscovering = false
    @Published var isSending = false
    @Published var statusMessage = "Find the light bar on your network or enter its IP address manually."

    private let service = WiZUDPService()

    var canSend: Bool {
        selectedDevice != nil && !isSending
    }

    var currentSceneName: String {
        WiZScene.named(lightState.sceneId)?.name ?? "Custom"
    }

    func discover() {
        isDiscovering = true
        statusMessage = "Searching for WiZ devices on the local network..."

        Task {
            do {
                let foundDevices = try await service.discover()
                devices = foundDevices

                if let first = foundDevices.first {
                    selectedDevice = first
                    manualIPAddress = first.ipAddress
                    statusMessage = "Found \(first.displayName) at \(first.ipAddress)."
                    await refreshState()
                } else {
                    statusMessage = "No WiZ devices found. Make sure the light and Mac are on the same Wi-Fi network."
                }
            } catch {
                statusMessage = error.localizedDescription
            }

            isDiscovering = false
        }
    }

    func select(_ device: WiZDevice) {
        selectedDevice = device
        manualIPAddress = device.ipAddress
        statusMessage = "Selected \(device.displayName) at \(device.ipAddress)."

        Task {
            await refreshState()
        }
    }

    func useManualAddress() {
        let trimmedAddress = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            statusMessage = "Enter the light bar IP address."
            return
        }

        let device = WiZDevice(ipAddress: trimmedAddress, mac: "", moduleName: "WiZ Light Bar", firmwareVersion: "")
        if !devices.contains(device) {
            devices.append(device)
        }
        select(device)
    }

    func refreshState() async {
        guard let ipAddress = selectedDevice?.ipAddress else {
            return
        }

        isSending = true
        do {
            lightState = try await service.getPilot(ipAddress: ipAddress)
            if WiZScene.named(lightState.sceneId) != nil, let sceneId = lightState.sceneId {
                selectedSceneID = sceneId
            }
            statusMessage = "Updated state from \(ipAddress)."
        } catch {
            statusMessage = error.localizedDescription
        }
        isSending = false
    }

    func setPower(_ isOn: Bool) {
        lightState.isOn = isOn
        send { ipAddress in
            try await self.service.setPower(ipAddress: ipAddress, isOn: isOn)
        }
    }

    func setDimming(_ dimming: Double) {
        let value = Int(dimming.rounded()).clamped(to: 10...100)
        lightState.dimming = value
        send { ipAddress in
            try await self.service.setDimming(ipAddress: ipAddress, dimming: value)
        }
    }

    func setTemperature(_ kelvin: Double) {
        let value = Int(kelvin.rounded()).clamped(to: 2200...6500)
        lightState.temperature = value
        lightState.sceneId = nil
        send { ipAddress in
            try await self.service.setTemperature(ipAddress: ipAddress, kelvin: value, dimming: self.lightState.dimming)
        }
    }

    func setColor(_ color: Color) {
        lightState.color = color
        lightState.sceneId = nil
        let snapshot = lightState
        send { ipAddress in
            try await self.service.setColor(
                ipAddress: ipAddress,
                red: snapshot.red,
                green: snapshot.green,
                blue: snapshot.blue,
                dimming: snapshot.dimming
            )
        }
    }

    func setSceneSpeed(_ speed: Double) {
        lightState.speed = Int(speed.rounded()).clamped(to: 20...200)
    }

    func applySelectedScene() {
        lightState.isOn = true
        lightState.sceneId = selectedSceneID
        let snapshot = lightState
        let sceneID = selectedSceneID

        send { ipAddress in
            try await self.service.setScene(
                ipAddress: ipAddress,
                sceneId: sceneID,
                speed: snapshot.speed,
                dimming: snapshot.dimming
            )
        }
    }

    private func send(_ action: @escaping (String) async throws -> Void) {
        guard let ipAddress = selectedDevice?.ipAddress else {
            statusMessage = "Select a light bar first."
            return
        }

        isSending = true
        Task {
            do {
                try await action(ipAddress)
                statusMessage = "Command sent to \(ipAddress)."
            } catch {
                statusMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
