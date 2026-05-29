import AppKit
import PaperInboxCore
import SwiftUI

struct PaperListView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search papers and imported notes", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.bar)

            if viewModel.displayedPapers.isEmpty {
                PlaceholderView(
                    title: "No Papers",
                    systemImage: "doc.text",
                    message: "Add a PDF, URL, or adjust the current filter."
                )
            } else {
                List(viewModel.displayedPapers, selection: $viewModel.selectedPaperIDs) { paper in
                    PaperRowView(paper: paper)
                        .tag(paper.id)
                }
                .listStyle(.plain)
                .id(viewModel.paperListResetID)
            }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: nil) { providers in
            viewModel.handleDrop(providers)
        }
    }
}

private struct PaperRowView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let paper: Paper
    @State private var isConfirmingDelete = false

    private var isSelected: Bool {
        viewModel.selectedPaperIDs.contains(paper.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                StatusBadge(status: paper.status)
                if let year = paper.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let venue = paper.venue, !venue.isEmpty {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            let collections = viewModel.collections(for: paper)
            if !collections.isEmpty {
                CollectionTagStripView(collections: collections, allCollections: viewModel.collections)
            }

            HStack(spacing: 10) {
                ArtifactIndicator(label: "Summary", isPresent: viewModel.hasArtifact(.summary, for: paper))
                ArtifactIndicator(label: "Study", isPresent: viewModel.hasArtifact(.studyGuide, for: paper))
                ArtifactIndicator(label: "Chat", isPresent: viewModel.hasArtifact(.chatTranscript, for: paper))
                Spacer()
            }
            .font(.caption)

            HStack {
                Button {
                    viewModel.launchPrompt(for: paper, mode: .summary)
                } label: {
                    Label("Summary", systemImage: "paperplane")
                }

                Button {
                    viewModel.launchPrompt(for: paper, mode: .studyGuide)
                } label: {
                    Label("Study Guide", systemImage: "book.closed")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? PaperSelectionStyle.background : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? PaperSelectionStyle.border : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
        .listRowBackground(isSelected ? PaperSelectionStyle.rowBackground : Color.clear)
        .foregroundStyle(Color.primary)
        .tint(Color.primary)
        .onTapGesture {
            viewModel.selectPaper(paper, modifierFlags: NSEvent.modifierFlags)
        }
        .onDrag {
            viewModel.dragProvider(for: paper)
        }
        .contextMenu {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Paper", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this paper?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Paper", role: .destructive) {
                viewModel.deletePaper(paper)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the paper from PaperInbox and deletes its local folder and imported artifacts.")
        }
    }
}

private enum PaperSelectionStyle {
    static let rowBackground = Color(red: 0.965, green: 0.975, blue: 0.975)
    static let background = Color(red: 0.925, green: 0.955, blue: 0.955)
    static let border = Color(red: 0.42, green: 0.61, blue: 0.64).opacity(0.35)
}

struct StatusBadge: View {
    let status: PaperStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var background: Color {
        switch status {
        case .unread:
            return Color.gray.opacity(0.18)
        case .toStudy:
            return Color.blue.opacity(0.18)
        case .read:
            return Color.teal.opacity(0.18)
        case .archived:
            return Color.secondary.opacity(0.16)
        }
    }
}

private struct ArtifactIndicator: View {
    let label: String
    let isPresent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPresent ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isPresent ? .green : .secondary)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
