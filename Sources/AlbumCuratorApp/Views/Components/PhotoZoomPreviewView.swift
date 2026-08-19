import SwiftUI

/// Full-screen, pinch-to-zoom photo viewer. Lets a user swipe through a set of assets
/// (e.g. everything in a cluster, or every photo about to be removed) and inspect each
/// one at full size — a thumbnail grid alone isn't enough to judge which of several
/// near-identical burst shots is actually sharper.
public struct PhotoZoomPreviewView: View {
    public let assetIDs: [String]
    public let assetMap: [String: PhotoAsset]

    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    public init(assetIDs: [String], assetMap: [String: PhotoAsset], initialAssetID: String) {
        self.assetIDs = assetIDs
        self.assetMap = assetMap
        self._currentIndex = State(initialValue: assetIDs.firstIndex(of: initialAssetID) ?? 0)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(assetIDs.enumerated()), id: \.offset) { index, assetID in
                    ZoomableAssetImage(localIdentifier: assetMap[assetID]?.localIdentifier ?? assetID)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }

                    Spacer()

                    if assetIDs.count > 1 {
                        Text("\(currentIndex + 1) of \(assetIDs.count)")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Balances the close button so the counter stays visually centered.
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding()

                Spacer()

                Text("Pinch or double-tap to zoom")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 12)
            }
        }
    }
}

/// A single pinch/double-tap-zoomable photo, loaded at a large target size for
/// inspecting detail that a thumbnail can't show.
private struct ZoomableAssetImage: View {
    let localIdentifier: String

    @State private var scale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0

    var body: some View {
        PHAssetImageView(
            localIdentifier: localIdentifier,
            targetSize: CGSize(width: 1600, height: 1600),
            contentMode: .fit
        )
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = committedScale * value
                }
                .onEnded { _ in
                    committedScale = min(max(scale, 1.0), 5.0)
                    withAnimation(.spring(response: 0.3)) {
                        scale = committedScale
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3)) {
                committedScale = committedScale > 1.0 ? 1.0 : 2.5
                scale = committedScale
            }
        }
    }
}
