import AppKit
import SwiftUI

/// Provider identity stays separate from the agent's activity/status badge.
struct ProviderLogo: View {
    let provider: String
    var size: CGFloat = 17

    private var key: String {
        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude", "claude code", "anthropic": return "claude"
        case "codex", "openai", "chatgpt": return "openai"
        case "opencode", "open code": return "opencode"
        case "pi": return "pi"
        default: return "agent"
        }
    }

    private static let images: [String: NSImage] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        var result: [String: NSImage] = [:]
        for key in ["claude", "openai", "opencode"] {
            if let url = bundle.url(forResource: "provider-\(key)", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                result[key] = image
            }
        }
        return result
    }()

    var body: some View {
        Group {
            if let image = Self.images[key] {
                Image(nsImage: image).resizable().scaledToFit()
            } else if key == "pi" {
                Text("π").font(.system(size: size, weight: .semibold, design: .serif))
            } else {
                Image(systemName: "terminal").resizable().scaledToFit()
            }
        }
        .foregroundStyle(key == "claude" ? Color(red: 0.851, green: 0.467, blue: 0.341) : .white)
        .frame(width: size, height: size)
        .accessibilityLabel(provider)
    }
}
