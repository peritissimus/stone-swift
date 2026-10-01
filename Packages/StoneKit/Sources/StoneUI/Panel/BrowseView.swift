import SwiftUI
import StoneDomain

/// ⌥O: previous notes on the left, a read-only preview of the selection on the right.
struct BrowseView: View {
    @Bindable var store: BrowseStore
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchField
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
                list
            }
            .frame(width: Theme.Size.browseListWidth)
            Rectangle().fill(Theme.Colors.divider).frame(width: 1)
            preview
        }
        .onAppear { fieldFocused = true }
        .onChange(of: store.focusToken) { fieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes", text: $store.query)
                .textFieldStyle(.plain)
                .font(Theme.Font.search)
                .focused($fieldFocused)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.searchFieldHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.rows) { row in
                        rowView(row)
                            .id(row.id)
                            .onTapGesture { store.select(row.note.path) }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            .scrollIndicators(.never)
            .onChange(of: store.selectedPath) { _, path in
                if let path { proxy.scrollTo(path) }
            }
        }
    }

    private func rowView(_ row: BrowseRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: row.note.isJournal ? "calendar" : "doc.text")
                    .foregroundStyle(.secondary)
                Text(row.note.title).font(Theme.Font.rowTitle).lineLimit(1)
            }
            Text(row.snippet ?? subtitle(for: row.note))
                .font(Theme.Font.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            row.note.path == store.selectedPath ? Theme.Colors.selection : .clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        .contentShape(Rectangle())
    }

    private func subtitle(for note: NoteSummary) -> String {
        let when = note.modifiedAt.formatted(.relative(presentation: .named))
        return note.path.folder.isRoot ? when : "\(note.path.folder.value) · \(when)"
    }

    @ViewBuilder
    private var preview: some View {
        if let note = store.preview {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(note.title).font(Theme.Font.previewTitle)
                    Text(note.path.value).font(Theme.Font.rowSubtitle).foregroundStyle(.tertiary)
                    Text(Self.render(note.body))
                        .font(Theme.Font.preview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.xl)
            }
        } else {
            Text(store.rows.isEmpty ? "No notes found" : "Select a note")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Inline Markdown only — bold, italics, code, links — with the source's line breaks kept.
    private static func render(_ body: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    }
}
