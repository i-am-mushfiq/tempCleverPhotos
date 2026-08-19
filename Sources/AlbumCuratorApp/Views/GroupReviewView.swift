import SwiftUI

public struct GroupReviewView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel

    private struct PreviewTarget: Identifiable {
        let id: String
    }
    @State private var previewTarget: PreviewTarget?

    var currentCluster: PhotoCluster? {
        guard viewModel.currentReviewIndex < viewModel.clusters.count else { return nil }
        return viewModel.clusters[viewModel.currentReviewIndex]
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button(action: { viewModel.navigationState = .resultsSummary }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if let cluster = currentCluster {
                    VStack {
                        Text("Group \(viewModel.currentReviewIndex + 1) of \(viewModel.clusters.count)")
                            .font(.headline)
                        ConfidenceBadge(confidence: cluster.confidence)
                    }
                }
                
                Spacer()
                
                Button(action: { viewModel.skipCurrentCluster() }) {
                    Text("Skip")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color.appSecondarySystemGroupedBackground)
            
            Divider()
            
            // Photo Comparison Area
            if let cluster = currentCluster {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Tap photos to toggle between Keeping in Album vs. Removal from Album. Touch and hold to preview full screen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 12)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)], spacing: 16) {
                            ForEach(cluster.assetIDs, id: \.self) { assetID in
                                if let asset = viewModel.assetMap[assetID] {
                                    let isKeeper = cluster.isKeeper(assetID)
                                    let isRemoval = cluster.isCandidateForRemoval(assetID)

                                    PhotoThumbnailView(
                                        asset: asset,
                                        isKeeper: isKeeper,
                                        isSelectedForRemoval: isRemoval,
                                        onTap: {
                                            viewModel.toggleKeeperInCurrentCluster(assetID: assetID)
                                        },
                                        onLongPress: {
                                            previewTarget = PreviewTarget(id: assetID)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        if cluster.isUserOverridden {
                            HStack {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .foregroundColor(.blue)
                                Text("Manual override applied")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 24)
                }
            } else {
                Spacer()
                Text("No groups available.")
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Divider()
            
            // Bottom Action Controls
            HStack(spacing: 16) {
                Button(action: { viewModel.previousGroup() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                        .background(Color.appTertiarySystemFill)
                        .clipShape(Circle())
                }
                .disabled(viewModel.currentReviewIndex == 0)
                
                Button(action: {
                    viewModel.nextGroup()
                }) {
                    HStack {
                        Text(viewModel.currentReviewIndex == viewModel.clusters.count - 1 ? "Review Complete" : "Keep & Next Group")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding()
            .background(Color.appSecondarySystemGroupedBackground)
        }
        .background(Color.appSystemGroupedBackground.ignoresSafeArea())
        .fullScreenCover(item: $previewTarget) { target in
            PhotoZoomPreviewView(
                assetIDs: currentCluster?.assetIDs ?? [target.id],
                assetMap: viewModel.assetMap,
                initialAssetID: target.id
            )
        }
    }
}
