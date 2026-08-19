import XCTest
@testable import AlbumCuratorApp

final class RecommendationExplainerTests: XCTestCase {

    private func analysis(
        sharpness: Double = 0.8,
        exposure: Double = 0.8,
        noise: Double = 0.8,
        faceCount: Int = 0,
        eyesOpen: Double = 1.0,
        smile: Double = 0.5,
        composition: Double = 0.8
    ) -> PhotoAnalysis {
        PhotoAnalysis(
            assetID: UUID().uuidString,
            sharpnessScore: sharpness,
            exposureBalance: exposure,
            noiseScore: noise,
            faceCount: faceCount,
            eyesOpenRatio: eyesOpen,
            smileProminence: smile,
            compositionScore: composition
        )
    }

    func testKeeperReason_SharpnessIsDominantSignal() {
        let keeper = analysis(sharpness: 0.95)
        let other = analysis(sharpness: 0.5)

        XCTAssertEqual(RecommendationExplainer.keeperReason(keeper: keeper, weakestOther: other), "Sharpest in this group")
        XCTAssertEqual(RecommendationExplainer.removalReason(candidate: other, keeper: keeper), "Blurrier than the keeper")
    }

    func testRemovalReason_EyesClosed_OnlyConsideredWhenFacesPresent() {
        let keeper = analysis(sharpness: 0.8, faceCount: 1, eyesOpen: 1.0)
        let candidate = analysis(sharpness: 0.8, faceCount: 1, eyesOpen: 0.1)

        XCTAssertEqual(RecommendationExplainer.removalReason(candidate: candidate, keeper: keeper), "Eyes closed here")
    }

    func testReason_NoFaces_IgnoresEyeAndExpressionSignals() {
        // Even though eyesOpen/smile differ wildly, faceCount is 0 on both, so those
        // signals shouldn't be considered — sharpness (a real, small gap) should win
        // instead of a meaningless face signal on a photo with no detected face.
        let keeper = analysis(sharpness: 0.75, faceCount: 0, eyesOpen: 1.0, smile: 0.9)
        let candidate = analysis(sharpness: 0.6, faceCount: 0, eyesOpen: 0.0, smile: 0.0)

        XCTAssertEqual(RecommendationExplainer.removalReason(candidate: candidate, keeper: keeper), "Blurrier than the keeper")
    }

    func testReason_NearlyIdenticalSignals_FallsBackToTooClose() {
        let keeper = analysis(sharpness: 0.80, exposure: 0.80, noise: 0.80, composition: 0.80)
        let candidate = analysis(sharpness: 0.79, exposure: 0.81, noise: 0.79, composition: 0.80)

        XCTAssertEqual(RecommendationExplainer.keeperReason(keeper: keeper, weakestOther: candidate), "Marginally the best of very similar shots")
        XCTAssertEqual(RecommendationExplainer.removalReason(candidate: candidate, keeper: keeper), "Nearly identical to the keeper")
    }
}
