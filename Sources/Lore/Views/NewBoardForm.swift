import SwiftUI

/// Name field for creating a board, shared by the sidebar's + button, a folder
/// row's quick-add, and the board manager so every entry point behaves the
/// same: `/` nests (`Linear/Settings`), empty and duplicate names are refused
/// inline, and Return creates.
///
/// `parent` turns the field into a leaf-name field: the folder path is shown
/// as a fixed prefix and joined back on create, which is what "new board in
/// this folder" should feel like.
struct NewBoardForm: View {
    var parent: String? = nil
    var onCancel: () -> Void
    var onCreated: (String) -> Void

    @Environment(LibraryStore.self) private var store
    @State private var name = ""
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    private var parentLabel: String? {
        parent.map(localizedBoard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(parentLabel.map { TF("New board in “%@”", $0) } ?? T("New board"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                if let parentLabel {
                    Text(verbatim: "\(parentLabel)/")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 120, alignment: .leading)
                }

                TextField(T("Board name"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .focused($nameFocused)
                    .onSubmit(create)
                    .onChange(of: name) { _, _ in problem = nil }
                    .layoutPriority(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.paper))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(problem == nil ? Theme.hairline : Theme.red.opacity(0.6), lineWidth: 1)
            )
            .onAppear { nameFocused = true }

            Text(problem ?? helperText)
                .font(.system(size: 10.5))
                .foregroundStyle(problem == nil ? Theme.inkTertiary : Theme.red)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                LoreButton(title: T("Cancel"), variant: .secondary) { onCancel() }
                LoreButton(title: T("Create"), variant: .primary) { create() }
            }
            .padding(.top, 2)
        }
        .padding(13)
    }

    private var helperText: String {
        if let parentLabel {
            return TF("Inside “%@”. Use “/” for another level.", parentLabel)
        }
        return T("Use “/” to nest, e.g. Linear/Settings")
    }

    private func create() {
        let leaf = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leaf.isEmpty else {
            problem = T("Board name can't be empty.")
            return
        }
        let fullName: String
        if let parent {
            fullName = BoardPath.canonicalName(parent + String(BoardPath.separator) + leaf)
        } else {
            fullName = BoardPath.canonicalName(leaf)
        }
        if let problem = store.boardCreationProblem(fullName) {
            self.problem = problem
            return
        }
        guard store.createBoard(fullName) else {
            self.problem = store.boardCreationProblem(fullName)
            return
        }
        onCreated(fullName)
    }
}
