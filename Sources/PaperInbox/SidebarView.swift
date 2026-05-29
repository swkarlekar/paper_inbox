import PaperInboxCore
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        List(selection: $viewModel.selectedFilter) {
            Section("Library") {
                StatusSidebarDropRowView(title: "To Study", systemImage: "book", status: .toStudy)
                    .tag(LibraryFilter.toStudy)
                StatusSidebarDropRowView(title: "Inbox", systemImage: "tray", status: .unread)
                    .tag(LibraryFilter.inbox)
                Label("Read", systemImage: "checkmark.circle")
                    .tag(LibraryFilter.read)
                Label("Archived", systemImage: "archivebox")
                    .tag(LibraryFilter.archived)
                Label("All Papers", systemImage: "doc.text")
                    .tag(LibraryFilter.all)
            }

            Section {
                ForEach(viewModel.collections) { collection in
                    CollectionSidebarRowView(collection: collection)
                        .tag(LibraryFilter.collection(collection.id))
                        .contextMenu {
                            Button {
                                viewModel.collectionPendingRename = collection
                            } label: {
                                Label("Rename Collection", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                viewModel.deleteCollection(collection)
                            } label: {
                                Label("Delete Collection", systemImage: "trash")
                            }
                        }
                }

                Button {
                    viewModel.isShowingNewCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Collections")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case .collection = viewModel.selectedFilter {
                Toggle("Include Read/Archived", isOn: $viewModel.includeReadArchivedInCollections)
                    .font(.caption)
                    .padding([.horizontal, .bottom], 10)
            }
        }
    }
}

private struct StatusSidebarDropRowView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let title: String
    let systemImage: String
    let status: PaperStatus
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isDropTargeted ? .blue : .primary)
                .frame(width: 16)

            Text(title)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(isDropTargeted ? 0.16 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(isDropTargeted ? 0.55 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onDrop(
            of: [PaperDragPayload.type, .plainText],
            isTargeted: $isDropTargeted
        ) { providers in
            viewModel.addDroppedPapers(providers, toStatus: status)
        }
    }
}

private struct CollectionSidebarRowView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let collection: PaperCollection
    @State private var isDropTargeted = false

    private var color: Color {
        CollectionTagColor.color(for: collection, in: viewModel.collections)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)

            Text(collection.name)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(viewModel.paperCount(in: collection))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(isDropTargeted ? 0.16 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(isDropTargeted ? 0.55 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onDrop(
            of: [PaperDragPayload.type, .plainText],
            isTargeted: $isDropTargeted
        ) { providers in
            viewModel.addDroppedPapers(providers, to: collection)
        }
    }
}
