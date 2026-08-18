import Foundation

/// Recommendation confidence levels matching FR-010.
public enum ClusterConfidence: String, CaseIterable, Codable {
    case high = "High Confidence"
    case medium = "Medium Confidence"
    case low = "Low Confidence"
    
    public var badgeColorName: String {
        switch self {
        case .high: return "green"
        case .medium: return "orange"
        case .low: return "gray"
        }
    }
}

/// A cluster of visually and temporally similar photos.
/// Supports multi-keeper selections as specified in Section 23 of the PRD.
public struct PhotoCluster: Identifiable, Hashable, Codable {
    public let id: String
    public let assetIDs: [String]
    public var recommendedKeepers: [String]
    public var candidatesForRemoval: [String]
    public let confidence: ClusterConfidence
    public var isUserOverridden: Bool
    public var isSkipped: Bool
    public let similarityScore: Double
    
    public init(
        id: String = UUID().uuidString,
        assetIDs: [String],
        recommendedKeepers: [String],
        candidatesForRemoval: [String],
        confidence: ClusterConfidence,
        isUserOverridden: Bool = false,
        isSkipped: Bool = false,
        similarityScore: Double = 0.85
    ) {
        self.id = id
        self.assetIDs = assetIDs
        self.recommendedKeepers = recommendedKeepers
        self.candidatesForRemoval = candidatesForRemoval
        self.confidence = confidence
        self.isUserOverridden = isUserOverridden
        self.isSkipped = isSkipped
        self.similarityScore = similarityScore
    }
    
    /// True if the given asset is marked as a keeper
    public func isKeeper(_ assetID: String) -> Bool {
        return recommendedKeepers.contains(assetID)
    }
    
    /// True if the given asset is selected for removal from album
    public func isCandidateForRemoval(_ assetID: String) -> Bool {
        return candidatesForRemoval.contains(assetID)
    }
    
    /// Toggle keeper state for a photo in the cluster
    public mutating func toggleKeeper(_ assetID: String) {
        isUserOverridden = true
        if isKeeper(assetID) {
            // Cannot unkeep if it's the last keeper (must have at least 1 keeper unless skipping group)
            if recommendedKeepers.count > 1 {
                recommendedKeepers.removeAll { $0 == assetID }
                if !candidatesForRemoval.contains(assetID) {
                    candidatesForRemoval.append(assetID)
                }
            }
        } else {
            recommendedKeepers.append(assetID)
            candidatesForRemoval.removeAll { $0 == assetID }
        }
    }
}
