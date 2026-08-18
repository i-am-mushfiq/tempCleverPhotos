import XCTest
@testable import AlbumCuratorApp

final class PhotoKitSafetyTests: XCTestCase {
    
    /// Critical Architectural Safety Invariant Test (FR-014 & Section 28 of PRD)
    /// Verifies that no code path in the app contains a call to PHAssetChangeRequest.deleteAssets.
    func testSafetyInvariant_NoAssetDeletionCallsExistInSources() throws {
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let sourcesURL = currentDir.appendingPathComponent("Sources")
        
        if fileManager.fileExists(atPath: sourcesURL.path) {
            try verifyNoDeleteCalls(in: sourcesURL)
        } else {
            // Fallback for custom test runner directories
            let fallbackURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources")
            
            if fileManager.fileExists(atPath: fallbackURL.path) {
                try verifyNoDeleteCalls(in: fallbackURL)
            }
        }
    }
    
    private func verifyNoDeleteCalls(in directoryURL: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else { return }
        
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
