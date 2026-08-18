import SwiftUI

public struct TransactionHistoryView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @Environment(\.dismiss) private var dismiss
    
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
        }
    }
}
