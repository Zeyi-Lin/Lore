import SwiftUI
import LoreAgentKit

extension LoreColorFamily {
    var localizedTitle: String {
        switch self {
        case .neutral: return T("Neutral")
        case .red: return T("Red")
        case .orange: return T("Orange")
        case .yellow: return T("Yellow")
        case .green: return T("Green")
        case .teal: return T("Teal")
        case .blue: return T("Blue")
        case .violet: return T("Violet")
        case .pink: return T("Pink")
        case .brown: return T("Brown")
        case .multicolor: return T("Multicolor")
        }
    }

    var swatchColor: Color {
        Color(hexString: swatchHex) ?? Theme.inkTertiary
    }
}

extension LoreColorTone {
    var localizedTitle: String {
        switch self {
        case .light: return T("Light")
        case .pastel: return T("Pastel")
        case .vivid: return T("Vivid")
        case .muted: return T("Muted")
        case .deep: return T("Deep")
        }
    }
}

/// A small circular hue swatch. Multicolor gets a rainbow ring instead of a
/// flat fill so it never reads as a specific hue.
struct ColorFamilySwatch: View {
    var family: LoreColorFamily
    var size: CGFloat = 11

    var body: some View {
        Group {
            if family == .multicolor {
                Circle()
                    .fill(AngularGradient(
                        colors: [
                            Color(hex: 0xE35D6A),
                            Color(hex: 0xE8A34A),
                            Color(hex: 0x7FA85B),
                            Color(hex: 0x4F9C9E),
                            Color(hex: 0x5B7CCB),
                            Color(hex: 0xB269C6),
                            Color(hex: 0xE35D6A)
                        ],
                        center: .center
                    ))
            } else {
                Circle().fill(family.swatchColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8))
    }
}
