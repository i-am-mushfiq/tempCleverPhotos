import XCTest
@testable import AlbumCuratorApp

final class VisionEngineTests: XCTestCase {
    
    var visionEngine: VisionAnalysisEngine!
    
    override func setUp() {
        super.setUp()
        visionEngine = VisionAnalysisEngine()
    }
    
    func testSingleAssetAnalysis_ProducesValidQualityScores() {
        let asset = PhotoAsset(
            id: "test_asset_001",
            localIdentifier: "ph_001",
            creationDate: Date(),
            pixelWidth: 4032,
            pixelHeight: 3024,
            isLivePhoto: false
        )
        
        let analysis = visionEngine.analyzeSingleAsset(asset)
        
        XCTAssertEqual(analysis.assetID, asset.id)
        XCTAssertGreaterThanOrEqual(analysis.sharpnessScore, 0.0)
        XCTAssertLessThanOrEqual(analysis.sharpnessScore, 1.0)
        XCTAssertGreaterThanOrEqual(analysis.overallQualityScore, 0.0)
        XCTAssertLessThanOrEqual(analysis.overallQualityScore, 1.0)
    }
    
    func testClustering_GroupsSimilarPhotosInConservativeMode() async {
        let now = Date()
        let assets = [
            PhotoAsset(id: "img_burst_1", localIdentifier: "ph1", creationDate: now),
            PhotoAsset(id: "img_burst_2", localIdentifier: "ph2", creationDate: now.addingTimeInterval(2)), // 2 sec apart
            PhotoAsset(id: "img_distinct_3", localIdentifier: "ph3", creationDate: now.addingTimeInterval(500)) // 500 sec apart
        ]
        
        let (clusters, _) = await visionEngine.analyzeAndCluster(
            assets: assets,
            cachedAnalyses: [:],
            mode: .conservative,
            progressHandler: { _, _, _ in }
        )
        
        XCTAssertFalse(clusters.isEmpty, "Should form at least one cluster for nearby photos")
        if let firstCluster = clusters.first {
            XCTAssertTrue(firstCluster.assetIDs.contains("img_burst_1"))
            XCTAssertTrue(firstCluster.assetIDs.contains("img_burst_2"))
            XCTAssertFalse(firstCluster.assetIDs.contains("img_distinct_3"), "Photo 500 sec apart should be excluded in conservative mode")
        }
    }
    
    func testConfidenceScoring_AssignsValidConfidence() async {
        let mockService = MockPhotoKitService()
        let assets = await mockService.fetchAssets(in: "album_vacation_101")
        
        let (clusters, _) = await visionEngine.analyzeAndCluster(
            assets: assets,
            cachedAnalyses: [:],
            mode: .balanced,
            progressHandler: { _, _, _ in }
        )
        
        XCTAssertGreaterThan(clusters.count, 0, "Should generate clusters for mock vacation album")
        for cluster in clusters {
            XCTAssertTrue(ClusterConfidence.allCases.contains(cluster.confidence))
            XCTAssertFalse(cluster.recommendedKeepers.isEmpty, "Every cluster must recommend at least one keeper")
        }
    }
}
