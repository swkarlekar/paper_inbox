import SwiftUI

struct LibraryWindow: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } content: {
            PaperListView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
        } detail: {
            if let paper = viewModel.selectedPaper {
                PaperDetailView(paper: paper)
            } else {
                PlaceholderView(
                    title: "No Paper Selected",
                    systemImage: "doc.text.magnifyingglass",
                    message: "Add a PDF or URL to start building the library."
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.isShowingAddPaper = true
                } label: {
                    Label("Add Paper", systemImage: "plus")
                }

                Button {
                    viewModel.isShowingNewCollection = true
                } label: {
                    Label("New Collection", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingAddPaper) {
            AddPaperView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingNewCollection) {
            NewCollectionView()
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.collectionPendingRename) { collection in
            RenameCollectionView(collection: collection)
                .environmentObject(viewModel)
        }
        .alert(item: $viewModel.alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            viewModel.reloadAndReportErrors()
        }
    }
}
