import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import LoraAgentKit

@Suite
struct ColorFamilyTests {

    @Test func pureBlueReadsAsVividBlue() {
        let profile = LoraColorAnalyzer.classify(palette: ["#2563EB", "#FFFFFF"])
        #expect(profile.family == .blue)
        #expect(profile.tone == .vivid)
        #expect(profile.families == [.blue])
        #expect(profile.isMulticolor == false)
    }

    @Test func nearNeutralPaletteIsNeutralAndLight() {
        let profile = LoraColorAnalyzer.classify(palette: ["#FFFFFF", "#F2F2F2", "#111111"])
        #expect(profile.families == [.neutral])
        #expect(profile.tone == .light)
        #expect(profile.neutralShare > 0.5)
    }

    @Test func darkForestGreenIsDeep() {
        let profile = LoraColorAnalyzer.classify(palette: ["#0E2A1B", "#1E4D33"])
        #expect(profile.family == .green)
        #expect(profile.tone == .deep)
    }

    @Test func tealAndYellowKeepBothFamilies() {
        let profile = LoraColorAnalyzer.classify(palette: ["#0F6B6B", "#F2C94C", "#FAF8F5"])
        #expect(profile.family == .teal)
        #expect(profile.families.contains(.yellow))
        #expect(profile.isMulticolor == false)
        #expect(profile.matches(family: .teal))
        #expect(profile.matches(family: .yellow))
        #expect(profile.matches(family: .red) == false)
    }

    @Test func threeEvenHuesBecomeMulticolor() {
        let profile = LoraColorAnalyzer.classify(palette: ["#2563EB", "#E5484D", "#2F9E44"])
        #expect(profile.families.count == 3)
        #expect(profile.isMulticolor)
        #expect(profile.matches(family: .multicolor))
    }

    @Test func warmLowChromaReadsAsBrown() {
        let profile = LoraColorAnalyzer.classify(palette: ["#6B4A2F"])
        #expect(profile.family == .brown)
    }

    @Test func invalidPaletteFallsBackToNeutral() {
        let profile = LoraColorAnalyzer.classify(palette: ["not-a-color", "#GGGGGG"])
        #expect(profile.families == [.neutral])
        #expect(profile.confidence == 0)
    }

    @Test func imageClassificationWeightsArea() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 80,
            height: 80,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // 75% forest green, 25% white.
        context.setFillColor(CGColor(red: 0.12, green: 0.30, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 60, y: 0, width: 20, height: 80))
        let image = try #require(context.makeImage())

        let profile = LoraColorAnalyzer.classify(image: image)
        #expect(profile.family == .green)
        #expect(profile.neutralShare > 0.15)
        #expect(profile.confidence > 0.5)
    }

    @Test func seedReferencesAllClassify() throws {
        let seed = TestPaths.packageRoot
            .appendingPathComponent("Sources/Lora/Resources/Seed/Images", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: seed, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }
        #expect(!files.isEmpty)
        for file in files {
            let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let profile = LoraColorAnalyzer.classify(image: image)
            #expect(!profile.families.isEmpty)
            #expect(profile.families.allSatisfy { $0 != .multicolor })
        }
    }
}
