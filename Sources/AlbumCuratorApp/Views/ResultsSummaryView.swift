import SwiftUI

public struct ResultsSummaryView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    
    var highConfidenceCount: Int {
        viewModel.clusters.filter { $0.confidence == .high }.count
    }
    
    var mediumConfidenceCount: Int {
        viewModel.clusters.filter { $0.confidence == .medium }.count
    }
    
    var lowConfidenceCount: Int {
        viewModel.clusters.filter { $0.confidence == .low }.count
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header Info
            VStack(spacing: 6) {
                Text(viewModel.selectedAlbum?.title ?? "Album Results")
                    .font(.title.bold())
                
                Text("\(viewModel.selectedAlbumAssets.count) photos analyzed • \(viewModel.clusters.count) similar groups found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)
            
            // Confidence Breakdown Card
            CardContainer {
                VStack(spacing: 16) {
                    Text("Recommendation Summary")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        ConfidenceStatItem(
                            count: highConfidenceCount,
                            label: "High Conf.",
                            color: .green,
                            icon: "checkmark.shield.fill"
                        )
                        
                        Divider()
                        
                        ConfidenceStatItem(
                            count: mediumConfidenceCount,
                            label: "Medium Conf.",
                            color: .orange,
                            icon: "exclamationmark.shield.fill"
                        )
                        
                        Divider()
                        
                        ConfidenceStatItem(
                            count: lowConfidenceCount,
                            label: "Manual Review",
                            color: .gray,
                            icon: "questionmark.circle.fill"
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            // Mode Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Grouping Strategy")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Picker("Similarity Mode", selection: $viewModel.similarityMode) {
                    ForEach(SimilarityMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                if highConfidenceCount > 0 {
                    Button(action: {
                        viewModel.acceptHighConfidenceRecommendations()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Accept All \(highConfidenceCount) High-Confidence Groups")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                
                Button(action: {
                    viewModel.navigationState = .groupReview
                }) {
                    HStack {
                        Text("Start Step-by-Step Review (\(viewModel.clusters.count) Groups)")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                
                Button(action: {
                    viewModel.navigationState = .albumList
                }) {
                    Text("Back to Albums")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.appSystemGroupedBackground.ignoresSafeArea())
    }
}
