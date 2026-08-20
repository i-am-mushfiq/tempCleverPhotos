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
        let sampleFeaturePrintData = Data([0x01, 0x02, 0x03, 0x04])
        let analysis = PhotoAnalysis(
            assetID: "asset_test_99",
            featurePrintData: sampleFeaturePrintData,
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
        XCTAssertEqual(loaded["asset_test_99"]?.featurePrintData, sampleFeaturePrintData)
    }
    
    func testSimilarityMode_SaveAndLoad() {
        persistenceService.saveSimilarityMode(.aggressive)
        let loadedMode = persistenceService.loadSimilarityMode()
        XCTAssertEqual(loadedMode, .aggressive)
    }

    func testLastAnalyzedDate_SaveAndLoad_IsPerAlbum() {
        let vacationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let familyDate = Date(timeIntervalSince1970: 1_700_100_000)

        persistenceService.saveLastAnalyzedDate(vacationDate, forAlbumID: "album_vacation_101")
        persistenceService.saveLastAnalyzedDate(familyDate, forAlbumID: "album_family_102")

        let dates = persistenceService.loadLastAnalyzedDates()
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(dates["album_vacation_101"], vacationDate)
        XCTAssertEqual(dates["album_family_102"], familyDate)
        XCTAssertNil(dates["album_screenshots_103"], "Albums never analyzed should have no recorded date")
    }
}
