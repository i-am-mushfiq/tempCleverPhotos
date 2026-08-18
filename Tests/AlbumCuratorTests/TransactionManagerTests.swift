import XCTest
@testable import AlbumCuratorApp

final class TransactionManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var persistenceService: LocalPersistenceService!
    var transactionManager: TransactionManager!
    var mockPhotoKit: MockPhotoKitService!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        persistenceService = LocalPersistenceService(storageDirectory: tempDirectory)
        transactionManager = TransactionManager(persistenceService: persistenceService)
        mockPhotoKit = MockPhotoKitService()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    func testRecordTransaction_AndUndoRestoration() async throws {
        let albumID = "album_vacation_101"
        let removedIDs = ["asset_vacation_burst_1", "asset_vacation_burst_2"]
        
        // Record transaction
        let tx = transactionManager.recordTransaction(
            albumID: albumID,
            albumTitle: "Summer Vacation 2026",
            removedAssetIDs: removedIDs
        )
        
        XCTAssertEqual(transactionManager.transactions.count, 1)
        XCTAssertEqual(transactionManager.transactions.first?.id, tx.id)
        XCTAssertFalse(tx.isUndone)
        
        // Execute undo
        let undoSuccess = try await transactionManager.undoTransaction(tx.id, photoKitService: mockPhotoKit)
        XCTAssertTrue(undoSuccess, "Undo operation should return true")
        
        let updatedTx = transactionManager.transactions.first(where: { $0.id == tx.id })
        XCTAssertTrue(updatedTx?.isUndone == true, "Transaction should be marked as undone")
        
        // Verify assets restored in mock PhotoKit
        let currentAssets = await mockPhotoKit.fetchAssets(in: albumID)
        for id in removedIDs {
            XCTAssertTrue(currentAssets.contains(where: { $0.id == id }), "Asset \(id) should be restored to album after undo")
        }
    }
}
