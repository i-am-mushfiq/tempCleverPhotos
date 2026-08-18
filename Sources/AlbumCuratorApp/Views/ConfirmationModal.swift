import SwiftUI

public struct ConfirmationModal: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @State private var isExecuting = false
    
    var countToRemove: Int {
        viewModel.totalRemovalCandidatesCount
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 12) {
                Text("Remove \(countToRemove) photos from \"\(viewModel.selectedAlbum?.title ?? "Album")\"?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("Your photos will NOT be deleted from your iPhone.\nThey will only be removed from this specific album.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
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
            
            Spacer()
            
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
    }
}
