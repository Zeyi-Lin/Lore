import Foundation
import CoreGraphics

// MARK: - Taxonomy

/// The hue family a pin reads as. Classification is intentionally broader
/// than a raw hue angle: designers search for "blue" or "warm neutral", not
/// for 212°. Families are multi-valued on a pin (a teal-and-yellow screen is
/// both), and `multicolor` is a filter-only pseudo family for pins with three
/// or more meaningful hues.
public enum LoraColorFamily: String, Codable, CaseIterable, Sendable {
    case neutral
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case violet
    case pink
    case brown
    case multicolor

    /// A representative swatch used by the app's filter chips. The value is
    /// presentational only; classification never uses it.
    public var swatchHex: String {
        switch self {
        case .neutral: return "#8A8178"
        case .red: return "#D93A4A"
        case .orange: return "#E0793C"
        case .yellow: return "#D9B33C"
        case .green: return "#4E9A63"
        case .teal: return "#2F9A9A"
        case .blue: return "#4A72D8"
        case .violet: return "#7C63C8"
        case .pink: return "#D45F9A"
        case .brown: return "#8B6547"
        case .multicolor: return "#B45FC4"
        }
    }

    /// Parses an API/query value, accepting common synonyms so an agent can
    /// ask for `cyan` or `grey` without knowing the canonical vocabulary.
    public static func parse(_ raw: String) -> LoraColorFamily? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = LoraColorFamily(rawValue: key) { return exact }
        switch key {
        case "grey", "gray", "mono", "monochrome", "monochromatic", "blackandwhite", "bw":
            return .neutral
        case "crimson", "scarlet":
            return .red
        case "amber", "apricot":
            return .orange
        case "gold", "lemon", "mustard":
            return .yellow
        case "emerald", "olive", "lime", "sage":
            return .green
        case "cyan", "turquoise", "mint", "aqua":
            return .teal
        case "azure", "navy", "cobalt":
            return .blue
        case "purple", "lavender", "lilac", "indigo":
            return .violet
        case "magenta", "fuchsia", "rose", "blush":
            return .pink
        case "tan", "taupe", "chocolate", "coffee", "earth", "earthy":
            return .brown
        case "multi", "rainbow", "colorful", "colourful":
            return .multicolor
        default:
            return nil
        }
    }
}

/// How a palette behaves tonally, independent of its hue. This is the second
/// axis of the taxonomy: "pastel blue" and "deep blue" are different references.
public enum LoraColorTone: String, Codable, CaseIterable, Sendable {
    case light
    case pastel
    case vivid
    case muted
    case deep

    public static func parse(_ raw: String) -> LoraColorTone? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = LoraColorTone(rawValue: key) { return exact }
        switch key {
        case "bright", "airy", "white":
            return .light
        case "soft", "powder", "candy":
            return .pastel
        case "saturated", "neon", "bold", "strong":
            return .vivid
        case "desaturated", "earth", "earthy", "morandi", "dusty":
            return .muted
        case "dark", "night", "black":
            return .deep
        default:
            return nil
        }
    }
}

// MARK: - Profile

/// The automatic colour fingerprint stored on a pin.
public struct LoraColorProfile: Equatable, Sendable {
    /// Meaningful hue families, ordered by coverage. Always at least one.
    public let families: [LoraColorFamily]
    public let tone: LoraColorTone
    /// Share of the image occupied by near-gray pixels (0...1).
    public let neutralShare: Double
    /// Mean OKLCH chroma of the chromatic pixels (0...~0.4).
    public let accentChroma: Double
    /// How dominant the leading family is, damped by how colourful the image is.
    public let confidence: Double

    public var family: LoraColorFamily { families.first ?? .neutral }

    /// Three or more named hues read as "colourful" rather than as one family.
    public var isMulticolor: Bool { family != .neutral && families.count >= 3 }

    public init(
        families: [LoraColorFamily],
        tone: LoraColorTone,
        neutralShare: Double = 0,
        accentChroma: Double = 0,
        confidence: Double = 1
    ) {
        var seen = Set<LoraColorFamily>()
        let cleaned = families.filter { $0 != .multicolor && seen.insert($0).inserted }
        self.families = cleaned.isEmpty ? [.neutral] : Array(cleaned.prefix(4))
        self.tone = tone
        self.neutralShare = min(max(neutralShare, 0), 1)
        self.accentChroma = max(accentChroma, 0)
        self.confidence = min(max(confidence, 0), 1)
    }

    /// `multicolor` is derived from the family list so the pseudo family never
    /// needs to be persisted.
    public func matches(family candidate: LoraColorFamily) -> Bool {
        if candidate == .multicolor { return isMulticolor }
        return families.contains(candidate)
    }

    public var filterKeys: [String] {
        var keys = families.map(\.rawValue)
        if isMulticolor { keys.append(LoraColorFamily.multicolor.rawValue) }
        return keys
    }
}

// MARK: - Analyzer

/// Deterministic OKLCH analysis for "what colour family is this reference?".
///
/// Pixels are converted to OKLCH, near-gray pixels are counted as neutral, and
/// the remaining pixels vote for a hue family by area. Areas are used rather
/// than saturation so a big teal panel beats a small bright button; saturation
/// is measured separately for the tonal axis. Both the image path and the
/// palette fallback (used by older libraries before their thumbnails are
/// re-analysed) share the same accumulator, so the vocabulary stays identical.
public enum LoraColorAnalyzer {
    /// OKLCH chroma below which a colour reads as gray/beige/white/black.
    public static let neutralChromaThreshold = 0.025

    /// A family must cover this share of the chromatic area to be listed.
    public static let familyShareThreshold = 0.15

    public static func classify(palette: [String]) -> LoraColorProfile {
        var accumulator = Accumulator()
        for (index, hex) in palette.prefix(6).enumerated() {
            guard let rgb = rgb(fromHex: hex) else { continue }
            // The palette is ranked by pixel coverage. A gentle decay stops a
            // saved "distinct" swatch from outweighing the dominant surface.
            let weight = pow(0.6, Double(index))
            accumulator.add(red: rgb.0, green: rgb.1, blue: rgb.2, weight: weight)
        }
        return accumulator.profile()
    }

    public static func classify(image: CGImage) -> LoraColorProfile {
        let longestSide = max(image.width, image.height)
        guard longestSide > 0 else { return Accumulator().profile() }
        let scale = min(1, 96.0 / Double(longestSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: info
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return Accumulator().profile() }

        var accumulator = Accumulator()
        var index = 0
        while index + 3 < bytes.count {
            let alpha = Int(bytes[index + 3])
            if alpha >= 32 {
                let alphaScale = Double(alpha) / 255
                var red = Double(bytes[index]) / 255
                var green = Double(bytes[index + 1]) / 255
                var blue = Double(bytes[index + 2]) / 255
                if alphaScale < 0.99 {
                    red = min(1, red / alphaScale)
                    green = min(1, green / alphaScale)
                    blue = min(1, blue / alphaScale)
                }
                accumulator.add(red: red, green: green, blue: blue, weight: 1)
            }
            index += 4
        }
        return accumulator.profile()
    }

    // MARK: Hue mapping

    static func family(hue: Double, lightness: Double, chroma: Double) -> LoraColorFamily {
        // Brown is a dark, low-chroma orange/yellow rather than its own hue
        // angle. Checking it first keeps warm earth tones out of orange/yellow.
        if hue >= 20, hue < 95, lightness < 0.62, chroma < 0.095 {
            return .brown
        }
        switch hue {
        case 0..<40: return .red
        case 40..<65: return .orange
        case 65..<105: return .yellow
        case 105..<165: return .green
        case 165..<215: return .teal
        case 215..<285: return .blue
        case 285..<320: return .violet
        case 320..<345: return .pink
        default: return .red
        }
    }

    static func tone(family: LoraColorFamily, meanLightness: Double, accentChroma: Double) -> LoraColorTone {
        if family == .neutral {
            if meanLightness >= 0.72 { return .light }
            if meanLightness <= 0.42 { return .deep }
            return .muted
        }
        if meanLightness <= 0.38 { return .deep }
        if accentChroma >= 0.11 { return .vivid }
        if accentChroma >= 0.07, meanLightness >= 0.78 { return .pastel }
        if accentChroma < 0.07 { return .muted }
        if meanLightness >= 0.78 { return .light }
        return .muted
    }

    // MARK: Colour science

    private static func linearize(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// sRGB (0...1) to OKLCH. Ottosson's OKLab matrices keep hue distances
    /// perceptually even, which is what makes the broad family buckets stable.
    static func oklch(red: Double, green: Double, blue: Double) -> (l: Double, c: Double, h: Double) {
        let r = linearize(red)
        let g = linearize(green)
        let b = linearize(blue)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = hypot(a, bb)
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (lightness, chroma, hue)
    }

    private static func rgb(fromHex hex: String) -> (Double, Double, Double)? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return (
            Double((number >> 16) & 0xFF) / 255,
            Double((number >> 8) & 0xFF) / 255,
            Double(number & 0xFF) / 255
        )
    }

    // MARK: Accumulation

    private struct Accumulator {
        var totalWeight = 0.0
        var lightnessWeighted = 0.0
        var neutralWeight = 0.0
        var chromaticWeight = 0.0
        var chromaWeighted = 0.0
        var familyWeights: [LoraColorFamily: Double] = [:]

        mutating func add(red: Double, green: Double, blue: Double, weight: Double) {
            let lab = LoraColorAnalyzer.oklch(red: red, green: green, blue: blue)
            totalWeight += weight
            lightnessWeighted += lab.l * weight
            if lab.c < LoraColorAnalyzer.neutralChromaThreshold {
                neutralWeight += weight
                return
            }
            chromaticWeight += weight
            chromaWeighted += lab.c * weight
            let family = LoraColorAnalyzer.family(hue: lab.h, lightness: lab.l, chroma: lab.c)
            familyWeights[family, default: 0] += weight
        }

        func profile() -> LoraColorProfile {
            guard totalWeight > 0 else {
                return LoraColorProfile(families: [.neutral], tone: .light, confidence: 0)
            }
            let meanLightness = lightnessWeighted / totalWeight
            let neutralShare = neutralWeight / totalWeight
            let chromaticShare = chromaticWeight / totalWeight
            let ranked = familyWeights
                .map { (family: $0.key, weight: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                    return lhs.family.rawValue < rhs.family.rawValue
                }
            let accentChroma = chromaticWeight > 0 ? chromaWeighted / chromaticWeight : 0

            guard chromaticShare >= 0.04, let leader = ranked.first else {
                let tone: LoraColorTone = meanLightness >= 0.72
                    ? .light
                    : (meanLightness <= 0.42 ? .deep : .muted)
                return LoraColorProfile(
                    families: [.neutral],
                    tone: tone,
                    neutralShare: neutralShare,
                    accentChroma: accentChroma,
                    confidence: 0
                )
            }

            var families = ranked
                .filter { $0.weight / chromaticWeight >= LoraColorAnalyzer.familyShareThreshold }
                .prefix(4)
                .map(\.family)
            if families.isEmpty { families = [leader.family] }

            let tone = LoraColorAnalyzer.tone(
                family: families[0],
                meanLightness: meanLightness,
                accentChroma: accentChroma
            )
            let topShare = leader.weight / chromaticWeight
            let confidence = topShare * min(1, chromaticShare / 0.3)
            return LoraColorProfile(
                families: families,
                tone: tone,
                neutralShare: neutralShare,
                accentChroma: accentChroma,
                confidence: confidence
            )
        }
    }
}
