import AppKit
import Foundation
import OneCore

@main struct LiveImageCheck {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("colors.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<400 { for y in 0..<200 { bitmap.setColor(NSColor(deviceRed: x < 200 ? 1 : 0, green: 0, blue: x < 200 ? 0 : 1, alpha: 1), atX: x, y: y) } }
        try bitmap.representation(using: .png, properties: [:])!.write(to: image)
        for provider in ["Codex", "Claude"] {
            let runner = AgentRunner()
            let result: Int32 = await withCheckedContinuation { continuation in
                runner.start(agent: Agent(id: "image-check", name: "Image check", provider: provider, directory: root.path, managed: true), prompt: "This is an image delivery test. Without using tools or reading any files, identify the two solid colors in the attached image in left-to-right order. Reply with only those two color names.", image: image) { update in
                    switch update {
                    case .text(let text): print("\(provider): \(text)")
                    case .error(let error): print("\(provider) ERROR: \(error)")
                    case .finished(let status): continuation.resume(returning: status)
                    default: break
                    }
                }
            }
            print("\(provider) EXIT: \(result)")
        }
    }
}
