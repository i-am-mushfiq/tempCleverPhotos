import SwiftUI

public struct AlbumListView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingHistory = false
    
    var filteredAlbums: [PhotoAlbum] {
        if searchText.isEmpty {
            return viewModel.albums
        } else {
            return viewModel.albums.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredAlbums) { album in
                        Button(action: {
                            Task {
                                await viewModel.selectAlbumAndScan(album)
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    if let thumbnailID = album.thumbnailAssetID {
                                        PHAssetImageView(localIdentifier: thumbnailID, targetSize: CGSize(width: 120, height: 120), contentMode: .fill)
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    } else {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(LinearGradient(
                                                colors: [.blue.opacity(0.6), .indigo.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 54, height: 54)
                                        
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(album.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 8) {
                                        Text("\(album.assetCount) photos")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        if let lastAnalyzed = album.lastAnalyzedDate {
                                            Text("•")
                                                .foregroundColor(.secondary)
                                            Text("Analyzed \(lastAnalyzed.formatted(.dateTime.month().day()))")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundColor(Color.appTertiaryLabel)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Select an Album to Curate")
                } footer: {
                    Text("Selecting an album will only analyze photos in that specific album. Your original Photos Library remains 100% untouched.")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.automatic)
            #endif
            .navigationTitle("Albums")
            .searchable(text: $searchText, prompt: "Search albums...")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingHistory) {
                TransactionHistoryView(viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadAlbums()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
