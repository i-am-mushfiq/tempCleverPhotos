import XCTest
@testable import AlbumCuratorApp

final class PersistenceTests: XCTestCase {
    
    var tempDirectory: URL!
    var persistenceService: LocalPersistenceService!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        persistenceService = LocalPersistenceService(storageDirectory: tempDirectory)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    func testAnalysesCache_SaveAndLoad() {
        let analysis = PhotoAnalysis(
            assetID: "asset_test_99",
            perceptualHash: 0x123456789ABCDEF0,
            sharpnessScore: 0.85,
            exposureBalance: 0.90,
            noiseScore: 0.95
        )
        
        let dict = ["asset_test_99": analysis]
        persistenceService.saveCachedAnalyses(dict)
        
        let loaded = persistenceService.loadCachedAnalyses()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded["asset_test_99"]?.assetID, "asset_test_99")
        XCTAssertEqual(loaded["asset_test_99"]?.sharpnessScore, 0.85)
    }
    
    func testSimilarityMode_SaveAndLoad() {
        persistenceService.saveSimilarityMode(.aggressive)
        let loadedMode = persistenceService.loadSimilarityMode()
        XCTAssertEqual(loadedMode, .aggressive)
    }
}
