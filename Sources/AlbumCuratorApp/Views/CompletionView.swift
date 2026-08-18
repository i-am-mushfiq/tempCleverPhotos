import SwiftUI

public struct CompletionView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @State private var undoStateMessage: String? = nil
    
    var removedCount: Int {
        viewModel.lastTransaction?.removedAssetIDs.count ?? 0
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 54))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Album Cleaned!")
                    .font(.largeTitle.bold())
                
                Text("\(removedCount) redundant photos removed from \"\(viewModel.selectedAlbum?.title ?? "Album")\"")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Text("Your original photos were not deleted from your device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if let msg = undoStateMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                    Text(msg)
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
            
            Spacer()
            
            VStack(spacing: 14) {
                if viewModel.lastTransaction?.isUndone == false {
                    Button(action: {
                        Task {
                            await viewModel.undoLastTransaction()
                            undoStateMessage = "Cleanup successfully undone! Photos re-added to album."
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text("Undo Cleanup")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                
                Button(action: {
                    viewModel.navigationState = .albumList
                }) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.appSystemGroupedBackground.ignoresSafeArea())
    }
}
