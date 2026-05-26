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

    func averageCornerColor() throws -> RGBLightColor {
        guard hasScreenCaptureAccess else {
            throw ScreenCornerSamplerError.screenCapturePermissionDenied
        }

        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let sampleSide = min(max(min(bounds.width, bounds.height) * 0.16, 96), 220)

        let sampleRects = [
            CGRect(x: bounds.minX, y: bounds.minY, width: sampleSide, height: sampleSide),
            CGRect(x: bounds.maxX - sampleSide, y: bounds.minY, width: sampleSide, height: sampleSide),
            CGRect(x: bounds.minX, y: bounds.maxY - sampleSide, width: sampleSide, height: sampleSide),
            CGRect(x: bounds.maxX - sampleSide, y: bounds.maxY - sampleSide, width: sampleSide, height: sampleSide)
        ]

        let colors = try sampleRects.map { rect in
            guard let image = CGDisplayCreateImage(displayID, rect: rect) else {
                throw ScreenCornerSamplerError.captureFailed
            }
            return try averageColor(in: image)
        }

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
