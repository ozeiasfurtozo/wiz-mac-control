import Foundation
import SwiftUI

struct WiZDevice: Identifiable, Hashable {
    var id: String { mac.isEmpty ? ipAddress : mac }

    let ipAddress: String
    let mac: String
    let moduleName: String
    let firmwareVersion: String

    var displayName: String {
        if !moduleName.isEmpty {
            return moduleName
        }
        if !mac.isEmpty {
            return "WiZ \(mac.suffix(4))"
        }
        return "WiZ Light"
    }
}

struct WiZLightState: Equatable {
    var isOn: Bool = false
    var dimming: Int = 80
    var temperature: Int = 3000
    var red: Int = 255
    var green: Int = 214
    var blue: Int = 170
    var sceneId: Int?
    var speed: Int = 100

    var color: Color {
        get {
            Color(
                red: Double(red) / 255.0,
                green: Double(green) / 255.0,
                blue: Double(blue) / 255.0
            )
        }
        set {
            let nativeColor = NSColor(newValue).usingColorSpace(.deviceRGB) ?? .white
            red = Int((nativeColor.redComponent * 255.0).rounded()).clamped(to: 0...255)
            green = Int((nativeColor.greenComponent * 255.0).rounded()).clamped(to: 0...255)
            blue = Int((nativeColor.blueComponent * 255.0).rounded()).clamped(to: 0...255)
        }
    }
}

struct RGBLightColor: Equatable {
    var red: Int
    var green: Int
    var blue: Int

    var color: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }

    func blended(with target: RGBLightColor, amount: Double) -> RGBLightColor {
        let normalizedAmount = amount.clamped(to: 0.0...1.0)
        return RGBLightColor(
            red: blend(red, target.red, amount: normalizedAmount),
            green: blend(green, target.green, amount: normalizedAmount),
            blue: blend(blue, target.blue, amount: normalizedAmount)
        )
    }

    func enhanced(saturation: Double, brightness: Double) -> RGBLightColor {
        let color = NSColor(
            deviceRed: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            alpha: 1.0
        )

        var hue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &currentSaturation, brightness: &currentBrightness, alpha: &alpha)

        let adjusted = NSColor(
            calibratedHue: hue,
            saturation: (currentSaturation * saturation).clamped(to: 0.0...1.0),
            brightness: (currentBrightness * brightness).clamped(to: 0.04...1.0),
            alpha: alpha
        )

        guard let rgb = adjusted.usingColorSpace(.deviceRGB) else {
            return self
        }

        return RGBLightColor(
            red: Int((rgb.redComponent * 255.0).rounded()).clamped(to: 0...255),
            green: Int((rgb.greenComponent * 255.0).rounded()).clamped(to: 0...255),
            blue: Int((rgb.blueComponent * 255.0).rounded()).clamped(to: 0...255)
        )
    }

    private func blend(_ current: Int, _ target: Int, amount: Double) -> Int {
        Int((Double(current) + (Double(target) - Double(current)) * amount).rounded()).clamped(to: 0...255)
    }
}

struct AmbilightZoneColors: Equatable {
    var zoneA: RGBLightColor
    var zoneB: RGBLightColor

    func blended(with target: AmbilightZoneColors, amount: Double) -> AmbilightZoneColors {
        AmbilightZoneColors(
            zoneA: zoneA.blended(with: target.zoneA, amount: amount),
            zoneB: zoneB.blended(with: target.zoneB, amount: amount)
        )
    }

    func enhanced(saturation: Double, brightness: Double) -> AmbilightZoneColors {
        AmbilightZoneColors(
            zoneA: zoneA.enhanced(saturation: saturation, brightness: brightness),
            zoneB: zoneB.enhanced(saturation: saturation, brightness: brightness)
        )
    }
}

struct AmbilightSamplingConfiguration: Equatable {
    var sideOffset: Double = 0
    var verticalOffset: Double = 0
    var displayID: UInt32 = 0
}

struct AmbilightDisplay: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let isMain: Bool

    var displayName: String {
        isMain ? "\(name) (Main)" : name
    }
}

enum LightControlMode: String, CaseIterable, Identifiable {
    case ambilight
    case color
    case scenes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ambilight:
            return "Ambilight"
        case .color:
            return "Color"
        case .scenes:
            return "Scenes"
        }
    }
}

struct WiZScene: Identifiable, Hashable {
    let id: Int
    let name: String

    static let presets: [WiZScene] = [
        WiZScene(id: 1, name: "Ocean"),
        WiZScene(id: 2, name: "Romance"),
        WiZScene(id: 3, name: "Sunset"),
        WiZScene(id: 4, name: "Party"),
        WiZScene(id: 5, name: "Fireplace"),
        WiZScene(id: 6, name: "Cozy"),
        WiZScene(id: 7, name: "Forest"),
        WiZScene(id: 8, name: "Pastel Colors"),
        WiZScene(id: 9, name: "Wake up"),
        WiZScene(id: 10, name: "Bedtime"),
        WiZScene(id: 11, name: "Warm white"),
        WiZScene(id: 12, name: "Daylight"),
        WiZScene(id: 13, name: "Cool white"),
        WiZScene(id: 14, name: "Night light"),
        WiZScene(id: 15, name: "Focus"),
        WiZScene(id: 16, name: "Relax"),
        WiZScene(id: 17, name: "True colors"),
        WiZScene(id: 18, name: "TV Time"),
        WiZScene(id: 19, name: "Plant growth"),
        WiZScene(id: 20, name: "Spring"),
        WiZScene(id: 21, name: "Summer"),
        WiZScene(id: 22, name: "Fall"),
        WiZScene(id: 23, name: "Deep dive"),
        WiZScene(id: 24, name: "Jungle"),
        WiZScene(id: 25, name: "Mojito"),
        WiZScene(id: 26, name: "Club"),
        WiZScene(id: 27, name: "Christmas"),
        WiZScene(id: 28, name: "Halloween"),
        WiZScene(id: 29, name: "Candlelight"),
        WiZScene(id: 30, name: "Golden white"),
        WiZScene(id: 31, name: "Pulse"),
        WiZScene(id: 32, name: "Steampunk"),
        WiZScene(id: 33, name: "Diwali")
    ]

    static func named(_ id: Int?) -> WiZScene? {
        guard let id else {
            return nil
        }
        return presets.first { $0.id == id }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
