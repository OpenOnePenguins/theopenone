import AppKit
import SwiftUI

enum OpenOneBrand {
    // The PNG's head fills 88% of its width and about 70% of its height.
    // A 26-point toolbar box gives it the same ~18-point height as utility glyphs.
    static let toolbarSize: CGFloat = 26
    static let headingSize: CGFloat = 32
    static let emptyStateSize: CGFloat = 48
    static let image: NSImage? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "open-one-logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // Keep the white face and yellow beak in both light and dark appearances.
        image.isTemplate = false
        image.accessibilityDescription = "Open One"
        return image
    }()

    static var menuBarImage: NSImage? {
        guard let image = image?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 22, height: 22)
        return image
    }
}

struct BrandLogo: View {
    var size: CGFloat = OpenOneBrand.headingSize

    var body: some View {
        Group {
            if let image = OpenOneBrand.image {
                Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
            } else {
                Image(systemName: "bubble.left.and.bubble.right").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Open One")
    }
}
