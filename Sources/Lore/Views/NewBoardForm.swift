import SwiftUI

/// Name field for creating a board, shared by the sidebar's + button and the
/// board manager so both entry points behave the same: `/` nests
/// (`Linear/Settings`), empty and duplicate names are refused inline, and
/// Return creates.
struct NewBoardForm: View {
    var onCancel: () -> Void
    var onCreated: (String) -> Void

    @Environment(LibraryStore.self) private var store
    @State private var name = ""
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(T("New board"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)

            TextField(T("Board name"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(problem == nil ? Theme.hairline : Theme.red.opacity(0.6), lineWidth: 1)
                )
                .focused($nameFocused)
                .onSubmit(create)
                .onChange(of: name) { _, _ in problem = nil }
                .onAppear { nameFocused = true }

            Text(problem ?? T("Use “/” to nest, e.g. Linear/Settings"))
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

    private func create() {
        if let problem = store.boardCreationProblem(name) {
            self.problem = problem
            return
        }
        let canonical = BoardPath.canonicalName(name)
        guard store.createBoard(name) else {
            self.problem = store.boardCreationProblem(name)
            return
        }
        onCreated(canonical)
    }
}
