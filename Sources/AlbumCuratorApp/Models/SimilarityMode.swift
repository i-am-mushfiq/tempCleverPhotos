import Foundation

/// User-configurable similarity mode as specified in FR-007.
public enum SimilarityMode: String, CaseIterable, Identifiable, Codable {
    case conservative = "Conservative"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .conservative:
            return "Only very similar shots (e.g. burst sequences)"
        case .balanced:
            return "Similar shots of the same moment or scene"
        case .aggressive:
            return "Visually similar shots across broader time windows"
        }
    }
    
    /// Max time difference in seconds between photos in a cluster
    public var maxTimeIntervalSeconds: TimeInterval {
        switch self {
        case .conservative: return 30.0    // 30 seconds
        case .balanced:     return 180.0   // 3 minutes
        case .aggressive:   return 600.0   // 10 minutes
        }
    }
    
    /// Hamming distance threshold for perceptual hash comparison (lower = stricter)
    public var hashDistanceThreshold: Int {
        switch self {
        case .conservative: return 8
        case .balanced:     return 14
        case .aggressive:   return 20
        }
    }
    
    /// Feature vector cosine similarity threshold (0.0 to 1.0, higher = stricter)
    public var featureSimilarityThreshold: Float {
        switch self {
        case .conservative: return 0.88
        case .balanced:     return 0.78
        case .aggressive:   return 0.68
        }
    }
}
