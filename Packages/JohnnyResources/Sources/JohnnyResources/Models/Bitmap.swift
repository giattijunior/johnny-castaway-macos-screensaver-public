import Foundation

public struct Bitmap: Sendable {
    public let bbWidth: UInt16
    public let bbHeight: UInt16
    public let dataSize: UInt32
    public let widths: [UInt16]
    public let heights: [UInt16]
    public let compression: CompressionMethod
    public let pixels: Data
    
    public init(
        bbWidth: UInt16,
        bbHeight: UInt16,
        dataSize: UInt32,
        widths: [UInt16],
        heights: [UInt16],
        compression: CompressionMethod,
        pixels: Data
    ) {
        self.bbWidth = bbWidth
        self.bbHeight = bbHeight
        self.dataSize = dataSize
        self.widths = widths
        self.heights = heights
        self.compression = compression
        self.pixels = pixels
    }
    
    public var imageCount: Int {
        return widths.count
    }
    
    public var totalSpritePixelBytes: Int {
        var sum = 0
        for i in 0 ..< widths.count {
            sum += Int(widths[i]) * Int(heights[i])
        }
        return sum
    }
    
    public func pixels(forSprite index: Int) -> Data {
        var offset = 0
        for i in 0 ..< index {
            offset += Int(widths[i]) * Int(heights[i])
        }
        let length = Int(widths[index]) * Int(heights[index])
        return pixels.subdata(in: offset ..< (offset + length))
    }
}
