import Foundation

/// Turns the raw per-photo quality signals into a short, human-readable reason for
/// why one photo beat another within a cluster — e.g. "Sharper", "Eyes closed here".
/// These signals are heuristic approximations (geometric proxies from Vision landmarks
/// and CoreImage filters), not a trained aesthetic model, so this surfaces the single
/// biggest measured gap rather than pretending to give an exhaustive breakdown.
public enum RecommendationExplainer {
    private enum Signal {
        case sharpness
        case exposure
        case noise
        case composition
        case eyesOpen
        case expression
        case tooClose
    }

    /// The single most differentiating signal between `keeper` and `other`, judged by
    /// which measured gap is largest. Face-related signals (eyes/expression) are only
    /// considered when at least one of the two photos actually has a detected face.
    private static func dominantSignal(keeper: PhotoAnalysis, other: PhotoAnalysis) -> Signal {
        var gaps: [(Signal, Double)] = [
            (.sharpness, keeper.sharpnessScore - other.sharpnessScore),
            (.exposure, keeper.exposureBalance - other.exposureBalance),
            (.noise, keeper.noiseScore - other.noiseScore),
            (.composition, keeper.compositionScore - other.compositionScore)
        ]

        if keeper.faceCount > 0 || other.faceCount > 0 {
            gaps.append((.eyesOpen, keeper.eyesOpenRatio - other.eyesOpenRatio))
            gaps.append((.expression, keeper.smileProminence - other.smileProminence))
        }

        guard let top = gaps.max(by: { abs($0.1) < abs($1.1) }), abs(top.1) > 0.06 else {
            return .tooClose
        }
        return top.0
    }

    /// Caption for the recommended keeper, framed positively against the weakest
    /// removal candidate in its cluster (the clearest contrast available).
    public static func keeperReason(keeper: PhotoAnalysis, weakestOther: PhotoAnalysis) -> String {
        switch dominantSignal(keeper: keeper, other: weakestOther) {
        case .sharpness: return "Sharpest in this group"
        case .exposure: return "Best exposed in this group"
        case .noise: return "Cleanest, least noise"
        case .composition: return "Best framed shot"
        case .eyesOpen: return "Eyes open here"
        case .expression: return "Best expression"
        case .tooClose: return "Marginally the best of very similar shots"
        }
    }

    /// Caption for a removal candidate, framed relative to the keeper it lost to.
    public static func removalReason(candidate: PhotoAnalysis, keeper: PhotoAnalysis) -> String {
        switch dominantSignal(keeper: keeper, other: candidate) {
        case .sharpness: return "Blurrier than the keeper"
        case .exposure: return "Worse exposed than the keeper"
        case .noise: return "Noisier than the keeper"
        case .composition: return "Less well framed than the keeper"
        case .eyesOpen: return "Eyes closed here"
        case .expression: return "Weaker expression than the keeper"
        case .tooClose: return "Nearly identical to the keeper"
        }
    }
}
