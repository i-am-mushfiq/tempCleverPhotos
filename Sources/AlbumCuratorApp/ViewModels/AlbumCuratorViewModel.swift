import Foundation
import SwiftUI
import Combine

@MainActor
public class AlbumCuratorViewModel: ObservableObject {
    // Navigation / State Machine
    public enum NavigationState {
        case onboarding
        case albumList
        case scanning
        case resultsSummary
        case groupReview
        case confirmationModal
        case completion
    }
    
    // Published Properties
    @Published public var navigationState: NavigationState = .onboarding
    @Published public var authorizationState: PhotosAuthorizationState = .notDetermined
    @Published public var albums: [PhotoAlbum] = []
    @Published public var selectedAlbum: PhotoAlbum?
    @Published public var selectedAlbumAssets: [PhotoAsset] = []
    @Published public var assetMap: [String: PhotoAsset] = [:]
    
    // Scanning state
    @Published public var isScanning: Bool = false
    @Published public var scanProgressCount: Int = 0
    @Published public var scanProgressTotal: Int = 0
    @Published public var scanMessage: String = ""
    
    // Analysis & Cluster results
    @Published public var similarityMode: SimilarityMode = .balanced {
        didSet {
            persistenceService.saveSimilarityMode(similarityMode)
        }
    }
    @Published public var clusters: [PhotoCluster] = []
    @Published public var currentReviewIndex: Int = 0
    @Published public var lastTransaction: MutationTransaction?
    @Published public var transactionHistory: [MutationTransaction] = []
    
    // Services
    public let photoKitService: PhotoKitServiceProtocol
    public let visionEngine: VisionAnalysisEngineProtocol
    public let persistenceService: LocalPersistenceServiceProtocol
    public let transactionManager: TransactionManager
    
    private var cachedAnalyses: [String: PhotoAnalysis] = [:]
    private var scanTask: Task<Void, Never>?
    
    public init(
        photoKitService: PhotoKitServiceProtocol = MockPhotoKitService(),
        visionEngine: VisionAnalysisEngineProtocol = VisionAnalysisEngine(),
        persistenceService: LocalPersistenceServiceProtocol = LocalPersistenceService()
    ) {
        self.photoKitService = photoKitService
        self.visionEngine = visionEngine
        self.persistenceService = persistenceService
        self.transactionManager = TransactionManager(persistenceService: persistenceService)
        
        self.similarityMode = persistenceService.loadSimilarityMode()
        self.cachedAnalyses = persistenceService.loadCachedAnalyses()
        self.transactionHistory = transactionManager.transactions
    }
    
    // Authorization
    public func checkAndRequestAuthorization() async {
        let status = await photoKitService.requestAuthorization()
        self.authorizationState = status
        if status == .authorized || status == .limited {
            await loadAlbums()
            self.navigationState = .albumList
        } else {
            self.navigationState = .onboarding
        }
    }
    
    // Album Discovery
    public func loadAlbums() async {
        let fetched = await photoKitService.fetchAlbums()
        self.albums = fetched
    }
    
    // Select & Start Scanning
    public func selectAlbumAndScan(_ album: PhotoAlbum) async {
        self.selectedAlbum = album
        self.navigationState = .scanning
        self.isScanning = true
        
        let assets = await photoKitService.fetchAssets(in: album.id)
        self.selectedAlbumAssets = assets
        self.assetMap = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        
        scanTask = Task {
            let (resultClusters, updatedAnalyses) = await visionEngine.analyzeAndCluster(
                assets: assets,
                cachedAnalyses: cachedAnalyses,
                mode: similarityMode,
                progressHandler: { [weak self] current, total, message in
                    Task { @MainActor in
                        self?.scanProgressCount = current
                        self?.scanProgressTotal = total
                        self?.scanMessage = message
                    }
                }
            )
            
            guard !Task.isCancelled else { return }
            
            self.cachedAnalyses = updatedAnalyses
            self.persistenceService.saveCachedAnalyses(updatedAnalyses)
            self.clusters = resultClusters
            self.currentReviewIndex = 0
            self.isScanning = false
            self.navigationState = .resultsSummary
        }
    }
    
    public func cancelScanning() {
        scanTask?.cancel()
        isScanning = false
        navigationState = .albumList
    }
    
    // Bulk Approval (FR-012)
    public func acceptHighConfidenceRecommendations() {
        // High confidence clusters are accepted as-is; medium and low are left for review
        navigationState = .confirmationModal
    }
    
    // Cluster Review Navigation
    public func nextGroup() {
        if currentReviewIndex < clusters.count - 1 {
            currentReviewIndex += 1
        } else {
            navigationState = .confirmationModal
        }
    }
    
    public func previousGroup() {
        if currentReviewIndex > 0 {
            currentReviewIndex -= 1
        }
    }
    
    public func toggleKeeperInCurrentCluster(assetID: String) {
        guard currentReviewIndex < clusters.count else { return }
        clusters[currentReviewIndex].toggleKeeper(assetID)
    }
    
    public func skipCurrentCluster() {
        guard currentReviewIndex < clusters.count else { return }
        clusters[currentReviewIndex].isSkipped = true
        nextGroup()
    }
    
    // Total Removal Candidates count
    public var totalRemovalCandidatesCount: Int {
        return clusters.reduce(0) { total, cluster in
            guard !cluster.isSkipped else { return total }
            return total + cluster.candidatesForRemoval.count
        }
    }
    
    // Execute Safe Mutation (FR-014)
    public func confirmAndExecuteRemoval() async {
        guard let album = selectedAlbum else { return }
        
        var assetIDsToRemove: [String] = []
        for cluster in clusters where !cluster.isSkipped {
            assetIDsToRemove.append(contentsOf: cluster.candidatesForRemoval)
        }
        
        guard !assetIDsToRemove.isEmpty else {
            navigationState = .albumList
            return
        }
        
        do {
            let success = try await photoKitService.removeAssetsFromAlbum(assetIDs: assetIDsToRemove, albumID: album.id)
            if success {
                let tx = transactionManager.recordTransaction(
                    albumID: album.id,
                    albumTitle: album.title,
                    removedAssetIDs: assetIDsToRemove
                )
                self.lastTransaction = tx
                self.transactionHistory = transactionManager.transactions
                await loadAlbums()
                self.navigationState = .completion
            }
        } catch {
            print("Failed to remove assets from album: \(error.localizedDescription)")
        }
    }
    
    // Execute Single-Tap Undo (FR-015)
    public func undoLastTransaction() async {
        guard let tx = lastTransaction else { return }
        do {
            let success = try await transactionManager.undoTransaction(tx.id, photoKitService: photoKitService)
            if success {
                self.lastTransaction = transactionManager.transactions.first(where: { $0.id == tx.id })
                self.transactionHistory = transactionManager.transactions
                await loadAlbums()
            }
        } catch {
            print("Failed to undo transaction: \(error.localizedDescription)")
        }
    }
    
    public func undoTransaction(_ tx: MutationTransaction) async {
        do {
            let success = try await transactionManager.undoTransaction(tx.id, photoKitService: photoKitService)
            if success {
                self.transactionHistory = transactionManager.transactions
                await loadAlbums()
            }
        } catch {
            print("Failed to undo transaction \(tx.id): \(error.localizedDescription)")
        }
    }
}
