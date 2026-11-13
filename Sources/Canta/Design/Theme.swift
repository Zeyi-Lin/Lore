import SwiftUI
import AppKit

// Canta's visual language: Pinterest-derived confidence (paper white, signature
// red, rounded image-first cards) warmed up with an editorial, library-like calm.
enum Theme {
    // Canvas
    static let paper = Color(hex: 0xFFFFFF)
    static let parchment = Color(hex: 0xFAF8F5)
    static let parchmentDeep = Color(hex: 0xF3EFE9)
    static let ink = Color(hex: 0x171412)
    static let inkSecondary = Color(hex: 0x615C56)
    static let inkTertiary = Color(hex: 0x989087)
    static let hairline = Color(hex: 0xE9E4DC)
    static let cardBorder = Color(hex: 0xEDE8E0)

    // Signature
    static let red = Color(hex: 0xE60023)
    static let redDeep = Color(hex: 0xB8001C)
    static let redWash = Color(hex: 0xFCE9EC)
    static let moss = Color(hex: 0x2D6A4F)
    static let mossWash = Color(hex: 0xE8F2EC)
    static let amber = Color(hex: 0xB7791F)

    // Corners
    static let cardRadius: CGFloat = 18
    static let panelRadius: CGFloat = 26
    static let modalRadius: CGFloat = 30
    static let pillRadius: CGFloat = 999

    // Type
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let boardColors: [String: Color] = [
        "Web dashboards": Color(hex: 0x4569D4),
        "Mobile flows": Color(hex: 0xB7791F),
        "Landing pages": Color(hex: 0xC14B63),
        "Editorial": Color(hex: 0x6B5B95),
        "Unsorted": Color(hex: 0x8A8178)
    ]

    static func boardColor(_ name: String) -> Color {
        if let exact = boardColors[name] { return exact }
        let palette: [UInt32] = [0x4569D4, 0xB7791F, 0xC14B63, 0x6B5B95, 0x2D6A4F, 0x9B6A43]
        var hash: UInt32 = 2_166_136_261
        for scalar in name.unicodeScalars {
            hash = (hash ^ scalar.value) &* 16_777_619
        }
        return Color(hex: palette[Int(hash % UInt32(palette.count))])
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}

extension Date {
    var cantaShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }

    var cantaRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var cantaTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · HH:mm"
        return formatter.string(from: self)
    }
}

// MARK: - Reusable surfaces

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct HoverLift: ViewModifier {
    @State private var hovering = false
    var lift: CGFloat = 3
    var shadow: Double = 0.10

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.008 : 1)
            .shadow(color: .black.opacity(hovering ? shadow : 0.04), radius: hovering ? 22 : 6, x: 0, y: hovering ? 12 : 2)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: hovering)
            .onHover { value in hovering = value }
    }
}

struct Hairline: View {
    var color: Color = Theme.hairline
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var foreground: Color = Theme.ink
    var background: Color = Color.black.opacity(0.045)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(background))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func cantaCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}
