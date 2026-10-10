import AppKit
import Foundation

// Rasterize the desktop's vector marks at 4× their largest mobile display size.
// This keeps the exact same artwork available to native and web Image components.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("mobile/assets/providers")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for name in ["claude", "openai", "opencode"] {
    let source = root.appendingPathComponent("Sources/OpenOne/Assets/provider-\(name).svg")
    guard let image = NSImage(contentsOf: source),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not render \(name)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode \(name)") }
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
print("Mobile provider marks generated from desktop SVGs")
