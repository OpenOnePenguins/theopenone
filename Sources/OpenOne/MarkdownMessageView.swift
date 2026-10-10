import SwiftUI
import OneCore

struct MarkdownMessageView: View {
    let text: String
    var fontSize: CGFloat = 16
    var copyCode: ((String) -> Void)?

    init(_ text: String, fontSize: CGFloat = 16, copyCode: ((String) -> Void)? = nil) {
        self.text = text; self.fontSize = fontSize; self.copyCode = copyCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownCache.document(text).blocks) { block in
                MarkdownBlockView(block: block, fontSize: fontSize, copyCode: copyCode)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let fontSize: CGFloat
    let copyCode: ((String) -> Void)?
    var ordered = false

    @ViewBuilder var body: some View {
        switch block.kind {
        case .header(let level):
            inline(block.text, size: fontSize + CGFloat(max(0, 4 - level) * 2), weight: .semibold)
                .padding(.top, 3).accessibilityAddTraits(.isHeader)
        case .codeBlock(let language):
            MarkdownCodeBlock(code: block.plainText, language: language, fontSize: fontSize, copyCode: copyCode)
        case .unorderedList, .orderedList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(block.children) { child in
                    AnyView(MarkdownBlockView(block: child, fontSize: fontSize, copyCode: copyCode, ordered: block.kind == .orderedList))
                }
            }
        case .listItem(let ordinal):
            HStack(alignment: .top, spacing: 7) {
                Group {
                    if let checked = block.checked {
                        Image(systemName: checked ? "checkmark.square" : "square").accessibilityLabel(checked ? "Completed" : "Not completed")
                    } else { Text(ordered ? "\(ordinal)." : "•").monospacedDigit() }
                }.font(.system(size: fontSize)).foregroundStyle(.secondary).frame(minWidth: 19, alignment: .trailing)
                children
            }
        case .blockQuote:
            HStack(spacing: 10) {
                Rectangle().fill(.white.opacity(0.28)).frame(width: 3)
                children.foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case .thematicBreak:
            Divider().padding(.vertical, 3)
        case .table(let columns):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    ForEach(block.children) { row in
                        GridRow {
                            ForEach(columns.indices, id: \.self) { index in
                                let cell = row.children.first { $0.kind == .tableCell(columnIndex: index) }
                                inline(cell?.text ?? AttributedString(), size: fontSize - 1, weight: row.kind == .tableHeaderRow ? .semibold : .regular)
                                    .frame(minWidth: 65, maxWidth: 240, alignment: alignment(columns[index].alignment))
                                    .gridColumnAlignment(horizontalAlignment(columns[index].alignment))
                            }
                        }
                    }
                }.padding(10)
            }.background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        default:
            if !block.children.isEmpty { children }
            else { inline(block.text, size: fontSize) }
        }
    }

    private var children: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(block.children) { child in
                AnyView(MarkdownBlockView(block: child, fontSize: fontSize, copyCode: copyCode))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ value: AttributedString, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        var styled = value
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            styled[run.range].font = .system(size: max(10, size - 1), design: .monospaced)
            styled[run.range].backgroundColor = .white.opacity(0.08)
        }
        return Text(styled).font(.system(size: size, weight: weight)).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true).tint(.blue)
    }

    private func horizontalAlignment(_ alignment: PresentationIntent.TableColumn.Alignment) -> HorizontalAlignment {
        switch alignment { case .center: return .center; case .right: return .trailing; default: return .leading }
    }
    private func alignment(_ alignment: PresentationIntent.TableColumn.Alignment) -> Alignment {
        switch alignment { case .center: return .center; case .right: return .trailing; default: return .leading }
    }
}

private struct MarkdownCodeBlock: View {
    let code: String
    let language: String?
    let fontSize: CGFloat
    let copyCode: ((String) -> Void)?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language?.isEmpty == false ? language! : "Code").lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let copyCode { copyCode(code) }
                    else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).accessibilityLabel("Copy code")
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if !Task.isCancelled { copied = false }
                    }
            }.font(.system(size: 11))
            ScrollView(.horizontal) {
                Text(verbatim: code.hasSuffix("\n") ? String(code.dropLast()) : code)
                    .font(.system(size: max(11, fontSize - 2), design: .monospaced)).lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: true).textSelection(.enabled)
            }
        }.padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private final class MarkdownDocumentBox: NSObject {
    let document: MarkdownDocument
    init(_ source: String) { document = MarkdownDocument(source) }
}

private enum MarkdownCache {
    static let storage: NSCache<NSString, MarkdownDocumentBox> = {
        let cache = NSCache<NSString, MarkdownDocumentBox>()
        cache.countLimit = 128; cache.totalCostLimit = 2_000_000
        return cache
    }()
    static func document(_ source: String) -> MarkdownDocument {
        let key = source as NSString
        if let cached = storage.object(forKey: key) { return cached.document }
        let value = MarkdownDocumentBox(source)
        storage.setObject(value, forKey: key, cost: source.utf8.count * 2)
        return value.document
    }
}
