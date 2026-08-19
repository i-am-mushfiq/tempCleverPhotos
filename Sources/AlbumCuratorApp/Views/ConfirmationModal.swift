import SwiftUI

public struct ConfirmationModal: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @State private var isExecuting = false

    private struct PreviewTarget: Identifiable {
        let id: String
    }
    @State private var previewTarget: PreviewTarget?

    var countToRemove: Int {
        viewModel.totalRemovalCandidatesCount
    }

    /// Every asset currently slated for removal across non-skipped clusters — this is
    /// what "Accept All High-Confidence Groups" commits to without the user having
    /// stepped through them individually, so showing the actual photos here (not just
    /// a count) is the last chance to catch a bad call before it executes.
    var removalAssetIDs: [String] {
        viewModel.clusters.filter { !$0.isSkipped }.flatMap { $0.candidatesForRemoval }
    }

    public var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                }

                Text("Remove \(countToRemove) photos from \"\(viewModel.selectedAlbum?.title ?? "Album")\"?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Your photos will NOT be deleted from your iPhone.\nThey will only be removed from this specific album.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.top, 16)

            if !removalAssetIDs.isEmpty {
                ScrollView {
                    Text("Tap a photo to preview it full screen.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 8)], spacing: 8) {
                        ForEach(removalAssetIDs, id: \.self) { assetID in
                            if let asset = viewModel.assetMap[assetID] {
                                Button(action: { previewTarget = PreviewTarget(id: assetID) }) {
                                    PHAssetImageView(
                                        localIdentifier: asset.localIdentifier,
                                        targetSize: CGSize(width: 200, height: 200),
                                        contentMode: .fill
                                    )
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(asset.customLabel ?? "Photo marked for removal")
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 220)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "shield.checkmark.fill")
                            .foregroundColor(.green)
                        Text("Safety Guarantee")
                            .font(.headline)
                    }
                    Text("The underlying Photo Library files are 100% preserved. An instant Undo feature is available immediately after this operation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button(action: {
                    isExecuting = true
                    Task {
                        await viewModel.confirmAndExecuteRemoval()
                        isExecuting = false
                    }
                }) {
                    HStack {
                        if isExecuting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "folder.badge.minus")
                            Text("Remove from Album")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isExecuting)
                
                Button(action: {
                    viewModel.navigationState = .resultsSummary
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.appSystemGroupedBackground.ignoresSafeArea())
        .alert("Removal Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .fullScreenCover(item: $previewTarget) { target in
            PhotoZoomPreviewView(
                assetIDs: removalAssetIDs,
                assetMap: viewModel.assetMap,
                initialAssetID: target.id
            )
        }
    }
}
