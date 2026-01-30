#!/usr/bin/env swift

import AppKit
import CoreGraphics

// MARK: - Configuration

let size = CGSize(width: 1024, height: 1024)

// Apple Fitness green palette
let gradientStartColor = NSColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)  // #34C759
let gradientEndColor = NSColor(red: 48/255, green: 209/255, blue: 88/255, alpha: 1)    // #30D158

// MARK: - Icon Generation

/// Generates the app icon with a health-focused green gradient background
/// and a centered walking figure symbol (figure.walk)
func generateAppIcon() -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Draw gradient background
    let colors = [gradientStartColor.cgColor, gradientEndColor.cgColor]
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    ) else {
        image.unlockFocus()
        return image
    }

    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size.height),
        end: CGPoint(x: size.width, y: 0),
        options: []
    )

    // Draw walking figure symbol
    let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
        .applying(.init(paletteColors: [.white]))

    if let symbol = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Walking figure")?
        .withSymbolConfiguration(config) {

        // Calculate centered position
        let symbolSize = symbol.size
        let x = (size.width - symbolSize.width) / 2
        let y = (size.height - symbolSize.height) / 2

        // Draw the symbol
        symbol.draw(
            in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    image.unlockFocus()
    return image
}

/// Saves an NSImage as PNG to the specified path
func saveImage(_ image: NSImage, to path: String) -> Bool {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Failed to create CGImage")
        return false
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    bitmapRep.size = image.size

    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return false
    }

    let url = URL(fileURLWithPath: path)

    do {
        try pngData.write(to: url)
        print("Saved: \(path)")
        return true
    } catch {
        print("Failed to write \(path): \(error)")
        return false
    }
}

// MARK: - Main

print("Generating AI Pedometer app icons...")
print("Size: \(Int(size.width))x\(Int(size.height))")

let icon = generateAppIcon()

// Get the script's directory to find the project root
let scriptPath = CommandLine.arguments[0]
let scriptDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()

// Output paths
let iosIconPath = projectRoot
    .appendingPathComponent("AIPedometer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    .path

let watchIconPath = projectRoot
    .appendingPathComponent("AIPedometerWatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    .path

var success = true

if saveImage(icon, to: iosIconPath) {
    print("iOS icon generated successfully")
} else {
    print("Failed to generate iOS icon")
    success = false
}

if saveImage(icon, to: watchIconPath) {
    print("watchOS icon generated successfully")
} else {
    print("Failed to generate watchOS icon")
    success = false
}

if success {
    print("\nApp icons generated successfully!")
    print("Run 'xcodegen generate' to regenerate the Xcode project.")
} else {
    print("\nSome icons failed to generate.")
    exit(1)
}
