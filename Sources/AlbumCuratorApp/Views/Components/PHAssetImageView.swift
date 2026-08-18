import SwiftUI
import Photos

public struct PHAssetImageView: View {
    public let localIdentifier: String?
    public let targetSize: CGSize
    public let contentMode: ContentMode

    @State private var image: UIImage? = nil

    public init(
        localIdentifier: String?,
        targetSize: CGSize = CGSize(width: 300, height: 300),
        contentMode: ContentMode = .fill
    ) {
        self.localIdentifier = localIdentifier
        self.targetSize = targetSize
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .task(id: localIdentifier) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let localIdentifier = localIdentifier, !localIdentifier.isEmpty else { return }
        
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let phAsset = results.firstObject else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: phAsset,
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: options
        ) { fetchedImage, _ in
            if let fetchedImage = fetchedImage {
                Task { @MainActor in
                    self.image = fetchedImage
                }
            }
        }
    }
}
