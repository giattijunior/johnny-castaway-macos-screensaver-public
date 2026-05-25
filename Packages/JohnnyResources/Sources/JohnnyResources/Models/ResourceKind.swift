import Foundation

public enum ResourceKind: String, Sendable, CaseIterable {
    case palette
    case screen
    case bitmap
    case ttmScript
    case adsScript
    case unrecognised
    
    public static func fromExtension(_ ext: String) -> ResourceKind? {
        let needle = ext.uppercased()
        switch needle {
        case ".PAL": return .palette
        case ".SCR": return .screen
        case ".BMP": return .bitmap
        case ".TTM": return .ttmScript
        case ".ADS": return .adsScript
        default: return nil
        }
    }
}
