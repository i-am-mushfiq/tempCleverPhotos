import Foundation

/// Detailed analysis output for a photo asset combining perceptual, visual, and quality signals.
/// analysisVersion "2.0.0" uses real Vision.framework feature prints; older cached entries are discarded.
public struct PhotoAnalysis: Identifiable, Hashable, Codable {
    public var id: String { assetID }
    public let assetID: String

    /// Serialized VNFeaturePrintObservation (NSKeyedArchiver) for disk caching across sessions.
    /// nil when the asset's thumbnail was unavailable at analysis time.
    public let featurePrintData: Data?

    // Technical Signals — populated by CoreImage filters
    public let sharpnessScore: Double   // CIEdges brightness proxy (0.0 blurry → 1.0 sharp)
    public let exposureBalance: Double  // Proximity of average luminance to 0.5 ideal (0.0 → 1.0)
    public let noiseScore: Double       // Reserved; default 0.9

    // Subject Signals — populated by VNDetectFaceRectanglesRequest
    public let faceCount: Int
    public let eyesOpenRatio: Double    // Reserved; default 1.0
    public let smileProminence: Double  // Reserved; default 0.5

    // Aesthetic Signals
    public let compositionScore: Double // Reserved; default 0.8
    public let overallQualityScore: Double // Weighted composite

    public let analysisVersion: String
    public let timestamp: Date

    public init(
        assetID: String,
        featurePrintData: Data? = nil,
        sharpnessScore: Double,
        exposureBalance: Double,
        noiseScore: Double = 0.9,
        faceCount: Int = 0,
        eyesOpenRatio: Double = 1.0,
        smileProminence: Double = 0.5,
        compositionScore: Double = 0.8,
        overallQualityScore: Double? = nil,
        analysisVersion: String = "2.0.0",
        timestamp: Date = Date()
    ) {
        self.assetID = assetID
        self.featurePrintData = featurePrintData
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
            let technicalComponent = (sharpnessScore * 0.4) + (exposureBalance * 0.3) + (noiseScore * 0.3)
            let subjectComponent = faceCount > 0 ? (eyesOpenRatio * 0.7 + smileProminence * 0.3) : 0.7
            let aestheticComponent = compositionScore
            self.overallQualityScore = (technicalComponent * 0.45) + (subjectComponent * 0.35) + (aestheticComponent * 0.20)
        }
    }
}
