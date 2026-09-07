// Generates Resources/AppIcon.icns: a gradient squircle with a white waveform.
// Usage: swift scripts/make-icon.swift
import AppKit

let projectDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconsetDir = projectDir.appendingPathComponent(".build/AppIcon.iconset")
let resourcesDir = projectDir.appendingPathComponent("Resources")

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    return copy
}

func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)
    let inset = s * 0.09
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2),
        xRadius: s * 0.185, yRadius: s * 0.185
    )

    NSGradient(colors: [
        NSColor(calibratedRed: 0.32, green: 0.18, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.22, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.28, blue: 0.55, alpha: 1),
    ])?.draw(in: squircle, angle: -65)

    // A highlight across the top for the glassy look.
    squircle.addClip()
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.28),
        NSColor.white.withAlphaComponent(0.0),
    ])?.draw(
        in: NSRect(x: inset, y: s * 0.52, width: s - inset * 2, height: s * 0.39),
        angle: -90
    )

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.40, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let white = tinted(symbol, .white)
        let size = white.size
        let scale = (s * 0.52) / max(size.width, size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        white.draw(
            in: NSRect(
                x: (s - drawSize.width) / 2,
                y: (s - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ),
            from: .zero, operation: .sourceOver, fraction: 1
        )
    }

    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = renderIcon(pixels: variant.pixels) else {
        fatalError("Failed to render \(variant.name)")
    }
    try data.write(to: iconsetDir.appendingPathComponent("\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconsetDir.path,
    "-o", resourcesDir.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "AppIcon.icns is ready" : "iconutil failed")
