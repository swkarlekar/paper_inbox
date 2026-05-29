import PaperInboxCore
import SwiftUI

struct AddPaperView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var urlString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Paper")
                .font(.title2.weight(.semibold))

            Button {
                viewModel.choosePDF()
                dismiss()
            } label: {
                Label("Choose PDF...", systemImage: "doc.badge.plus")
            }

            Divider()

            TextField("https://arxiv.org/abs/...", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addURL)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add URL") {
                    addURL()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func addURL() {
        viewModel.addURL(urlString)
        dismiss()
    }
}

struct NewCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collection")
                .font(.title2.weight(.semibold))

            TextField("Collection name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func create() {
        viewModel.createCollection(name: name)
        dismiss()
    }
}

struct RenameCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: LibraryViewModel
    let collection: PaperCollection
    @State private var name: String

    init(collection: PaperCollection) {
        self.collection = collection
        _name = State(initialValue: collection.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Collection")
                .font(.title2.weight(.semibold))

            TextField("Collection name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(rename)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Rename") {
                    rename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func rename() {
        viewModel.renameCollection(collection, name: name)
        dismiss()
    }
}
