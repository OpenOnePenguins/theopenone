import Foundation
import OneCore

func runMarkdownTests(check: (Bool, String) -> Void) {
    let heading = MarkdownDocument("## Ready **now**").blocks[0]
    check(heading.kind == .header(level: 2) && heading.plainText == "Ready now", "Markdown headings retain block level and readable text")
    check(heading.text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "Markdown retains bold inside headings")
    let inline = MarkdownDocument("*Italic* and `x < 2` with [docs](https://example.com/docs)").blocks[0]
    check(inline.text.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true } && inline.text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }, "Markdown preserves emphasis and literal inline code")
    check(inline.text.runs.contains { $0.link?.absoluteString == "https://example.com/docs" }, "Markdown links retain their click destination")
    let lines = MarkdownDocument("First\nSecond\n\nThird").blocks
    check(lines.count == 2 && lines[0].plainText == "First\nSecond" && lines[1].plainText == "Third", "Markdown keeps chat line breaks and separates paragraphs")
    let list = MarkdownDocument("- First\n\n  3. Nested\n  4. Next\n- Last").blocks[0]
    check(list.kind == .unorderedList && list.children.count == 2, "Markdown groups bullet items without losing sibling boundaries")
    let nested = list.children[0].children.last!
    check(nested.kind == .orderedList && nested.children.map(\.kind) == [.listItem(ordinal: 3), .listItem(ordinal: 4)], "Markdown retains nested list depth and starting ordinal")
    let tasks = MarkdownDocument("- [x] **Done**\n- [ ] Pending").blocks[0].children
    check(tasks.map(\.checked) == [true, false] && tasks[0].children[0].plainText == "Done", "Markdown task lists become read-only checkboxes without raw markers")
    check(tasks[0].children[0].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "task marker removal preserves inline styles")
    let quote = MarkdownDocument("> First\n>\n> Second\n>\n> > Nested").blocks[0]
    check(quote.kind == .blockQuote && quote.children.count == 3 && quote.children.last?.kind == .blockQuote, "Markdown quotes preserve multiple paragraphs and nesting")
    let code = "let value = \"<b>**literal**</b>\"\n  print(value)\n"
    let fenced = MarkdownDocument("```swift\n" + code + "```\n").blocks[0]
    check(fenced.kind == .codeBlock(languageHint: "swift") && fenced.plainText == code, "fenced code preserves language, indentation, symbols and exact copy content")
    let streaming = MarkdownDocument("```python\nprint('still streaming')").blocks[0]
    check(streaming.kind == .codeBlock(languageHint: "python") && streaming.plainText.contains("still streaming"), "an unfinished streaming code fence still renders its content")
    let table = MarkdownDocument("| Name | Count |\n| :--- | ---: |\n| A | **2** |\n| B | |\n").blocks[0]
    if case .table(let columns) = table.kind {
        check(columns.map(\.alignment) == [.left, .right] && table.children.count == 3, "Markdown tables retain alignment, header and data rows")
    } else { check(false, "Markdown tables retain alignment, header and data rows") }
    check(table.children[1].children[1].plainText == "2" && table.children[2].children.first?.plainText == "B", "Markdown table cells retain formatting and empty cells do not shift data")
    check(MarkdownDocument("---").blocks.first?.kind == .thematicBreak, "Markdown horizontal rules are structural dividers")
    check(MarkdownDocument("[unsafe](javascript:alert%281%29)").blocks[0].text.runs.allSatisfy { $0.link == nil }, "Markdown cannot turn script URLs into actionable links")
    let image = MarkdownDocument("![Diagram](https://example.com/diagram.png)").blocks[0]
    check(image.plainText == "Diagram" && image.text.runs.allSatisfy { $0.imageURL == nil } && image.text.link?.absoluteString == "https://example.com/diagram.png", "image Markdown shows linked alt text without automatic remote image requests")
    check(MarkdownDocument("<script>alert('literal')</script>").blocks[0].plainText.contains("<script>"), "raw HTML remains literal message text")
    check(MarkdownDocument("").blocks.isEmpty && MarkdownDocument("Unfinished **bold").blocks[0].plainText == "Unfinished **bold", "empty and unfinished inline Markdown remain readable")
}
