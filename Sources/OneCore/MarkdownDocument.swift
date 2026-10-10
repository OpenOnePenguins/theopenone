import Foundation

/// Native Markdown structure with inline attributes retained inside each leaf.
public struct MarkdownBlock: Identifiable {
    public let id: Int
    public let kind: PresentationIntent.Kind
    public var text = AttributedString()
    public var children: [MarkdownBlock] = []
    public var checked: Bool?

    public var plainText: String { String(text.characters) }
}

public struct MarkdownDocument {
    public let blocks: [MarkdownBlock]

    public init(_ source: String) {
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else {
            blocks = [MarkdownBlock(id: -1, kind: .paragraph, text: AttributedString(source))]
            return
        }
        var result: [MarkdownBlock] = []
        var fallbackID = -1
        for run in parsed.runs {
            var part = AttributedString(parsed[run.range])
            // Chat messages retain deliberate line breaks, including Markdown soft breaks.
            if run.inlinePresentationIntent?.contains(.softBreak) == true { part = AttributedString("\n", attributes: run.attributes) }
            part.presentationIntent = nil
            if let image = run.imageURL { part.imageURL = nil; part.link = Self.readableLink(image) }
            if let link = part.link { part.link = Self.readableLink(link) }
            let path = Array(run.presentationIntent?.components.reversed() ?? [])
            if path.isEmpty {
                result.append(MarkdownBlock(id: fallbackID, kind: .paragraph, text: part)); fallbackID -= 1
            } else {
                Self.append(part, path: path[...], to: &result)
            }
        }
        Self.prepareTasks(&result)
        blocks = result.isEmpty && !source.isEmpty ? [MarkdownBlock(id: -1, kind: .paragraph, text: AttributedString(source))] : result
    }

    private static func readableLink(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "file"].contains(scheme) else { return nil }
        return url
    }

    private static func append(_ text: AttributedString, path: ArraySlice<PresentationIntent.IntentType>, to blocks: inout [MarkdownBlock]) {
        guard let component = path.first else { return }
        if blocks.last?.id != component.identity { blocks.append(MarkdownBlock(id: component.identity, kind: component.kind)) }
        let index = blocks.count - 1
        if path.count == 1 { blocks[index].text.append(text) }
        else { append(text, path: path.dropFirst(), to: &blocks[index].children) }
    }

    private static func prepareTasks(_ blocks: inout [MarkdownBlock]) {
        for i in blocks.indices {
            prepareTasks(&blocks[i].children)
            guard case .listItem = blocks[i].kind, let first = blocks[i].children.first,
                  case .paragraph = first.kind else { continue }
            let prefix = String(first.text.characters.prefix(4)).lowercased()
            guard prefix == "[x] " || prefix == "[ ] " else { continue }
            blocks[i].checked = prefix == "[x] "
            let start = first.text.characters.index(first.text.startIndex, offsetBy: 4)
            blocks[i].children[0].text = AttributedString(first.text[start...])
        }
    }
}
