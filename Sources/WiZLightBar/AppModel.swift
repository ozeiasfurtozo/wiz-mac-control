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
    @Published var selectedControlMode: LightControlMode = .color
    @Published var isAmbilightEnabled = false
    @Published var hasScreenCapturePermission = false
    @Published var isAmbilightZoneMappingSwapped = false
    @Published var ambilightSideOffset: Double = 0
    @Published var ambilightVerticalOffset: Double = 0
    @Published var ambilightDisplays: [AmbilightDisplay] = []
    @Published var selectedAmbilightDisplayID: UInt32 = 0
    @Published var ambilightZoneAColor = RGBLightColor(red: 255, green: 214, blue: 170)
    @Published var ambilightZoneBColor = RGBLightColor(red: 255, green: 214, blue: 170)
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
        static let ambilightZoneMappingSwapped = "ambilightZoneMappingSwapped"
        static let ambilightSideOffset = "ambilightSideOffset"
        static let ambilightVerticalOffset = "ambilightVerticalOffset"
        static let ambilightDisplayID = "ambilightDisplayID"
        static let selectedControlMode = "selectedControlMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawMode = defaults.string(forKey: DefaultsKey.selectedControlMode),
           let mode = LightControlMode(rawValue: rawMode) {
            selectedControlMode = mode
        }
        hasScreenCapturePermission = screenSampler.hasScreenCaptureAccess
        isAmbilightZoneMappingSwapped = defaults.bool(forKey: DefaultsKey.ambilightZoneMappingSwapped)
        ambilightSideOffset = defaults.double(forKey: DefaultsKey.ambilightSideOffset).clamped(to: 0...360)
        ambilightVerticalOffset = defaults.double(forKey: DefaultsKey.ambilightVerticalOffset).clamped(to: 0...360)
        refreshAmbilightDisplays()
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
        selectedControlMode = .scenes

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
            setControlMode(.ambilight)
            startAmbilight()
        } else {
            stopAmbilight(statusMessage: "Ambilight mode stopped.")
        }
    }

    func setControlMode(_ mode: LightControlMode) {
        selectedControlMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.selectedControlMode)

        if mode != .ambilight {
            stopAmbilightIfNeeded()
        }
    }

    func setAmbilightZoneMappingSwapped(_ isSwapped: Bool) {
        isAmbilightZoneMappingSwapped = isSwapped
        defaults.set(isSwapped, forKey: DefaultsKey.ambilightZoneMappingSwapped)
        if isAmbilightEnabled {
            statusMessage = isSwapped ? "Ambilight zones swapped." : "Ambilight zones restored."
        }
    }

    func setAmbilightSideOffset(_ offset: Double) {
        let value = offset.rounded().clamped(to: 0...360)
        ambilightSideOffset = value
        defaults.set(value, forKey: DefaultsKey.ambilightSideOffset)
    }

    func setAmbilightVerticalOffset(_ offset: Double) {
        let value = offset.rounded().clamped(to: 0...360)
        ambilightVerticalOffset = value
        defaults.set(value, forKey: DefaultsKey.ambilightVerticalOffset)
    }

    func setAmbilightDisplay(_ displayID: UInt32) {
        selectedAmbilightDisplayID = displayID
        defaults.set(Int(displayID), forKey: DefaultsKey.ambilightDisplayID)
    }

    func refreshAmbilightDisplays() {
        ambilightDisplays = screenSampler.availableDisplays()

        let savedDisplayID = UInt32(defaults.integer(forKey: DefaultsKey.ambilightDisplayID))
        if savedDisplayID != 0, ambilightDisplays.contains(where: { $0.id == savedDisplayID }) {
            selectedAmbilightDisplayID = savedDisplayID
            return
        }

        let fallbackDisplay = ambilightDisplays.first(where: \.isMain) ?? ambilightDisplays.first
        selectedAmbilightDisplayID = fallbackDisplay?.id ?? CGMainDisplayID()
        defaults.set(Int(selectedAmbilightDisplayID), forKey: DefaultsKey.ambilightDisplayID)
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

        refreshAmbilightDisplays()
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
            var previousColors: AmbilightZoneColors?
            var failureCount = 0

            while !Task.isCancelled {
                guard let self else {
                    return
                }

                do {
                    previousColors = try await self.sendAmbilightFrame(previousColors: previousColors)
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

    private func sendAmbilightFrame(previousColors: AmbilightZoneColors?) async throws -> AmbilightZoneColors {
        guard let ipAddress = selectedDevice?.ipAddress else {
            throw AmbilightError.noSelectedDevice
        }

        let sampler = screenSampler
        let configuration = AmbilightSamplingConfiguration(
            sideOffset: ambilightSideOffset,
            verticalOffset: ambilightVerticalOffset,
            displayID: selectedAmbilightDisplayID
        )
        let sampledColors = try await Task.detached(priority: .utility) {
            try sampler.averageTwoZoneColors(configuration: configuration)
        }.value
        .enhanced(saturation: 1.35, brightness: 1.08)

        let screenColors = previousColors?.blended(with: sampledColors, amount: 0.38) ?? sampledColors
        let outputColors = isAmbilightZoneMappingSwapped
            ? AmbilightZoneColors(zoneA: screenColors.zoneB, zoneB: screenColors.zoneA)
            : screenColors

        try await service.setColor(
            ipAddress: ipAddress,
            red: outputColors.zoneA.red,
            green: outputColors.zoneA.green,
            blue: outputColors.zoneA.blue,
            dimming: lightState.dimming,
            zone: 1
        )

        try await service.setColor(
            ipAddress: ipAddress,
            red: outputColors.zoneB.red,
            green: outputColors.zoneB.green,
            blue: outputColors.zoneB.blue,
            dimming: lightState.dimming,
            zone: 2
        )

        lightState.isOn = true
        lightState.sceneId = nil
        lightState.red = (outputColors.zoneA.red + outputColors.zoneB.red) / 2
        lightState.green = (outputColors.zoneA.green + outputColors.zoneB.green) / 2
        lightState.blue = (outputColors.zoneA.blue + outputColors.zoneB.blue) / 2
        ambilightZoneAColor = outputColors.zoneA
        ambilightZoneBColor = outputColors.zoneB

        return screenColors
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
