import Foundation

public struct TTMScript: Sendable {
    public struct Tag: Sendable {
        public let id: UInt16
        public let description: String
        
        public init(id: UInt16, description: String) {
            self.id = id
            self.description = description
        }
    }
    
    public let version: Data
    public let versionSize: UInt32
    public let numPages: UInt32
    public let pagUnknown: [UInt8]
    public let compression: CompressionMethod
    public let bytecode: Data
    public let ttiUnknown: [UInt8]
    public let tags: [Tag]
    
    public init(
        version: Data,
        versionSize: UInt32,
        numPages: UInt32,
        pagUnknown: [UInt8],
        compression: CompressionMethod,
        bytecode: Data,
        ttiUnknown: [UInt8],
        tags: [Tag]
    ) {
        self.version = version
        self.versionSize = versionSize
        self.numPages = numPages
        self.pagUnknown = pagUnknown
        self.compression = compression
        self.bytecode = bytecode
        self.ttiUnknown = ttiUnknown
        self.tags = tags
    }
}
