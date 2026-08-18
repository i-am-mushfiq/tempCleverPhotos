import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Color {
    public static var appSystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    public static var appSecondarySystemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    public static var appTertiarySystemFill: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemFill)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
    
    public static var appTertiaryLabel: Color {
        #if os(iOS)
        return Color(uiColor: .tertiaryLabel)
        #else
        return Color.secondary
        #endif
    }
}
