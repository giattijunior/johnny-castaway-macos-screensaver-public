import Foundation

public struct Screen: Sendable {
    public let totalSize: UInt16
    public let flags: UInt16
    public let dimSize: UInt32
    public let width: UInt16
    public let height: UInt16
    public let compression: CompressionMethod
    public let pixels: Data
    
    public init(
        totalSize: UInt16,
        flags: UInt16,
        dimSize: UInt32,
        width: UInt16,
        height: UInt16,
        compression: CompressionMethod,
        pixels: Data
    ) {
        self.totalSize = totalSize
        self.flags = flags
        self.dimSize = dimSize
        self.width = width
        self.height = height
        self.compression = compression
        self.pixels = pixels
    }
}
