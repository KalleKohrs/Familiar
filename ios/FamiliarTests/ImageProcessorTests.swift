import FamiliarCore
import Testing
import UIKit
@testable import Familiar

struct ImageProcessorTests {
    /// Ein 12-Megapixel-Foto im Querformat mit etwas Struktur (einfarbig würde sich zu stark komprimieren).
    private func photo(width: Int = 4000, height: Int = 3000) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            for index in 0..<200 {
                UIColor(hue: CGFloat(index % 20) / 20, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: (index * 97) % width, y: (index * 61) % height, width: 400, height: 300))
            }
        }
    }

    @Test func taskImageIsDownscaledForUpload() async throws {
        let prepared = try #require(await ImageProcessor.taskImage(from: photo()))
        #expect(max(prepared.width, prepared.height) == 1600)
        #expect(prepared.width > prepared.height)
        // Deutlich unter dem, was ein Handyfoto sonst wiegt.
        #expect(prepared.jpegData.count < 600_000)
        let thumbnail = try #require(UIImage(data: prepared.thumbnailData))
        #expect(max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale <= 480)
        #expect(prepared.thumbnailData.count < 80_000)
    }

    @Test func smallPhotosAreNotEnlarged() async throws {
        let prepared = try #require(await ImageProcessor.taskImage(from: photo(width: 800, height: 600)))
        #expect(max(prepared.width, prepared.height) <= 800)
    }
}
