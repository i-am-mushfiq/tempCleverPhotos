import SwiftUI

public struct PhotoThumbnailView: View {
    public let asset: PhotoAsset
    public let isKeeper: Bool
    public let isSelectedForRemoval: Bool
    public let onTap: () -> Void
    public let onLongPress: (() -> Void)?

    public init(
        asset: PhotoAsset,
        isKeeper: Bool,
        isSelectedForRemoval: Bool,
        onTap: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil
    ) {
        self.asset = asset
        self.isKeeper = isKeeper
        self.isSelectedForRemoval = isSelectedForRemoval
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    public var body: some View {
        // Plain tap + long-press gestures rather than wrapping this in a Button:
        // a Button's own tap action can still fire right after a long-press release,
        // which would toggle the keeper state at the same moment the zoom preview
        // opens. Plain gestures on a non-Button view disambiguate correctly instead.
        ZStack(alignment: .topTrailing) {
            // Photo Placeholder representation
            ZStack(alignment: .bottomLeading) {
                PHAssetImageView(
                    localIdentifier: asset.localIdentifier,
                    targetSize: CGSize(width: 400, height: 400),
                    contentMode: .fill
                )
                .aspectRatio(asset.aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isKeeper ? Color.blue : (isSelectedForRemoval ? Color.red : Color.gray.opacity(0.3)), lineWidth: isKeeper || isSelectedForRemoval ? 3 : 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    if let label = asset.customLabel {
                        Text(label)
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    if asset.isLivePhoto {
                        HStack(spacing: 2) {
                            Image(systemName: "livephoto")
                                .font(.caption2)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
                .padding(6)
            }

            // Status Overlay Badges
            HStack(spacing: 4) {
                if isKeeper {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption.bold())
                        Text("BEST SHOT")
                            .font(.system(size: 10, weight: .black))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(radius: 2)
                } else if isSelectedForRemoval {
                    HStack(spacing: 2) {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption.bold())
                        Text("REMOVE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            onLongPress?()
        }
        .accessibilityLabel(asset.customLabel ?? "Photo \(asset.id.prefix(6))")
        .accessibilityHint(isKeeper ? "Recommended best shot to keep in album" : (isSelectedForRemoval ? "Selected for removal from album" : "Tap to toggle selection. Touch and hold to preview full screen."))
    }
}
