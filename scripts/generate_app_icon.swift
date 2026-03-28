import AppKit
import Foundation

struct IconRenderer {
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func renderPNG(side: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "VoicePowerIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
        }

        bitmap.size = NSSize(width: side, height: side)

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "VoicePowerIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let cg = context.cgContext

        cg.setAllowsAntialiasing(true)
        cg.setShouldAntialias(true)
        cg.interpolationQuality = .high

        let canvas = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
        drawBackground(in: cg, rect: canvas)
        drawSymbol(in: cg, rect: canvas)

        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VoicePowerIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }

        return png
    }

    private func drawBackground(in cg: CGContext, rect: CGRect) {
        let radius = rect.width * 0.232
        let backgroundPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        cg.saveGState()
        cg.addPath(backgroundPath)
        cg.clip()

        drawLinearGradient(
            in: cg,
            colors: [
                color(hex: 0x1A2127).cgColor,
                color(hex: 0x0D1218).cgColor,
                color(hex: 0x05070B).cgColor
            ],
            locations: [0.0, 0.42, 1.0],
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY)
        )

        drawRadialGradient(
            in: cg,
            center: CGPoint(x: rect.midX, y: rect.height * 0.44),
            startRadius: 0,
            endRadius: rect.width * 0.42,
            colors: [
                color(hex: 0x0E7A86, alpha: 0.14).cgColor,
                color(hex: 0x0E7A86, alpha: 0.0).cgColor
            ],
            locations: [0.0, 1.0]
        )

        drawRadialGradient(
            in: cg,
            center: CGPoint(x: rect.width * 0.32, y: rect.height * 0.79),
            startRadius: 0,
            endRadius: rect.width * 0.34,
            colors: [
                color(hex: 0xFFFFFF, alpha: 0.11).cgColor,
                color(hex: 0xFFFFFF, alpha: 0.0).cgColor
            ],
            locations: [0.0, 1.0]
        )

        drawLinearGradient(
            in: cg,
            colors: [
                color(hex: 0xFFFFFF, alpha: 0.08).cgColor,
                color(hex: 0xFFFFFF, alpha: 0.0).cgColor
            ],
            locations: [0.0, 1.0],
            start: CGPoint(x: rect.width * 0.1, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.height * 0.56)
        )

        cg.restoreGState()

        cg.saveGState()
        cg.addPath(backgroundPath)
        cg.setLineWidth(max(1, rect.width * 0.006))
        cg.setStrokeColor(color(hex: 0xFFFFFF, alpha: 0.05).cgColor)
        cg.strokePath()
        cg.restoreGState()
    }

    private func drawSymbol(in cg: CGContext, rect: CGRect) {
        let strokeWidth = rect.width * 0.082
        let waveformGradient = [
            color(hex: 0xF7FCFF).cgColor,
            color(hex: 0xCFEFFF).cgColor,
            color(hex: 0x7EDCF7).cgColor
        ]
        let shadowColor = color(hex: 0x000000, alpha: 0.28).cgColor
        let glowColor = color(hex: 0x49E6FF, alpha: 0.42).cgColor

        let waveform = CGMutablePath()
        waveform.move(to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.50))
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.60),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * 0.50),
            control2: CGPoint(x: rect.width * 0.28, y: rect.height * 0.60)
        )
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.36, y: rect.height * 0.60),
            control2: CGPoint(x: rect.width * 0.39, y: rect.height * 0.40)
        )
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.67),
            control1: CGPoint(x: rect.width * 0.46, y: rect.height * 0.36),
            control2: CGPoint(x: rect.width * 0.49, y: rect.height * 0.67)
        )
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.34),
            control1: CGPoint(x: rect.width * 0.55, y: rect.height * 0.67),
            control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.34)
        )
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.74, y: rect.height * 0.56),
            control1: CGPoint(x: rect.width * 0.66, y: rect.height * 0.34),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.56)
        )
        waveform.addCurve(
            to: CGPoint(x: rect.width * 0.81, y: rect.height * 0.50),
            control1: CGPoint(x: rect.width * 0.77, y: rect.height * 0.56),
            control2: CGPoint(x: rect.width * 0.79, y: rect.height * 0.50)
        )

        cg.saveGState()
        cg.setLineWidth(strokeWidth * 0.92)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setShadow(offset: .zero, blur: rect.width * 0.09, color: glowColor)
        cg.addPath(waveform)
        cg.setStrokeColor(color(hex: 0xA7F7FF, alpha: 0.34).cgColor)
        cg.strokePath()
        cg.restoreGState()

        strokeWithShadow(in: cg, path: waveform, width: strokeWidth, color: shadowColor, blur: rect.width * 0.045)
        fillStrokedPath(
            in: cg,
            path: waveform,
            width: strokeWidth,
            colors: waveformGradient,
            locations: [0.0, 0.45, 1.0],
            start: CGPoint(x: rect.width * 0.18, y: rect.height * 0.66),
            end: CGPoint(x: rect.width * 0.82, y: rect.height * 0.34)
        )
    }

    private func strokeWithShadow(in cg: CGContext, path: CGPath, width: CGFloat, color: CGColor, blur: CGFloat) {
        cg.saveGState()
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setShadow(offset: CGSize(width: 0, height: -(width * 0.1)), blur: blur, color: color)
        cg.addPath(path)
        cg.setStrokeColor(color)
        cg.strokePath()
        cg.restoreGState()
    }

    private func fillStrokedPath(
        in cg: CGContext,
        path: CGPath,
        width: CGFloat,
        colors: [CGColor],
        locations: [CGFloat],
        start: CGPoint,
        end: CGPoint
    ) {
        let outlined = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)

        cg.saveGState()
        cg.addPath(outlined)
        cg.clip()
        drawLinearGradient(
            in: cg,
            colors: colors,
            locations: locations,
            start: start,
            end: end
        )
        cg.restoreGState()
    }

    private func drawLinearGradient(
        in cg: CGContext,
        colors: [CGColor],
        locations: [CGFloat],
        start: CGPoint,
        end: CGPoint
    ) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            return
        }

        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private func drawRadialGradient(
        in cg: CGContext,
        center: CGPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        colors: [CGColor],
        locations: [CGFloat]
    ) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            return
        }

        cg.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: startRadius,
            endCenter: center,
            endRadius: endRadius,
            options: []
        )
    }

    private func degrees(_ value: CGFloat) -> CGFloat {
        value * .pi / 180
    }

    private func color(hex: Int, alpha: CGFloat = 1.0) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
private let appDirectory = rootURL.appendingPathComponent("App", isDirectory: true)
private let iconPNGURL = appDirectory.appendingPathComponent("VoicePower-icon.png")

let renderer = IconRenderer()
let masterPNG = try renderer.renderPNG(side: 1024)
try masterPNG.write(to: iconPNGURL, options: .atomic)
print("Generated \(iconPNGURL.path)")
