import Foundation

/// Detailed analysis output for a photo asset combining perceptual, visual, and quality signals.
public struct PhotoAnalysis: Identifiable, Hashable, Codable {
    public var id: String { assetID }
    public let assetID: String
    
    // Perceptual & Visual Features
    public let perceptualHash: UInt64
    public let featureVector: [Float]
    
    // Technical Signals
    public let sharpnessScore: Double   // Laplacian variance / gradient magnitude (0.0 to 1.0)
    public let exposureBalance: Double  // Histogram exposure quality (0.0 to 1.0)
    public let noiseScore: Double       // High-frequency noise estimation (0.0 to 1.0, higher is cleaner)
    
    // Subject Signals
    public let faceCount: Int
    public let eyesOpenRatio: Double    // Percentage of faces with eyes open (0.0 to 1.0)
    public let smileProminence: Double  // Facial expression signal (0.0 to 1.0)
    
    // Aesthetic Signals
    public let compositionScore: Double // Balance & subject positioning (0.0 to 1.0)
    public let overallQualityScore: Double // Weighted composite score
    
    public let analysisVersion: String
    public let timestamp: Date
    
    public init(
        assetID: String,
        perceptualHash: UInt64,
        featureVector: [Float] = [],
        sharpnessScore: Double,
        exposureBalance: Double,
        noiseScore: Double = 0.9,
        faceCount: Int = 0,
        eyesOpenRatio: Double = 1.0,
        smileProminence: Double = 0.5,
        compositionScore: Double = 0.8,
        overallQualityScore: Double? = nil,
        analysisVersion: String = "1.0.0",
        timestamp: Date = Date()
    ) {
        self.assetID = assetID
        self.perceptualHash = perceptualHash
        self.featureVector = featureVector
        self.sharpnessScore = sharpnessScore
        self.exposureBalance = exposureBalance
        self.noiseScore = noiseScore
        self.faceCount = faceCount
        self.eyesOpenRatio = eyesOpenRatio
        self.smileProminence = smileProminence
        self.compositionScore = compositionScore
        self.analysisVersion = analysisVersion
        self.timestamp = timestamp
        
        if let explicitScore = overallQualityScore {
            self.overallQualityScore = explicitScore
        } else {
            // Calculate weighted quality score
            let technicalComponent = (sharpnessScore * 0.4) + (exposureBalance * 0.3) + (noiseScore * 0.3)
            let subjectComponent = faceCount > 0 ? (eyesOpenRatio * 0.7 + smileProminence * 0.3) : 0.7
            let aestheticComponent = compositionScore
            
            self.overallQualityScore = (technicalComponent * 0.45) + (subjectComponent * 0.35) + (aestheticComponent * 0.20)
        }
    }
}
