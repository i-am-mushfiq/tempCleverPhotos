import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Hero Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.2), .indigo.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Album Curator")
                    .font(.largeTitle.bold())
                
                Text("Clean up your albums in minutes,\nwithout deleting your photos.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Privacy Commitments Card
            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("100% On-Device Processing")
                                .font(.headline)
                            Text("Photos never leave your iPhone. No cloud uploads or external servers.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.minus")
                            .font(.title2)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Non-Destructive Cleanup")
                                .font(.headline)
                            Text("Removes redundant photos from the selected album only. Photos remain safe in your Photos Library.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Primary Action
            Button(action: {
                Task {
                    await viewModel.checkAndRequestAuthorization()
                }
            }) {
                HStack {
                    Text("Grant Photos Access")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
