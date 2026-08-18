import SwiftUI

public struct ScanningView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    
    public var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 140, height: 140)
                
                ProgressView()
                    .scaleEffect(1.8)
                    .tint(.blue)
            }
            
            VStack(spacing: 12) {
                Text("Analyzing \(viewModel.selectedAlbum?.title ?? "Album")")
                    .font(.title2.bold())
                
                if viewModel.scanProgressTotal > 0 {
                    Text("\(viewModel.scanProgressCount) / \(viewModel.scanProgressTotal)")
                        .font(.title.monospacedDigit().bold())
                        .foregroundColor(.blue)
                }
                
                Text(viewModel.scanMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Progress Bar
            if viewModel.scanProgressTotal > 0 {
                ProgressView(value: Double(viewModel.scanProgressCount), total: Double(viewModel.scanProgressTotal))
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            CardContainer {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                    Text("Incremental analysis cached locally. Processing runs 100% on-device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Button(action: {
                viewModel.cancelScanning()
            }) {
                Text("Cancel Analysis")
                    .font(.headline)
                    .foregroundColor(.red)
                    .padding()
            }
            .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
