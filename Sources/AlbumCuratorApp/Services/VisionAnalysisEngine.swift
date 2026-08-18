import Foundation
import Vision
import CoreImage
import Photos

// MARK: - Protocol

public protocol VisionAnalysisEngineProtocol {
    /// Analyzes assets and clusters them by real visual similarity.
    /// Uses VNFeaturePrintObservation for perceptual comparison and CoreImage for quality signals.
    func analyzeAndCluster(
        assets: [PhotoAsset],
        cachedAnalyses: [String: PhotoAnalysis],
        mode: SimilarityMode,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async -> (clusters: [PhotoCluster], updatedAnalyses: [String: PhotoAnalysis])

    /// Computes quality analysis for a single photo asset (synchronous fallback, used in tests).
    func analyzeSingleAsset(_ asset: PhotoAsset) -> PhotoAnalysis
}

// MARK: - Engine

public class VisionAnalysisEngine: VisionAnalysisEngineProtocol {

    private let currentVersion = "2.0.0"

    public init() {}

    // MARK: - Thumbnail Loading

    /// Loads a small CGImage thumbnail for Vision analysis via PHImageManager.
    private func loadThumbnail(for asset: PhotoAsset) async -> CGImage? {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil)
        guard let phAsset = results.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat      // Fastest available quality
            options.isNetworkAccessAllowed = false   // On-device only
            options.isSynchronous = false
            options.resizeMode = .fast

            PHImageManager.default().requestImage(
                for: phAsset,
                targetSize: CGSize(width: 224, height: 224),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: - Vision Analysis

    /// Generates a VNFeaturePrintObservation for perceptual comparison.
    private func generateFeaturePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// Counts detected faces via VNDetectFaceRectanglesRequest.
    private func detectFaces(in cgImage: CGImage) -> Int {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.count ?? 0
    }

    // MARK: - CoreImage Quality Signals

    /// Sharpness: brightness of CIEdges output.
    /// Blurry images have weak edges → low brightness → low score.
    private func computeSharpness(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let edgesFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        edgesFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgesFilter.setValue(5.0, forKey: kCIInputIntensityKey)
        guard let edgeOutput = edgesFilter.outputImage else { return 0.5 }

        return averageLuminance(of: edgeOutput, extent: ciImage.extent, context: context)
    }

    /// Exposure balance: how close the average luminance is to the ideal mid-tone (0.5).
    /// Perfect exposure → score near 1.0. Very dark or blown-out → score near 0.0.
    private func computeExposure(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Desaturate to measure luminance only
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return 0.5 }
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let grayOutput = colorFilter.outputImage else { return 0.5 }

        let luminance = averageLuminance(of: grayOutput, extent: ciImage.extent, context: context)
        // Penalise deviation from ideal 0.5: deviation of 0.5 → score 0.0
        return max(0.0, 1.0 - (abs(luminance - 0.5) * 2.0))
    }

    /// Renders a CIImage to a 1×1 pixel and returns its average luminance (0.0–1.0).
    private func averageLuminance(of image: CIImage, extent: CGRect, context: CIContext) -> Double {
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(image, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // BT.601 luminance from RGB
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // MARK: - Feature Print Serialization

    /// Serializes a VNFeaturePrintObservation to Data for disk caching.
    private func serializeFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    /// Deserializes a VNFeaturePrintObservation from cached Data.
    private func deserializeFeaturePrint(from data: Data) -> VNFeaturePrintObservation? {
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    // MARK: - Single Asset (Synchronous Fallback)

    /// Synchronous stub — used in tests or when no thumbnail is available.
    /// Production analysis goes through analyzeAndCluster.
    public func analyzeSingleAsset(_ asset: PhotoAsset) -> PhotoAnalysis {
        return PhotoAnalysis(
            assetID: asset.id,
            featurePrintData: nil,
            sharpnessScore: 0.5,
            exposureBalance: 0.5,
            faceCount: 0,
            analysisVersion: currentVersion
        )
    }

    // MARK: - Main Entry Point

    public func analyzeAndCluster(
        assets: [PhotoAsset],
        cachedAnalyses: [String: PhotoAnalysis],
        mode: SimilarityMode,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async -> (clusters: [PhotoCluster], updatedAnalyses: [String: PhotoAnalysis]) {
        let total = assets.count
        guard total > 0 else { return ([], cachedAnalyses) }

        var analyses = cachedAnalyses

        // ── Phase 1: Feature Extraction ──────────────────────────────────────────
        // Re-analyse only assets missing from cache or from an older version.
        for (index, asset) in assets.enumerated() {
            let needsAnalysis = analyses[asset.id].map { $0.analysisVersion != currentVersion } ?? true

            if needsAnalysis {
                if let cgImage = await loadThumbnail(for: asset) {
                    let featurePrint = generateFeaturePrint(for: cgImage)
                    let faceCount   = detectFaces(in: cgImage)
                    let sharpness   = computeSharpness(cgImage: cgImage)
                    let exposure    = computeExposure(cgImage: cgImage)
                    let fpData      = featurePrint.flatMap { serializeFeaturePrint($0) }

                    analyses[asset.id] = PhotoAnalysis(
                        assetID: asset.id,
                        featurePrintData: fpData,
                        sharpnessScore: sharpness,
                        exposureBalance: exposure,
                        faceCount: faceCount,
                        analysisVersion: currentVersion
                    )
                } else {
                    // Thumbnail unavailable (e.g. iCloud-only asset offline) — neutral scores
                    analyses[asset.id] = PhotoAnalysis(
                        assetID: asset.id,
                        featurePrintData: nil,
                        sharpnessScore: 0.5,
                        exposureBalance: 0.5,
                        faceCount: 0,
                        analysisVersion: currentVersion
                    )
                }
            }

            if index % 5 == 0 || index == total - 1 {
                progressHandler(
                    index + 1, total,
                    "Analyzing photo quality & visual features (\(index + 1)/\(total))..."
                )
            }
        }

        progressHandler(total, total, "Clustering similar photos...")

        // ── Phase 2: Reconstruct feature prints for clustering ────────────────────
        var featurePrints: [String: VNFeaturePrintObservation] = [:]
        for asset in assets {
            if let data = analyses[asset.id]?.featurePrintData,
               let fp = deserializeFeaturePrint(from: data) {
                featurePrints[asset.id] = fp
            }
        }

        // ── Phase 3: Time-window + feature-print clustering ───────────────────────
        let sortedAssets = assets.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
        var unvisited = Set(sortedAssets.map { $0.id })
        var assetMap: [String: PhotoAsset] = [:]
        for a in sortedAssets { assetMap[a.id] = a }

        var clusters: [PhotoCluster] = []
        let distanceThreshold = mode.featurePrintDistanceThreshold
        let timeWindow        = mode.maxTimeIntervalSeconds

        for asset in sortedAssets {
            guard unvisited.contains(asset.id) else { continue }

            var clusterIDs = [asset.id]
            unvisited.remove(asset.id)

            let baseDate  = asset.creationDate ?? Date()
            let basePrint = featurePrints[asset.id]

            for candidate in sortedAssets {
                guard unvisited.contains(candidate.id) else { continue }

                let candDate = candidate.creationDate ?? Date()
                let timeDiff = abs(candDate.timeIntervalSince(baseDate))
                guard timeDiff <= timeWindow else { continue }

                var isSimilar = false
                if let fp1 = basePrint, let fp2 = featurePrints[candidate.id] {
                    // Real Vision similarity comparison
                    var distance: Float = 1.0
                    try? fp1.computeDistance(&distance, to: fp2)
                    isSimilar = distance < distanceThreshold
                } else {
                    // No feature print available: fallback to burst-only (< 5 seconds)
                    isSimilar = timeDiff < 5.0
                }

                if isSimilar {
                    clusterIDs.append(candidate.id)
                    unvisited.remove(candidate.id)
                }
            }

            // Only emit a cluster if 2+ similar photos were found
            if clusterIDs.count > 1 {
                let cluster = rankAndCreateCluster(
                    assetIDs: clusterIDs,
                    analyses: analyses,
                    assetMap: assetMap
                )
                clusters.append(cluster)
            }
        }

        return (clusters, analyses)
    }

    // MARK: - Cluster Ranking

    private func rankAndCreateCluster(
        assetIDs: [String],
        analyses: [String: PhotoAnalysis],
        assetMap: [String: PhotoAsset]
    ) -> PhotoCluster {
        // Sort descending by overall quality score
        let sortedByQuality = assetIDs.sorted { id1, id2 in
            (analyses[id1]?.overallQualityScore ?? 0.0) > (analyses[id2]?.overallQualityScore ?? 0.0)
        }

        let bestID        = sortedByQuality.first!
        let bestQuality   = analyses[bestID]?.overallQualityScore ?? 0.0
        let secondQuality = sortedByQuality.count > 1
            ? (analyses[sortedByQuality[1]]?.overallQualityScore ?? 0.0)
            : 0.0

        // Default: keep only the best shot
        var keepers = [bestID]

        // Special case: if #2 is a Live Photo companion within 2% quality, keep both
        if sortedByQuality.count > 1 {
            let secondID = sortedByQuality[1]
            let gap = bestQuality - secondQuality
            if gap < 0.02, let asset = assetMap[secondID], asset.isLivePhoto {
                keepers.append(secondID)
            }
        }

        let candidatesForRemoval = assetIDs.filter { !keepers.contains($0) }

        // Confidence is driven by quality gap: clear winner → high confidence recommendation
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
            similarityScore: Double(max(0.0, 1.0 - qualityGap))
        )
    }
}
