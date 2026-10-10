import Foundation
import CoreGraphics
import ImageIO

// Platform packaging only: every export uses the approved PNG's pixels and geometry.
// Never redraw the mascot or generate independent copies of its design here.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Sources/OpenOne/Assets/open-one-logo.png")
let sourceData = try Data(contentsOf: sourceURL)
guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read the canonical Open One logo")
}
let checkOnly = CommandLine.arguments.contains("--check")
var stale: [String] = []

func save(_ data: Data, to path: String) throws {
    let url = root.appendingPathComponent(path)
    if (try? Data(contentsOf: url)) == data { return }
    if checkOnly { stale.append(path); return }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    print("Updated \(path)")
}

func png(size: Int, scale: CGFloat = 1, opaque: Bool = false, monochrome: Bool = false, backgroundOnly: Bool = false) throws -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: colorSpace, bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let side = CGFloat(size)
    if opaque {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    if !backgroundOnly {
        let inset = side * (1 - scale) / 2
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: inset, y: inset, width: side * scale, height: side * scale))
    }
    if monochrome, let pixels = context.data?.assumingMemoryBound(to: UInt8.self) {
        // Android themed icons use alpha as an ink mask. Remove the white face
        // from the mask so the eyes and beak survive the system's single tint.
        for i in stride(from: 0, to: size * size * 4, by: 4) {
            let a = Double(pixels[i + 3])
            let luminance = a == 0 ? 1 : (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / a
            let ink = min(1, max(0, (0.90 - luminance) / 0.25))
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0
            pixels[i + 3] = UInt8((a * ink).rounded())
        }
    }
    guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

try save(png(size: 64), to: "Sources/OpenOne/Assets/open-one-favicon.png")
try save(png(size: 180, scale: 0.88, opaque: true), to: "Sources/OpenOne/Assets/open-one-touch-icon.png")
if FileManager.default.fileExists(atPath: root.appendingPathComponent("landing").path) {
    try save(sourceData, to: "landing/assets/open-one-logo.png")
    try save(png(size: 64), to: "landing/assets/favicon.png")
    try save(png(size: 180, scale: 0.88, opaque: true), to: "landing/assets/apple-touch-icon.png")
}
if FileManager.default.fileExists(atPath: root.appendingPathComponent("mobile").path) {
    try save(sourceData, to: "mobile/assets/open-one-logo.png")
    // Keep the earlier mobile asset path in sync for existing consumers.
    try save(sourceData, to: "mobile/assets/open-one.png")
    try save(png(size: 1024, scale: 0.88, opaque: true), to: "mobile/assets/icon.png")
    // 60% canvas scale keeps the complete head within Android's masked safe area.
    try save(png(size: 1024, scale: 0.60), to: "mobile/assets/android-icon-foreground.png")
    try save(png(size: 1024, scale: 0.60, monochrome: true), to: "mobile/assets/android-icon-monochrome.png")
    try save(png(size: 1024, opaque: true, backgroundOnly: true), to: "mobile/assets/android-icon-background.png")
    try save(png(size: 1024), to: "mobile/assets/splash-icon.png")
    try save(png(size: 64), to: "mobile/assets/favicon.png")
}
if !stale.isEmpty {
    fputs("Stale branding assets; run bash scripts/sync-brand-assets.sh:\n\(stale.joined(separator: "\n"))\n", stderr)
    exit(1)
}
print(checkOnly ? "All branding exports match the canonical logo." : "Branding assets synchronized.")
