import XCTest
@testable import AlbumCuratorApp

final class PhotoKitSafetyTests: XCTestCase {
    
    /// Critical Architectural Safety Invariant Test (FR-014 & Section 28 of PRD)
    /// Verifies that no code path in the app contains a call to PHAssetChangeRequest.deleteAssets.
    func testSafetyInvariant_NoAssetDeletionCallsExistInSources() throws {
        let currentFileURL = URL(fileURLWithPath: #file)
        let rootSourcesURL = currentFileURL
            .deletingLastPathComponent() // AlbumCuratorTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources")
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootSourcesURL.path) else {
            XCTFail("Sources directory not found at path: \(rootSourcesURL.path)")
            return
        }
        
        guard let enumerator = fileManager.enumerator(at: rootSourcesURL, includingPropertiesForKeys: nil) else {
            XCTFail("Failed to enumerate Sources directory")
            return
        }
        
        var foundDeleteCalls: [String] = []
        
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if content.contains("deleteAssets") {
                foundDeleteCalls.append(fileURL.lastPathComponent)
            }
        }
        
        XCTAssertTrue(
            foundDeleteCalls.isEmpty,
            "CRITICAL SAFETY VIOLATION: Source files contain deleteAssets API calls: \(foundDeleteCalls). Non-destructive architectural invariant failed!"
        )
    }
    
    /// Verifies that album mutation only removes items from mock album without destroying the assets
    func testAlbumMutation_IsNonDestructive() async throws {
        let mockService = MockPhotoKitService()
        let albumID = "album_vacation_101"
        
        let initialAssets = await mockService.fetchAssets(in: albumID)
        XCTAssertFalse(initialAssets.isEmpty, "Initial test album should contain photos")
        
        let targetToRemove = [initialAssets.first!.id]
        
        // Perform removal from album
        let success = try await mockService.removeAssetsFromAlbum(assetIDs: targetToRemove, albumID: albumID)
        XCTAssertTrue(success, "Album removal operation should succeed")
        
        let updatedAssets = await mockService.fetchAssets(in: albumID)
        XCTAssertEqual(updatedAssets.count, initialAssets.count - 1, "Album photo count should decrease by 1")
        XCTAssertFalse(updatedAssets.contains(where: { $0.id == targetToRemove.first! }), "Removed asset should no longer exist in album")
        
        // Verify asset exists in global log (simulating Photos Library persistence)
        XCTAssertTrue(mockService.removedAssetsLog[albumID]?.contains(targetToRemove.first!) == true)
    }
}
