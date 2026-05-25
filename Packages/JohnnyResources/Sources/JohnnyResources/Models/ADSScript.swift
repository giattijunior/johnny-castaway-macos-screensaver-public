import Foundation

public struct ADSScript: Sendable {
    public struct ResourceReference: Sendable {
        public let id: UInt16
        public let name: String
        
        public init(id: UInt16, name: String) {
            self.id = id
            self.name = name
        }
    }
    
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
    public let adsUnknown: [UInt8]
    public let resSize: UInt32
    public let referencedResources: [ResourceReference]
    public let compression: CompressionMethod
    public let bytecode: Data
    public let tags: [Tag]
    
    public init(
        version: Data,
        versionSize: UInt32,
        adsUnknown: [UInt8],
        resSize: UInt32,
        referencedResources: [ResourceReference],
        compression: CompressionMethod,
        bytecode: Data,
        tags: [Tag]
    ) {
        self.version = version
        self.versionSize = versionSize
        self.adsUnknown = adsUnknown
        self.resSize = resSize
        self.referencedResources = referencedResources
        self.compression = compression
        self.bytecode = bytecode
        self.tags = tags
    }
}
