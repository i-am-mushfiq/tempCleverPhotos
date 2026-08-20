import SwiftUI

public struct TransactionHistoryView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @Environment(\.dismiss) private var dismiss

    private struct PreviewTarget: Identifiable {
        let id: String
        let assetIDs: [String]
    }
    @State private var previewTarget: PreviewTarget?

    public var body: some View {
        NavigationStack {
            List {
                if viewModel.transactionHistory.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Past album cleanups will appear here with single-tap undo capability.")
                    )
                } else {
                    ForEach(viewModel.transactionHistory) { tx in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tx.albumTitle)
                                        .font(.headline)
                                    Text("\(tx.removedAssetIDs.count) photos removed • \(tx.timestamp.formatted(.dateTime.month().day().hour().minute()))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if tx.isUndone {
                                    Text("Undone")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .clipShape(Capsule())
                                } else {
                                    Button(action: {
                                        Task {
                                            await viewModel.undoTransaction(tx)
                                        }
                                    }) {
                                        Text("Undo")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            // Show the actual removed photos, not just a count — recognizing
                            // the pictures matters far more than a number when deciding
                            // whether to undo a cleanup from days ago.
                            TransactionThumbnailStrip(assetIDs: tx.removedAssetIDs) { tappedID in
                                previewTarget = PreviewTarget(id: tappedID, assetIDs: tx.removedAssetIDs)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Cleanup History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(item: $previewTarget) { target in
                PhotoZoomPreviewView(
                    assetIDs: target.assetIDs,
                    assetMap: viewModel.assetMap,
                    initialAssetID: target.id
                )
            }
        }
    }
}

/// Horizontal strip of small thumbnails for a transaction's removed assets, capped at
/// a fixed count with a "+N" tile for the rest so a large bulk-accept doesn't blow out
/// the row height. Tapping any thumbnail opens the full-screen zoom preview.
private struct TransactionThumbnailStrip: View {
    let assetIDs: [String]
    let onTapThumbnail: (String) -> Void
    private let maxDisplayed = 6

    var body: some View {
        HStack(spacing: 6) {
            ForEach(assetIDs.prefix(maxDisplayed), id: \.self) { assetID in
                Button(action: { onTapThumbnail(assetID) }) {
                    PHAssetImageView(
                        localIdentifier: assetID,
                        targetSize: CGSize(width: 120, height: 120),
                        contentMode: .fill
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if assetIDs.count > maxDisplayed {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appTertiarySystemFill)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("+\(assetIDs.count - maxDisplayed)")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                    )
            }

            Spacer(minLength: 0)
        }
    }
}
