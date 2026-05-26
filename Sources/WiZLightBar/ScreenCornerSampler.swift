import AppKit
import CoreGraphics
import Foundation

enum ScreenCornerSamplerError: LocalizedError {
    case screenCapturePermissionDenied
    case captureFailed
    case bitmapContextFailed

    var errorDescription: String? {
        switch self {
        case .screenCapturePermissionDenied:
            return "Screen Recording permission is required for Ambilight mode."
        case .captureFailed:
            return "Could not capture the screen corners."
        case .bitmapContextFailed:
            return "Could not read the screen corner colors."
        }
    }
}

struct ScreenCornerSampler {
    private let thumbnailSize = 14

    var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func availableDisplays() -> [AmbilightDisplay] {
        let screens = NSScreen.screens
        let displays = screens.enumerated().compactMap { index, screen -> AmbilightDisplay? in
            guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            return AmbilightDisplay(
                id: displayNumber.uint32Value,
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                isMain: screen === NSScreen.main
            )
        }

        if !displays.isEmpty {
            return displays
        }

        return [
            AmbilightDisplay(
                id: CGMainDisplayID(),
                name: "Main Display",
                isMain: true
            )
        ]
    }

    func averageCornerColor() throws -> RGBLightColor {
        let colors = try averageTwoZoneColors()
        return average(colors: [colors.zoneA, colors.zoneB])
    }

    func averageTwoZoneColors(configuration: AmbilightSamplingConfiguration = AmbilightSamplingConfiguration()) throws -> AmbilightZoneColors {
        guard hasScreenCaptureAccess else {
            throw ScreenCornerSamplerError.screenCapturePermissionDenied
        }

        let displayID = configuration.displayID == 0 ? CGMainDisplayID() : CGDirectDisplayID(configuration.displayID)
        let bounds = CGDisplayBounds(displayID)
        let sampleSide = min(max(min(bounds.width, bounds.height) * 0.16, 96), 220)
        let sideOffset = configuration.sideOffset.clamped(to: 0...max(bounds.width / 2 - sampleSide, 0))
        let verticalOffset = configuration.verticalOffset.clamped(to: 0...max(bounds.height / 2 - sampleSide, 0))

        let leftRects = [
            CGRect(x: bounds.minX + sideOffset, y: bounds.minY + verticalOffset, width: sampleSide, height: sampleSide),
            CGRect(x: bounds.minX + sideOffset, y: bounds.maxY - sampleSide - verticalOffset, width: sampleSide, height: sampleSide)
        ]
        let rightRects = [
            CGRect(x: bounds.maxX - sampleSide - sideOffset, y: bounds.minY + verticalOffset, width: sampleSide, height: sampleSide),
            CGRect(x: bounds.maxX - sampleSide - sideOffset, y: bounds.maxY - sampleSide - verticalOffset, width: sampleSide, height: sampleSide)
        ]

        return AmbilightZoneColors(
            zoneA: try averageColor(in: leftRects, displayID: displayID),
            zoneB: try averageColor(in: rightRects, displayID: displayID)
        )
    }

    private func averageColor(in rects: [CGRect], displayID: CGDirectDisplayID) throws -> RGBLightColor {
        let colors = try rects.map { rect in
            guard let image = CGDisplayCreateImage(displayID, rect: rect) else {
                throw ScreenCornerSamplerError.captureFailed
            }
            return try averageColor(in: image)
        }

        return average(colors: colors)
    }

    private func average(colors: [RGBLightColor]) -> RGBLightColor {
        let red = colors.reduce(0) { $0 + $1.red } / colors.count
        let green = colors.reduce(0) { $0 + $1.green } / colors.count
        let blue = colors.reduce(0) { $0 + $1.blue } / colors.count

        return RGBLightColor(red: red, green: green, blue: blue)
    }

    private func averageColor(in image: CGImage) throws -> RGBLightColor {
        let width = thumbnailSize
        let height = thumbnailSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let color = pixels.withUnsafeMutableBytes { rawBuffer -> RGBLightColor? in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return nil
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var redTotal = 0
            var greenTotal = 0
            var blueTotal = 0

            for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
                redTotal += Int(bytes[index])
                greenTotal += Int(bytes[index + 1])
                blueTotal += Int(bytes[index + 2])
            }

            let count = width * height
            return RGBLightColor(
                red: redTotal / count,
                green: greenTotal / count,
                blue: blueTotal / count
            )
        }

        guard let color else {
            throw ScreenCornerSamplerError.bitmapContextFailed
        }

        return color
    }
}
