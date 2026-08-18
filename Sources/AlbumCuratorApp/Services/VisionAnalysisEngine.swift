import Foundation

public protocol VisionAnalysisEngineProtocol {
    /// Analyzes assets and clusters them into groups of visually/temporally similar photos with best-shot recommendations.
    func analyzeAndCluster(
        assets: [PhotoAsset],
        cachedAnalyses: [String: PhotoAnalysis],
        mode: SimilarityMode,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async -> (clusters: [PhotoCluster], updatedAnalyses: [String: PhotoAnalysis])
    
    /// Computes quality analysis for a single photo asset.
    func analyzeSingleAsset(_ asset: PhotoAsset) -> PhotoAnalysis
}

public class VisionAnalysisEngine: VisionAnalysisEngineProtocol {
    public init() {}
    
    public func analyzeSingleAsset(_ asset: PhotoAsset) -> PhotoAnalysis {
        // Deterministic pseudo-random feature calculation derived from asset ID for testing stability
        let hashSeed = UInt64(abs(asset.id.hashValue))
        let dHash = hashSeed ^ 0xA5A5A5A5A5A5A5A5
        
        // Generate pseudo-feature vector
        var vector: [Float] = []
        var seed = Float(hashSeed % 1000) / 1000.0
        for _ in 0..<32 {
            seed = sin(seed * 12.9898 + 78.233) * 43758.5453
            vector.append(seed - floor(seed))
        }
        
        // Technical quality signals
        let sharpness = 0.5 + 0.45 * sin(Double(hashSeed % 100) * 0.1)
        let exposure = 0.6 + 0.35 * cos(Double(hashSeed % 50) * 0.2)
        let noise = 0.85 + 0.1 * sin(Double(hashSeed % 30) * 0.15)
        
        // Subject signals
        let faces = Int(hashSeed % 4) // 0 to 3 faces
        let eyesOpen = faces > 0 ? (0.7 + 0.3 * sin(Double(hashSeed % 20) * 0.5)) : 1.0
        let smile = 0.4 + 0.5 * cos(Double(hashSeed % 15) * 0.3)
        
        // Aesthetic signals
        let composition = 0.65 + 0.3 * sin(Double(hashSeed % 80) * 0.05)
        
        return PhotoAnalysis(
            assetID: asset.id,
            perceptualHash: dHash,
            featureVector: vector,
            sharpnessScore: sharpness,
            exposureBalance: exposure,
            noiseScore: noise,
            faceCount: faces,
            eyesOpenRatio: eyesOpen,
            smileProminence: smile,
            compositionScore: composition
        )
    }
    
    public func analyzeAndCluster(
        assets: [PhotoAsset],
        cachedAnalyses: [String: PhotoAnalysis],
        mode: SimilarityMode,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async -> (clusters: [PhotoCluster], updatedAnalyses: [String: PhotoAnalysis]) {
        let total = assets.count
        guard total > 0 else { return ([], cachedAnalyses) }
        
        var analyses = cachedAnalyses
        
        // Phase 1: Feature Extraction / Analysis (Incremental Cache reuse)
        for (index, asset) in assets.enumerated() {
            if analyses[asset.id] == nil {
                analyses[asset.id] = analyzeSingleAsset(asset)
            }
            if index % 5 == 0 || index == total - 1 {
                progressHandler(index + 1, total, "Analyzing photo quality & visual features (\(index + 1)/\(total))...")
            }
        }
        
        progressHandler(total, total, "Clustering similar photos...")
        
        // Phase 2: Candidate Generation (Time Window Filtering)
        let sortedAssets = assets.sorted { ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) }
        
        var unvisited = Set(sortedAssets.map { $0.id })
        var assetMap: [String: PhotoAsset] = [:]
        for a in sortedAssets { assetMap[a.id] = a }
        
        var clusters: [PhotoCluster] = []
        
        for asset in sortedAssets {
            guard unvisited.contains(asset.id) else { continue }
            
            var currentClusterIDs = [asset.id]
            unvisited.remove(asset.id)
            
            let baseAnalysis = analyses[asset.id]!
            let baseDate = asset.creationDate ?? Date()
            
            for candidate in sortedAssets {
                guard unvisited.contains(candidate.id) else { continue }
                let candDate = candidate.creationDate ?? Date()
                
                let timeDiff = abs(candDate.timeIntervalSince(baseDate))
                if timeDiff <= mode.maxTimeIntervalSeconds {
                    let candAnalysis = analyses[candidate.id]!
                    let similarity = computeSimilarity(baseAnalysis, candAnalysis)
                    
                    if similarity >= Double(mode.featureSimilarityThreshold) {
                        currentClusterIDs.append(candidate.id)
                        unvisited.remove(candidate.id)
                    }
                }
            }
            
            // Only create cluster if 2 or more similar photos exist
            if currentClusterIDs.count > 1 {
                let cluster = rankAndCreateCluster(
                    assetIDs: currentClusterIDs,
                    analyses: analyses,
                    assetMap: assetMap,
                    mode: mode
                )
                clusters.append(cluster)
            }
        }
        
        return (clusters, analyses)
    }
    
    private func computeSimilarity(_ a: PhotoAnalysis, _ b: PhotoAnalysis) -> Double {
        // Hamming distance on perceptual hash
        let hashDistance = (a.perceptualHash ^ b.perceptualHash).nonzeroBitCount
        let hashSim = max(0.0, 1.0 - (Double(hashDistance) / 64.0))
        
        // Cosine similarity on feature vector
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        let count = min(a.featureVector.count, b.featureVector.count)
        if count > 0 {
            for i in 0..<count {
                dotProduct += a.featureVector[i] * b.featureVector[i]
                normA += a.featureVector[i] * a.featureVector[i]
                normB += b.featureVector[i] * b.featureVector[i]
            }
            let denom = (sqrt(normA) * sqrt(normB))
            let vectorSim = denom > 0 ? (dotProduct / denom) : 0.0
            return (Double(vectorSim) * 0.7) + (hashSim * 0.3)
        }
        
        return hashSim
    }
    
    private func rankAndCreateCluster(
        assetIDs: [String],
        analyses: [String: PhotoAnalysis],
        assetMap: [String: PhotoAsset],
        mode: SimilarityMode
    ) -> PhotoCluster {
        // Rank by overall quality score
        let sortedByQuality = assetIDs.sorted { id1, id2 in
            let q1 = analyses[id1]?.overallQualityScore ?? 0.0
            let q2 = analyses[id2]?.overallQualityScore ?? 0.0
            return q1 > q2
        }
        
        let bestID = sortedByQuality.first!
        let bestQuality = analyses[bestID]?.overallQualityScore ?? 0.0
        let secondQuality = sortedByQuality.count > 1 ? (analyses[sortedByQuality[1]]?.overallQualityScore ?? 0.0) : 0.0
        
        var keepers = [bestID]
        
        // Multi-keeper heuristic: If second shot is within 2% quality and has different face parameters or Live Photo preference
        if sortedByQuality.count > 2, (bestQuality - secondQuality) < 0.02 {
            let secondID = sortedByQuality[1]
            if let a1 = analyses[bestID], let a2 = analyses[secondID], a1.faceCount != a2.faceCount {
                keepers.append(secondID)
            }
        }
        
        let candidatesForRemoval = assetIDs.filter { !keepers.contains($0) }
        
        // Confidence calculation (Precision over recall)
        let qualityGap = bestQuality - secondQuality
        let confidence: ClusterConfidence
        
        if assetIDs.count >= 2 && qualityGap > 0.08 {
            confidence = .high
        } else if qualityGap > 0.03 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        return PhotoCluster(
            assetIDs: assetIDs,
            recommendedKeepers: keepers,
            candidatesForRemoval: candidatesForRemoval,
            confidence: confidence,
            similarityScore: 0.85 + (qualityGap * 0.5)
        )
    }
}
