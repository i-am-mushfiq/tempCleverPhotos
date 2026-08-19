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

// MARK: - Cancellation Support

/// Thread-safe holder for an in-flight PHImageRequestID so a cancellation
/// arriving on another thread can cancel the request once it's known.
private final class ImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var cancelledBeforeSet = false

    func set(_ id: PHImageRequestID) {
        lock.lock()
        defer { lock.unlock() }
        if cancelledBeforeSet {
            PHImageManager.default().cancelImageRequest(id)
        } else {
            requestID = id
        }
    }

    func cancelIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if let id = requestID {
            PHImageManager.default().cancelImageRequest(id)
        } else {
            cancelledBeforeSet = true
        }
    }
}

// MARK: - Connected-Components Clustering

/// Union-find (disjoint-set) over asset indices, with path compression and
/// union-by-rank, used to group photos transitively rather than greedily.
private final class UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(size: Int) {
        parent = Array(0..<size)
        rank = Array(repeating: 0, count: size)
    }

    func find(_ x: Int) -> Int {
        if parent[x] != x {
            parent[x] = find(parent[x])
        }
        return parent[x]
    }

    func union(_ x: Int, _ y: Int) {
        let rootX = find(x)
        let rootY = find(y)
        guard rootX != rootY else { return }

        if rank[rootX] < rank[rootY] {
            parent[rootX] = rootY
        } else if rank[rootX] > rank[rootY] {
            parent[rootY] = rootX
        } else {
            parent[rootY] = rootX
            rank[rootX] += 1
        }
    }
}

// MARK: - Engine

/// `@unchecked Sendable`: the engine holds no mutable state — every method builds its
/// own local Vision/CoreImage instances — so concurrent calls from multiple TaskGroup
/// children (see `analyzeAndCluster`'s Phase 1) are safe.
public final class VisionAnalysisEngine: VisionAnalysisEngineProtocol, @unchecked Sendable {

    private let currentVersion = "3.0.0"

    public init() {}

    // MARK: - Thumbnail Loading

    /// Loads a small CGImage thumbnail for Vision analysis via PHImageManager.
    /// Cancellation-aware: if the enclosing Task is cancelled while the request is
    /// in flight, the underlying PHImageManager request is cancelled too instead of
    /// running to completion in the background.
    private func loadThumbnail(for asset: PhotoAsset) async -> CGImage? {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil)
        guard let phAsset = results.firstObject else { return nil }

        let requestBox = ImageRequestBox()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat      // Fastest available quality
                options.isNetworkAccessAllowed = false   // On-device only
                options.isSynchronous = false
                options.resizeMode = .fast

                let id = PHImageManager.default().requestImage(
                    for: phAsset,
                    targetSize: CGSize(width: 224, height: 224),
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image?.cgImage)
                }
                requestBox.set(id)
            }
        }, onCancel: {
            requestBox.cancelIfNeeded()
        })
    }

    // MARK: - Vision Analysis

    private struct VisionSignals {
        let featurePrint: VNFeaturePrintObservation?
        let faceCount: Int
        let eyesOpenRatio: Double
        let smileProminence: Double
        let compositionScore: Double
    }

    /// Runs feature-print, face-landmarks, and saliency requests in a single handler pass
    /// (cheaper than separate VNImageRequestHandler instances per request).
    private func runVisionRequests(on cgImage: CGImage) -> VisionSignals {
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([featurePrintRequest, landmarksRequest, saliencyRequest])

        let featurePrint = featurePrintRequest.results?.first as? VNFeaturePrintObservation
        let faces = (landmarksRequest.results as? [VNFaceObservation]) ?? []
        let (eyesOpenRatio, smileProminence) = analyzeFaceExpressions(faces)
        let compositionScore = analyzeComposition(saliencyRequest.results?.first as? VNSaliencyImageObservation)

        return VisionSignals(
            featurePrint: featurePrint,
            faceCount: faces.count,
            eyesOpenRatio: eyesOpenRatio,
            smileProminence: smileProminence,
            compositionScore: compositionScore
        )
    }

    /// Averages per-face eye-openness and smile heuristics across all detected faces.
    /// Both are geometric proxies derived from landmark contours, not ML expression
    /// classifiers — Vision has no public API for either signal directly.
    private func analyzeFaceExpressions(_ faces: [VNFaceObservation]) -> (eyesOpenRatio: Double, smileProminence: Double) {
        guard !faces.isEmpty else { return (1.0, 0.5) }

        var eyeScores: [Double] = []
        var smileScores: [Double] = []

        for face in faces {
            guard let landmarks = face.landmarks else { continue }

            var faceEyeScores: [Double] = []
            if let leftEye = landmarks.leftEye { faceEyeScores.append(eyeOpennessScore(leftEye)) }
            if let rightEye = landmarks.rightEye { faceEyeScores.append(eyeOpennessScore(rightEye)) }
            if !faceEyeScores.isEmpty {
                eyeScores.append(faceEyeScores.reduce(0, +) / Double(faceEyeScores.count))
            }

            if let outerLips = landmarks.outerLips {
                smileScores.append(smileProminenceScore(outerLips))
            }
        }

        // Use the minimum eye-openness across faces/eyes: one closed eye in a group
        // shot should pull the score down, not get averaged away.
        let eyesOpenRatio = eyeScores.min() ?? 1.0
        let smileProminence = smileScores.isEmpty ? 0.5 : smileScores.reduce(0, +) / Double(smileScores.count)
        return (eyesOpenRatio, smileProminence)
    }

    /// Eye-aspect-ratio proxy from the eye contour's local bounding box.
    /// Empirically, Vision's open-eye contours have a height/width ratio around
    /// 0.35–0.5; closed/squinting eyes collapse toward 0.05–0.15.
    private func eyeOpennessScore(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard points.count >= 2 else { return 1.0 }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 1.0 }

        let width = maxX - minX
        guard width > 0.0001 else { return 1.0 }
        let aspectRatio = Double((maxY - minY) / width)

        let normalized = (aspectRatio - 0.05) / (0.35 - 0.05)
        return min(1.0, max(0.0, normalized))
    }

    /// Smile proxy: how far the mouth corners sit above the lip contour's mean
    /// height. Vision's coordinate space has origin at bottom-left, so a corner
    /// with a larger y than the contour average is lifted — the geometric signature
    /// of a smile. This is a heuristic, not a trained expression classifier.
    private func smileProminenceScore(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard points.count >= 4 else { return 0.5 }

        let sortedByX = points.sorted { $0.x < $1.x }
        guard let leftCorner = sortedByX.first, let rightCorner = sortedByX.last else { return 0.5 }

        let cornerAverageY = Double(leftCorner.y + rightCorner.y) / 2.0
        let centerY = Double(points.map { $0.y }.reduce(0, +)) / Double(points.count)
        let lift = cornerAverageY - centerY

        // Empirically, corner lift ranges roughly -0.02 (neutral/frown) to +0.03
        // (broad smile) in face-local normalized coordinates.
        let normalized = (lift + 0.02) / 0.05
        return min(1.0, max(0.0, normalized))
    }

    /// Rule-of-thirds proximity of the most confident salient subject.
    /// Falls back to a neutral-low score when no clear subject is detected
    /// (e.g. a flat-lay or landscape shot with no single focal point).
    private func analyzeComposition(_ saliency: VNSaliencyImageObservation?) -> Double {
        guard let salientObjects = saliency?.salientObjects, !salientObjects.isEmpty else {
            return 0.6
        }

        let primary = salientObjects.max(by: { $0.confidence < $1.confidence }) ?? salientObjects[0]
        let center = CGPoint(x: primary.boundingBox.midX, y: primary.boundingBox.midY)

        let thirdsIntersections: [CGPoint] = [
            CGPoint(x: 1.0 / 3, y: 1.0 / 3), CGPoint(x: 2.0 / 3, y: 1.0 / 3),
            CGPoint(x: 1.0 / 3, y: 2.0 / 3), CGPoint(x: 2.0 / 3, y: 2.0 / 3)
        ]
        let nearestDistance = thirdsIntersections
            .map { point -> Double in
                let dx = Double(point.x - center.x)
                let dy = Double(point.y - center.y)
                return (dx * dx + dy * dy).squareRoot()
            }
            .min() ?? 1.0

        // A subject exactly on an intersection scores 1.0; one dead-center (the
        // farthest any point can be from its nearest intersection, ~0.24) scores
        // lowest. Floored at 0.3 so one noisy saliency read doesn't tank the score.
        let normalized = 1.0 - min(1.0, nearestDistance / 0.4)
        return max(0.3, normalized)
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

    /// Noise proxy: how much luminance energy CINoiseReduction removes from the image.
    /// A clean, low-ISO photo loses very little to denoising; a grainy/high-ISO shot
    /// loses noticeably more. This is a residual-energy proxy, not a calibrated ISO/SNR measurement.
    private func computeNoise(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let denoiseFilter = CIFilter(name: "CINoiseReduction") else { return 0.9 }
        denoiseFilter.setValue(ciImage, forKey: kCIInputImageKey)
        denoiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
        denoiseFilter.setValue(0.4, forKey: "inputSharpness")
        guard let denoisedOutput = denoiseFilter.outputImage else { return 0.9 }

        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else { return 0.9 }
        diffFilter.setValue(ciImage, forKey: kCIInputImageKey)
        diffFilter.setValue(denoisedOutput, forKey: kCIInputBackgroundImageKey)
        guard let diffOutput = diffFilter.outputImage else { return 0.9 }

        let residualEnergy = averageLuminance(of: diffOutput, extent: ciImage.extent, context: context)
        // Empirically, clean photos lose <0.01 average luminance to denoising;
        // heavily noisy ones lose >0.08.
        return max(0.0, 1.0 - min(1.0, residualEnergy / 0.08))
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

    /// Computes one asset's full PhotoAnalysis. Safe to call concurrently: every call
    /// builds its own PHImageManager request, Vision handler, and CIContext, so there's
    /// no shared mutable state between concurrent invocations.
    private func computeAnalysis(for asset: PhotoAsset) async -> PhotoAnalysis {
        guard let cgImage = await loadThumbnail(for: asset) else {
            // Thumbnail unavailable (e.g. iCloud-only asset offline) — neutral scores.
            // Deliberately neutral (0.5) rather than optimistic, since nothing was
            // actually measured for this asset.
            return PhotoAnalysis(
                assetID: asset.id,
                featurePrintData: nil,
                sharpnessScore: 0.5,
                exposureBalance: 0.5,
                noiseScore: 0.5,
                faceCount: 0,
                eyesOpenRatio: 1.0,
                smileProminence: 0.5,
                compositionScore: 0.5,
                analysisVersion: currentVersion
            )
        }

        let signals   = runVisionRequests(on: cgImage)
        let sharpness = computeSharpness(cgImage: cgImage)
        let exposure  = computeExposure(cgImage: cgImage)
        let noise     = computeNoise(cgImage: cgImage)
        let fpData    = signals.featurePrint.flatMap { serializeFeaturePrint($0) }

        return PhotoAnalysis(
            assetID: asset.id,
            featurePrintData: fpData,
            sharpnessScore: sharpness,
            exposureBalance: exposure,
            noiseScore: noise,
            faceCount: signals.faceCount,
            eyesOpenRatio: signals.eyesOpenRatio,
            smileProminence: signals.smileProminence,
            compositionScore: signals.compositionScore,
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
        // Re-analyse only assets missing from cache or from an older version, running
        // up to `concurrencyLimit` at once via a TaskGroup worker pool instead of one
        // fully sequential await-per-photo loop — this is the difference between a
        // large album taking minutes vs. tens of seconds to scan.
        let assetsNeedingAnalysis = assets.filter { asset in
            analyses[asset.id].map { $0.analysisVersion != currentVersion } ?? true
        }
        var completedCount = total - assetsNeedingAnalysis.count
        if completedCount > 0 {
            progressHandler(completedCount, total, "Loaded \(completedCount) cached result(s)...")
        }

        if !assetsNeedingAnalysis.isEmpty {
            let concurrencyLimit = min(4, assetsNeedingAnalysis.count)

            await withTaskGroup(of: (String, PhotoAnalysis)?.self) { group in
                var nextIndex = 0

                func scheduleNext() {
                    guard !Task.isCancelled, nextIndex < assetsNeedingAnalysis.count else { return }
                    let asset = assetsNeedingAnalysis[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let analysis = await self.computeAnalysis(for: asset)
                        return (asset.id, analysis)
                    }
                }

                for _ in 0..<concurrencyLimit { scheduleNext() }

                while let result = await group.next() {
                    if let (assetID, analysis) = result {
                        analyses[assetID] = analysis
                        completedCount += 1
                        if completedCount % 5 == 0 || completedCount == total {
                            progressHandler(
                                completedCount, total,
                                "Analyzing photo quality & visual features (\(completedCount)/\(total))..."
                            )
                        }
                    }
                    if Task.isCancelled { break }
                    scheduleNext()
                }
            }
        }

        // Cancellation stops new work from being scheduled above (both the outer loop
        // and withTaskGroup's implicit cleanup cancel any still-running children), but
        // we still discard partial results here rather than caching a half-finished scan.
        if Task.isCancelled {
            return (clusters: [], updatedAnalyses: analyses)
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
        // Uses connected-components (union-find) over a similarity graph, rather than
        // greedily absorbing everything into whichever asset happens to be the next
        // unvisited anchor — two photos land in the same cluster if there's a chain of
        // pairwise-similar photos between them, which is order-independent and doesn't
        // depend on iteration order the way the old greedy-anchor approach did. The
        // trade-off is the classic "chaining" effect of single-linkage clustering: a
        // long burst can transitively merge photos at its two ends that aren't directly
        // similar to each other — acceptable here since chains are bounded by each mode's
        // time window, so it can only chain across one continuous burst/scene, not across
        // unrelated moments.
        //
        // sortedAssets is ascending by creationDate, so for anchor i we only need to scan
        // forward and can stop as soon as a candidate falls outside the time window (every
        // later candidate is even farther away) — this replaces an unconditional full
        // rescan of the whole array per anchor with a bounded forward scan.
        let sortedAssets = assets.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
        var assetMap: [String: PhotoAsset] = [:]
        for a in sortedAssets { assetMap[a.id] = a }

        let distanceThreshold = mode.featurePrintDistanceThreshold
        let timeWindow        = mode.maxTimeIntervalSeconds
        let unionFind = UnionFind(size: sortedAssets.count)

        for i in sortedAssets.indices {
            let asset = sortedAssets[i]
            let baseDate  = asset.creationDate ?? .distantPast
            let basePrint = featurePrints[asset.id]

            var j = i + 1
            while j < sortedAssets.count {
                let candidate = sortedAssets[j]
                let candDate = candidate.creationDate ?? .distantPast
                let timeDiff = candDate.timeIntervalSince(baseDate)
                guard timeDiff <= timeWindow else { break }

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
                    unionFind.union(i, j)
                }
                j += 1
            }
        }

        var groupedIndices: [Int: [Int]] = [:]
        for i in sortedAssets.indices {
            groupedIndices[unionFind.find(i), default: []].append(i)
        }

        var clusters: [PhotoCluster] = []
        for (_, indices) in groupedIndices where indices.count > 1 {
            let assetIDs = indices.map { sortedAssets[$0].id }
            let cluster = rankAndCreateCluster(
                assetIDs: assetIDs,
                analyses: analyses,
                assetMap: assetMap
            )
            clusters.append(cluster)
        }

        // Dictionary grouping doesn't preserve chronological order — restore it so the
        // step-by-step review UI walks through the album in the order the user shot it,
        // matching the old anchor-loop's naturally chronological emission order.
        clusters.sort { lhs, rhs in
            let lhsDate = lhs.assetIDs.compactMap { assetMap[$0]?.creationDate }.min() ?? .distantPast
            let rhsDate = rhs.assetIDs.compactMap { assetMap[$0]?.creationDate }.min() ?? .distantPast
            return lhsDate < rhsDate
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
