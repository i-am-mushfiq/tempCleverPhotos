import Foundation

/// In-memory mock PhotoKit service for testing and preview execution.
public class MockPhotoKitService: PhotoKitServiceProtocol {
    public var mockAlbums: [PhotoAlbum] = []
    public var mockAssetsByAlbum: [String: [PhotoAsset]] = [:]
    public var removedAssetsLog: [String: [String]] = [:] // albumID -> assetIDs
    
    public init() {
        setupDefaultMockData()
    }
    
    public func requestAuthorization() async -> PhotosAuthorizationState {
        return .authorized
    }
    
    public func fetchAlbums() async -> [PhotoAlbum] {
        return mockAlbums
    }
    
    public func fetchAssets(in albumID: String) async -> [PhotoAsset] {
        return mockAssetsByAlbum[albumID] ?? []
    }
    
    public func removeAssetsFromAlbum(assetIDs: [String], albumID: String) async throws -> Bool {
        if var current = mockAssetsByAlbum[albumID] {
            current.removeAll { assetIDs.contains($0.id) }
            mockAssetsByAlbum[albumID] = current
        }
        
        var removed = removedAssetsLog[albumID] ?? []
        removed.append(contentsOf: assetIDs)
        removedAssetsLog[albumID] = removed
        
        // Update album count
        if let index = mockAlbums.firstIndex(where: { $0.id == albumID }) {
            let old = mockAlbums[index]
            mockAlbums[index] = PhotoAlbum(
                id: old.id,
                title: old.title,
                assetCount: mockAssetsByAlbum[albumID]?.count ?? 0,
                thumbnailAssetID: old.thumbnailAssetID,
                lastAnalyzedDate: old.lastAnalyzedDate
            )
        }
        return true
    }
    
    public func restoreAssetsToAlbum(assetIDs: [String], albumID: String) async throws -> Bool {
        if let removed = removedAssetsLog[albumID] {
            let toRestore = removed.filter { assetIDs.contains($0) }
            
            // Re-create dummy assets for restored items
            for id in toRestore {
                let asset = PhotoAsset(
                    id: id,
                    localIdentifier: id,
                    creationDate: Date(),
                    customLabel: "Restored Asset \(id.prefix(4))"
                )
                mockAssetsByAlbum[albumID, default: []].append(asset)
            }
        }
        
        // Update album count
        if let index = mockAlbums.firstIndex(where: { $0.id == albumID }) {
            let old = mockAlbums[index]
            mockAlbums[index] = PhotoAlbum(
                id: old.id,
                title: old.title,
                assetCount: mockAssetsByAlbum[albumID]?.count ?? 0,
                thumbnailAssetID: old.thumbnailAssetID,
                lastAnalyzedDate: Date()
            )
        }
        return true
    }
    
    private func setupDefaultMockData() {
        let vacationID = "album_vacation_101"
        let familyID = "album_family_102"
        let screenshotsID = "album_screenshots_103"
        
        mockAlbums = [
            PhotoAlbum(id: vacationID, title: "Summer Vacation 2026", assetCount: 14),
            PhotoAlbum(id: familyID, title: "Family Gathering", assetCount: 8),
            PhotoAlbum(id: screenshotsID, title: "Screenshots & Receipts", assetCount: 5)
        ]
        
        let now = Date()
        
        // Group 1: 4 rapid burst landscape shots
        var vacationAssets: [PhotoAsset] = []
        for i in 1...4 {
            let asset = PhotoAsset(
                id: "asset_vacation_burst_\(i)",
                localIdentifier: "ph_vacation_\(i)",
                creationDate: now.addingTimeInterval(Double(i * 3)), // 3 sec apart
                pixelWidth: 4032,
                pixelHeight: 3024,
                isLivePhoto: i == 2,
                customLabel: "Beach Landscape \(i)"
            )
            vacationAssets.append(asset)
        }
        
        // Group 2: 5 group portraits
        for i in 1...5 {
            let asset = PhotoAsset(
                id: "asset_vacation_portrait_\(i)",
                localIdentifier: "ph_portrait_\(i)",
                creationDate: now.addingTimeInterval(600 + Double(i * 4)), // 10 min later
                pixelWidth: 4032,
                pixelHeight: 3024,
                isLivePhoto: false,
                customLabel: "Sunset Group Shot \(i)"
            )
            vacationAssets.append(asset)
        }
        
        // Group 3: 5 food photography shots
        for i in 1...5 {
            let asset = PhotoAsset(
                id: "asset_vacation_food_\(i)",
                localIdentifier: "ph_food_\(i)",
                creationDate: now.addingTimeInterval(3600 + Double(i * 5)), // 1 hr later
                pixelWidth: 3024,
                pixelHeight: 3024,
                isLivePhoto: false,
                customLabel: "Dinner Plate \(i)"
            )
            vacationAssets.append(asset)
        }
        
        mockAssetsByAlbum[vacationID] = vacationAssets
        
        // Family Album Assets
        var familyAssets: [PhotoAsset] = []
        for i in 1...8 {
            let asset = PhotoAsset(
                id: "asset_family_\(i)",
                localIdentifier: "ph_family_\(i)",
                creationDate: now.addingTimeInterval(Double(i * 5)),
                pixelWidth: 4032,
                pixelHeight: 3024,
                customLabel: "Family Pose \(i)"
            )
            familyAssets.append(asset)
        }
        mockAssetsByAlbum[familyID] = familyAssets
    }
}
