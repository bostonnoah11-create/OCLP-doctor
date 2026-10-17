#!/usr/bin/env swift
import AppKit
import Foundation

// Deterministic vector rasterization only. No app launch, screen capture, or network access.
// Usage: swift Scripts/render-icon.swift Assets/AppIcon.svg Assets/AppIconPreview.png [1024]
let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4,
      let side = Int(arguments.count == 4 ? arguments[3] : "1024"), side > 0, side <= 4096 else {
    fputs("Usage: render-icon.swift input.svg output.png [size 1...4096]\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
guard input.pathExtension.lowercased() == "svg", output.pathExtension.lowercased() == "png",
      let source = NSImage(contentsOf: input) else {
    fputs("Could not read the SVG input.\n", stderr)
    exit(1)
}
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
    pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: side * 4, bitsPerPixel: 32),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the output bitmap.\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
source.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the PNG output.\n", stderr)
    exit(1)
}
do {
    try data.write(to: output, options: .atomic)
    print("Rendered \(side) × \(side) PNG from SVG.")
} catch {
    fputs("Could not write the PNG output.\n", stderr)
    exit(1)
}
