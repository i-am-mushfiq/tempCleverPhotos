import SwiftUI

public struct ConfidenceBadge: View {
    public let confidence: ClusterConfidence
    
    public init(confidence: ClusterConfidence) {
        self.confidence = confidence
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.bold())
            Text(confidence.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .foregroundColor(badgeColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch confidence {
        case .high: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.shield.fill"
        case .low: return "questionmark.circle.fill"
        }
    }
    
    private var badgeColor: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .gray
        }
    }
}
