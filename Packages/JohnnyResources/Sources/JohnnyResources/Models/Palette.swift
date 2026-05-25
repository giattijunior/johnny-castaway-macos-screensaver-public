import Foundation

public struct Palette: Sendable {
    public struct RGB: Sendable {
        public let r: UInt8
        public let g: UInt8
        public let b: UInt8
        
        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r
            self.g = g
            self.b = b
        }
    }
    
    public let colors: [RGB]
    public let palSize: UInt16
    public let palUnknown: [UInt8]
    public let vgaHeaderBytes: [UInt8]
    
    public init(colors: [RGB], palSize: UInt16, palUnknown: [UInt8], vgaHeaderBytes: [UInt8]) {
        self.colors = colors
        self.palSize = palSize
        self.palUnknown = palUnknown
        self.vgaHeaderBytes = vgaHeaderBytes
    }
}
