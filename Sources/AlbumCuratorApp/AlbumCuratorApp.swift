import SwiftUI

@main
struct AlbumCuratorApp: App {
    @StateObject private var viewModel = AlbumCuratorViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainContentView(viewModel: viewModel)
                .task {
                    await viewModel.checkAndRequestAuthorization()
                }
        }
    }
}

struct MainContentView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    
    var body: some View {
        Group {
            switch viewModel.navigationState {
            case .onboarding:
                OnboardingView(viewModel: viewModel)
            case .albumList:
                AlbumListView(viewModel: viewModel)
            case .scanning:
                ScanningView(viewModel: viewModel)
            case .resultsSummary:
                ResultsSummaryView(viewModel: viewModel)
            case .groupReview:
                GroupReviewView(viewModel: viewModel)
            case .confirmationModal:
                ConfirmationModal(viewModel: viewModel)
            case .completion:
                CompletionView(viewModel: viewModel)
            }
        }
        .animation(.default, value: viewModel.navigationState)
    }
}
