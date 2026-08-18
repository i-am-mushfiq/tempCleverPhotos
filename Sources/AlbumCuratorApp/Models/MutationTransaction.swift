import Foundation

/// Transaction log entry recording an album cleanup operation for undo support.
public struct MutationTransaction: Identifiable, Hashable, Codable {
    public let id: String
    public let albumID: String
    public let albumTitle: String
    public let removedAssetIDs: [String]
    public let timestamp: Date
    public var isUndone: Bool
    
    public init(
        id: String = UUID().uuidString,
        albumID: String,
        albumTitle: String,
        removedAssetIDs: [String],
        timestamp: Date = Date(),
        isUndone: Bool = false
    ) {
        self.id = id
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.removedAssetIDs = removedAssetIDs
        self.timestamp = timestamp
        self.isUndone = isUndone
    }
}
