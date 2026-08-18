import Foundation
import Photos

/// Represents an individual photo asset within an album.
/// Enforces atomic handling of Live Photos as specified in FR-005.
public struct PhotoAsset: Identifiable, Hashable, Codable {
    public let id: String
    public let localIdentifier: String
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isLivePhoto: Bool
    public let isFavorite: Bool
    public var customLabel: String?

    public init(
        id: String = UUID().uuidString,
        localIdentifier: String,
        creationDate: Date? = Date(),
        pixelWidth: Int = 4032,
        pixelHeight: Int = 3024,
        isLivePhoto: Bool = false,
        isFavorite: Bool = false,
        customLabel: String? = nil
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isLivePhoto = isLivePhoto
        self.isFavorite = isFavorite
        self.customLabel = customLabel
    }

    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 1.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

/// Lightweight representation of a user-created Photos Album collection.
/// Smart albums (Recents, Favorites, etc.) are excluded from the app's album list
/// because PHAssetCollectionChangeRequest returns nil for read-only collections,
/// making them unmutable.
public struct PhotoAlbum: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let assetCount: Int
    public var thumbnailAssetID: String?
    public var lastAnalyzedDate: Date?
    /// True for PHAssetCollectionType.smartAlbum — read-only, cannot be mutated.
    public let isReadOnly: Bool

    public init(
        id: String,
        title: String,
        assetCount: Int,
        thumbnailAssetID: String? = nil,
        lastAnalyzedDate: Date? = nil,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.title = title
        self.assetCount = assetCount
        self.thumbnailAssetID = thumbnailAssetID
        self.lastAnalyzedDate = lastAnalyzedDate
        self.isReadOnly = isReadOnly
    }
}
