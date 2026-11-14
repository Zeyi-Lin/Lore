import Testing
import Foundation
import ImageIO
@testable import LoreAgentKit

@Suite
struct AnimationTests {

    @Test func detectsAnimatedGIF() throws {
        let data = Fixture.makeAnimatedGIF()
        let animation = try #require(LoreImageAnalyzer.animation(data: data))
        #expect(animation.isAnimated)
        #expect(animation.isGIF)
        #expect(animation.frameCount == 2)
        #expect(abs(animation.duration - 0.2) < 0.05)
    }

    @Test func stillImageIsNotAnimated() throws {
        let animation = try #require(LoreImageAnalyzer.animation(data: Fixture.pngData))
        #expect(!animation.isAnimated)
        #expect(!animation.isGIF)
        #expect(animation.frameCount == 1)
        #expect(animation.duration == 0)
    }

    @Test func stillPNGSourceIsNotAnimated() throws {
        let source = try #require(CGImageSourceCreateWithData(Fixture.makePNG() as CFData, nil))
        let animation = LoreImageAnalyzer.animation(source: source)
        #expect(!animation.isAnimated)
        #expect(animation.frameCount == 1)
    }
}
