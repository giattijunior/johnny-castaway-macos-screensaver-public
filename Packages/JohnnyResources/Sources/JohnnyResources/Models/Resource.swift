import Foundation

public enum Resource: Sendable {
    case palette(Palette)
    case screen(Screen)
    case bitmap(Bitmap)
    case ttmScript(TTMScript)
    case adsScript(ADSScript)
    case unrecognised(extension: String, rawData: Data)
    
    public var kind: ResourceKind {
        switch self {
        case .palette: return .palette
        case .screen: return .screen
        case .bitmap: return .bitmap
        case .ttmScript: return .ttmScript
        case .adsScript: return .adsScript
        case .unrecognised: return .unrecognised
        }
    }
}
