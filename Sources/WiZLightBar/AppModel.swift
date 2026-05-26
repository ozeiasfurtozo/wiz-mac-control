import AppKit
import Foundation
import SwiftUI

private enum AmbilightError: LocalizedError {
    case noSelectedDevice

    var errorDescription: String? {
        switch self {
        case .noSelectedDevice:
            return "Select a light bar first."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [WiZDevice] = []
    @Published var selectedDevice: WiZDevice?
    @Published var manualIPAddress: String = ""
    @Published var lightState = WiZLightState()
    @Published var selectedSceneID = WiZScene.presets[0].id
    @Published var isDiscovering = false
    @Published var isSending = false
    @Published var isAmbilightEnabled = false
    @Published var hasScreenCapturePermission = false
    @Published var ambilightColor = RGBLightColor(red: 255, green: 214, blue: 170)
    @Published var statusMessage = "Find the light bar on your network or enter its IP address manually."

    private let service = WiZUDPService()
    private let screenSampler = ScreenCornerSampler()
    private let defaults: UserDefaults
    private var ambilightTask: Task<Void, Never>?

    private enum DefaultsKey {
        static let lastDeviceIPAddress = "lastDeviceIPAddress"
        static let lastDeviceMAC = "lastDeviceMAC"
        static let lastDeviceModuleName = "lastDeviceModuleName"
        static let lastDeviceFirmwareVersion = "lastDeviceFirmwareVersion"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasScreenCapturePermission = screenSampler.hasScreenCaptureAccess
        restoreLastDevice()
    }

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

                if let device = preferredDevice(from: foundDevices) {
                    select(device)
                    statusMessage = "Found \(device.displayName) at \(device.ipAddress)."
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
        saveLastDevice(device)
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
        if !isOn {
            stopAmbilight(statusMessage: "Ambilight mode stopped.")
        }

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
        stopAmbilightIfNeeded()

        let value = Int(kelvin.rounded()).clamped(to: 2200...6500)
        lightState.temperature = value
        lightState.sceneId = nil
        send { ipAddress in
            try await self.service.setTemperature(ipAddress: ipAddress, kelvin: value, dimming: self.lightState.dimming)
        }
    }

    func setColor(_ color: Color) {
        stopAmbilightIfNeeded()

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
        stopAmbilightIfNeeded()

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

    func setAmbilightEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startAmbilight()
        } else {
            stopAmbilight(statusMessage: "Ambilight mode stopped.")
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
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

    private func startAmbilight() {
        guard selectedDevice != nil else {
            isAmbilightEnabled = false
            statusMessage = "Select a light bar first."
            return
        }

        hasScreenCapturePermission = screenSampler.hasScreenCaptureAccess
        if !hasScreenCapturePermission {
            hasScreenCapturePermission = screenSampler.requestScreenCaptureAccess()
        }

        guard hasScreenCapturePermission else {
            isAmbilightEnabled = false
            statusMessage = "Allow Screen Recording for WiZ Light Bar, then enable Ambilight again."
            return
        }

        ambilightTask?.cancel()
        isAmbilightEnabled = true
        lightState.isOn = true
        lightState.sceneId = nil
        statusMessage = "Ambilight mode active."

        ambilightTask = Task { [weak self] in
            var previousColor: RGBLightColor?
            var failureCount = 0

            while !Task.isCancelled {
                guard let self else {
                    return
                }

                do {
                    previousColor = try await self.sendAmbilightFrame(previousColor: previousColor)
                    failureCount = 0
                } catch {
                    failureCount += 1
                    self.handleAmbilightError(error, shouldStop: failureCount >= 3)
                }

                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        }
    }

    private func stopAmbilightIfNeeded() {
        guard isAmbilightEnabled else {
            return
        }
        stopAmbilight(statusMessage: "Ambilight mode stopped.")
    }

    private func stopAmbilight(statusMessage message: String) {
        ambilightTask?.cancel()
        ambilightTask = nil
        isAmbilightEnabled = false
        statusMessage = message
    }

    private func sendAmbilightFrame(previousColor: RGBLightColor?) async throws -> RGBLightColor {
        guard let ipAddress = selectedDevice?.ipAddress else {
            throw AmbilightError.noSelectedDevice
        }

        let sampler = screenSampler
        let sampledColor = try await Task.detached(priority: .utility) {
            try sampler.averageCornerColor()
        }.value
        .enhanced(saturation: 1.35, brightness: 1.08)

        let outputColor = previousColor?.blended(with: sampledColor, amount: 0.38) ?? sampledColor

        try await service.setColor(
            ipAddress: ipAddress,
            red: outputColor.red,
            green: outputColor.green,
            blue: outputColor.blue,
            dimming: lightState.dimming
        )

        lightState.isOn = true
        lightState.sceneId = nil
        lightState.red = outputColor.red
        lightState.green = outputColor.green
        lightState.blue = outputColor.blue
        ambilightColor = outputColor

        return outputColor
    }

    private func handleAmbilightError(_ error: Error, shouldStop: Bool) {
        if error is ScreenCornerSamplerError {
            hasScreenCapturePermission = screenSampler.hasScreenCaptureAccess
        }

        if error is ScreenCornerSamplerError || error is AmbilightError || shouldStop {
            stopAmbilight(statusMessage: "\(error.localizedDescription) Ambilight mode stopped.")
            return
        }

        statusMessage = error.localizedDescription
    }

    private func restoreLastDevice() {
        guard let ipAddress = defaults.string(forKey: DefaultsKey.lastDeviceIPAddress),
              !ipAddress.isEmpty else {
            return
        }

        let device = WiZDevice(
            ipAddress: ipAddress,
            mac: defaults.string(forKey: DefaultsKey.lastDeviceMAC) ?? "",
            moduleName: defaults.string(forKey: DefaultsKey.lastDeviceModuleName) ?? "WiZ Light Bar",
            firmwareVersion: defaults.string(forKey: DefaultsKey.lastDeviceFirmwareVersion) ?? ""
        )

        devices = [device]
        selectedDevice = device
        manualIPAddress = ipAddress
        statusMessage = "Restored \(device.displayName) at \(ipAddress)."

        Task {
            await refreshState()
        }
    }

    private func saveLastDevice(_ device: WiZDevice) {
        defaults.set(device.ipAddress, forKey: DefaultsKey.lastDeviceIPAddress)
        defaults.set(device.mac, forKey: DefaultsKey.lastDeviceMAC)
        defaults.set(device.moduleName, forKey: DefaultsKey.lastDeviceModuleName)
        defaults.set(device.firmwareVersion, forKey: DefaultsKey.lastDeviceFirmwareVersion)
    }

    private func preferredDevice(from foundDevices: [WiZDevice]) -> WiZDevice? {
        if let savedIPAddress = defaults.string(forKey: DefaultsKey.lastDeviceIPAddress),
           let savedDevice = foundDevices.first(where: { $0.ipAddress == savedIPAddress }) {
            return savedDevice
        }

        return foundDevices.first
    }
}
