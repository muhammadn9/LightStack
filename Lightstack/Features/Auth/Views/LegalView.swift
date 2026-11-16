import SwiftUI

/// The two legal documents. The text lives in `docs/legal/*.md` (bundled as resources) so the
/// in-app screens and the published copies cannot drift apart.
enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Use"
        }
    }

    private var resourceName: String {
        switch self {
        case .privacy: return "PRIVACY_POLICY"
        case .terms: return "TERMS_OF_USE"
        }
    }

    /// Markdown body with the draft note above the `---` line removed.
    var markdown: String {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "# \(navigationTitle)\n\nThis document could not be loaded."
        }
        if let range = text.range(of: "\n---\n") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

/// Scrollable legal text rendered from the simple markdown subset the documents use.
struct LegalView: View {
    let document: LegalDocument

    private enum Block: Identifiable {
        case title(String), heading(String), paragraph(String), bullet(String)
        var id: String {
            switch self {
            case .title(let t): return "t" + t
            case .heading(let t): return "h" + t
            case .paragraph(let t): return "p" + t
            case .bullet(let t): return "b" + t
            }
        }
    }

    private var blocks: [Block] {
        document.markdown.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
            if line.hasPrefix("# ") { return .title(String(line.dropFirst(2))) }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(document.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal.\(document.rawValue)")
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(.title.bold()).foregroundStyle(AppTheme.textPrimary)
        case .heading(let text):
            Text(text).font(.headline).foregroundStyle(AppTheme.textPrimary).padding(.top, 8)
        case .paragraph(let text):
            Text(inline(text)).font(.body).foregroundStyle(AppTheme.textPrimary)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(AppTheme.textSecondary)
                Text(inline(text)).font(.body).foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Wraps `LegalView` in its own navigation stack with a Done button, for presenting as a sheet.
struct LegalSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalView(document: document)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("legal.done")
                    }
                }
        }
    }
}
