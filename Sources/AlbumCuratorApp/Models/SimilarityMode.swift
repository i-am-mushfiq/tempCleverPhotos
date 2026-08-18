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

    /// Max time difference in seconds between photos considered for the same cluster.
    public var maxTimeIntervalSeconds: TimeInterval {
        switch self {
        case .conservative: return 30.0    // 30 seconds
        case .balanced:     return 180.0   // 3 minutes
        case .aggressive:   return 600.0   // 10 minutes
        }
    }

    /// VNFeaturePrintObservation distance threshold (lower = more similar).
    /// computeDistance() returns Float: 0.0 = identical, higher = more different.
    /// Empirically: < 0.35 is near-identical, > 0.75 is clearly different.
    public var featurePrintDistanceThreshold: Float {
        switch self {
        case .conservative: return 0.35   // Only near-identical shots
        case .balanced:     return 0.55   // Same scene / burst
        case .aggressive:   return 0.75   // Visually related shots
        }
    }
}
