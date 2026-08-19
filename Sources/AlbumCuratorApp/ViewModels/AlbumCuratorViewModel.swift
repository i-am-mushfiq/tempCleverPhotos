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
            // Re-cluster the already-analyzed photos under the new mode. This is cheap —
            // Phase 2/3 of analyzeAndCluster run entirely off cached feature prints, no
            // Vision re-analysis needed — so switching modes on the results screen updates
            // the groups immediately instead of silently doing nothing until the next scan.
            let requestedMode = similarityMode
            Task { await self.recluster(with: requestedMode) }
        }
    }
    @Published public var clusters: [PhotoCluster] = []
    @Published public var currentReviewIndex: Int = 0
    @Published public var lastTransaction: MutationTransaction?
    @Published public var transactionHistory: [MutationTransaction] = []

    /// Non-nil when a recoverable error occurs (removal fail, undo fail).
    /// Bind to an .alert() in your view.
    @Published public var errorMessage: String? = nil

    // Services
    public let photoKitService: PhotoKitServiceProtocol
    public let visionEngine: VisionAnalysisEngineProtocol
    public let persistenceService: LocalPersistenceServiceProtocol
    public let transactionManager: TransactionManager

    private var cachedAnalyses: [String: PhotoAnalysis] = [:]
    private var scanTask: Task<Void, Never>?

    public init(
        photoKitService: PhotoKitServiceProtocol = PhotoKitService(),
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

    // MARK: - Authorization

    public func checkAuthorizationOnLaunch() async {
        let status = photoKitService.checkAuthorizationStatus()
        self.authorizationState = status
        if status == .authorized || status == .limited {
            await loadAlbums()
            self.navigationState = .albumList
        } else {
            self.navigationState = .onboarding
        }
    }

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

    // MARK: - Album Discovery

    public func loadAlbums() async {
        let fetched = await photoKitService.fetchAlbums()
        let lastAnalyzedDates = persistenceService.loadLastAnalyzedDates()
        self.albums = fetched.map { album in
            var album = album
            album.lastAnalyzedDate = lastAnalyzedDates[album.id]
            return album
        }
    }

    // MARK: - Select & Start Scanning

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

            let analyzedDate = Date()
            self.persistenceService.saveLastAnalyzedDate(analyzedDate, forAlbumID: album.id)
            if var updatedSelectedAlbum = self.selectedAlbum, updatedSelectedAlbum.id == album.id {
                updatedSelectedAlbum.lastAnalyzedDate = analyzedDate
                self.selectedAlbum = updatedSelectedAlbum
            }
            if let index = self.albums.firstIndex(where: { $0.id == album.id }) {
                self.albums[index].lastAnalyzedDate = analyzedDate
            }

            self.navigationState = .resultsSummary
        }
    }

    public func cancelScanning() {
        scanTask?.cancel()
        isScanning = false
        navigationState = .albumList
    }

    /// Re-groups the current album's already-analyzed photos under `mode` without
    /// re-running Vision analysis. Passing `cachedAnalyses` back in means every asset
    /// is already at `currentVersion`, so analyzeAndCluster's Phase 1 finds nothing to
    /// (re-)analyze and goes straight to the cheap clustering phases.
    private func recluster(with mode: SimilarityMode) async {
        guard !selectedAlbumAssets.isEmpty else { return }

        let (resultClusters, _) = await visionEngine.analyzeAndCluster(
            assets: selectedAlbumAssets,
            cachedAnalyses: cachedAnalyses,
            mode: mode,
            progressHandler: { _, _, _ in }
        )

        // Discard a stale result if the user changed modes again before this finished.
        guard mode == similarityMode else { return }

        self.clusters = resultClusters
        self.currentReviewIndex = 0
    }

    /// The measured quality signals for a given asset, if it's been analyzed. Lets
    /// views explain *why* a recommendation was made instead of just showing a badge.
    public func analysis(for assetID: String) -> PhotoAnalysis? {
        cachedAnalyses[assetID]
    }

    // MARK: - Bulk Approval (FR-012)

    /// Marks all non-high-confidence clusters as skipped so only .high clusters
    /// are included in the removal batch when the user confirms.
    public func acceptHighConfidenceRecommendations() {
        for i in clusters.indices where clusters[i].confidence != .high {
            clusters[i].isSkipped = true
        }
        navigationState = .confirmationModal
    }

    // MARK: - Cluster Review Navigation

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

    // MARK: - Removal Candidate Count

    public var totalRemovalCandidatesCount: Int {
        return clusters.reduce(0) { total, cluster in
            guard !cluster.isSkipped else { return total }
            return total + cluster.candidatesForRemoval.count
        }
    }

    // MARK: - Execute Safe Mutation (FR-014)

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
            let success = try await photoKitService.removeAssetsFromAlbum(
                assetIDs: assetIDsToRemove,
                albumID: album.id
            )
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
            } else {
                self.errorMessage = "Could not remove photos from \"\(album.title)\". The album may be read-only or the operation was denied by the system."
            }
        } catch {
            self.errorMessage = "Removal failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Undo (FR-015)

    public func undoLastTransaction() async {
        guard let tx = lastTransaction else { return }
        do {
            let success = try await transactionManager.undoTransaction(tx.id, photoKitService: photoKitService)
            if success {
                self.lastTransaction = transactionManager.transactions.first(where: { $0.id == tx.id })
                self.transactionHistory = transactionManager.transactions
                await loadAlbums()
            } else {
                self.errorMessage = "Undo did not complete — the album or photos may have been moved."
            }
        } catch {
            self.errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }

    public func undoTransaction(_ tx: MutationTransaction) async {
        do {
            let success = try await transactionManager.undoTransaction(tx.id, photoKitService: photoKitService)
            if success {
                self.transactionHistory = transactionManager.transactions
                await loadAlbums()
            } else {
                self.errorMessage = "Undo did not complete for transaction \(tx.albumTitle)."
            }
        } catch {
            self.errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }
}
