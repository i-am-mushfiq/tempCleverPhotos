import Foundation
import Photos

public enum PhotosAuthorizationState: String {
    case authorized
    case limited
    case denied
    case notDetermined
}

public protocol PhotoKitServiceProtocol {
    func checkAuthorizationStatus() -> PhotosAuthorizationState
    func requestAuthorization() async -> PhotosAuthorizationState
    func fetchAlbums() async -> [PhotoAlbum]
    func fetchAssets(in albumID: String) async -> [PhotoAsset]
    
    /// Non-destructive mutation: Removes specified assets from the album.
    /// SAFE INVARIANT: Never deletes assets from the user's Photos Library.
    func removeAssetsFromAlbum(assetIDs: [String], albumID: String) async throws -> Bool
    
    /// Re-adds assets back to the specified album for undo operations.
    func restoreAssetsToAlbum(assetIDs: [String], albumID: String) async throws -> Bool
}

/// Concrete PhotoKit service communicating with Apple's PhotoKit framework.
public class PhotoKitService: PhotoKitServiceProtocol {
    public init() {}
    
    public func checkAuthorizationStatus() -> PhotosAuthorizationState {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    public func requestAuthorization() async -> PhotosAuthorizationState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
    
    public func fetchAlbums() async -> [PhotoAlbum] {
        return await withCheckedContinuation { continuation in
            var albums: [PhotoAlbum] = []
            
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userAlbums.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                let coverID = assets.firstObject?.localIdentifier
                let album = PhotoAlbum(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled Album",
                    assetCount: assets.count,
                    thumbnailAssetID: coverID
                )
                albums.append(album)
            }
            
            let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            smartAlbums.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                if assets.count > 0 {
                    let coverID = assets.firstObject?.localIdentifier
                    let album = PhotoAlbum(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Smart Album",
                        assetCount: assets.count,
                        thumbnailAssetID: coverID
                    )
                    albums.append(album)
                }
            }
            
            continuation.resume(returning: albums)
        }
    }
    
    public func fetchAssets(in albumID: String) async -> [PhotoAsset] {
        return await withCheckedContinuation { continuation in
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            guard let collection = collections.firstObject else {
                continuation.resume(returning: [])
                return
            }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let phAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            var assets: [PhotoAsset] = []
            
            phAssets.enumerateObjects { asset, _, _ in
                let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                let item = PhotoAsset(
                    id: asset.localIdentifier,
                    localIdentifier: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isLivePhoto: isLivePhoto,
                    isFavorite: asset.isFavorite
                )
                assets.append(item)
            }
            
            continuation.resume(returning: assets)
        }
    }
    
    /// SAFELY removes assets from the designated album WITHOUT deleting them from PHPhotoLibrary.
    public func removeAssetsFromAlbum(assetIDs: [String], albumID: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            guard let collection = collections.firstObject else {
                continuation.resume(returning: false)
                return
            }
            
            let assetsToFetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
            
            PHPhotoLibrary.shared().performChanges({
                guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: collection) else { return }
                // ONLY remove from album - DO NOT call asset deletion APIs!
                albumChangeRequest.removeAssets(assetsToFetch)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    /// Re-adds assets to the album (Undo operation).
    public func restoreAssetsToAlbum(assetIDs: [String], albumID: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            guard let collection = collections.firstObject else {
                continuation.resume(returning: false)
                return
            }
            
            let assetsToFetch = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
            
            PHPhotoLibrary.shared().performChanges({
                guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: collection) else { return }
                albumChangeRequest.addAssets(assetsToFetch)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
