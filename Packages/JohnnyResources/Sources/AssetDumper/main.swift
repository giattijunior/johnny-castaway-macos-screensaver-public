import Foundation
import ImageIO
import UniformTypeIdentifiers
import JohnnyResources

@main
struct AssetDumper {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("Usage: swift run asset-dumper <source-folder-with-resources> <output-folder>")
            exit(1)
        }
        
        let sourcePath = args[1]
        let outputPath = args[2]
        
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let outputURL = URL(fileURLWithPath: outputPath)
        
        let mapURL = sourceURL.appendingPathComponent("RESOURCE.MAP")
        let containerURL = sourceURL.appendingPathComponent("RESOURCE.001")
        
        print("==> Loading resources from \(sourceURL.path)...")
        
        guard FileManager.default.fileExists(atPath: mapURL.path),
              FileManager.default.fileExists(atPath: containerURL.path) else {
            print("Error: RESOURCE.MAP or RESOURCE.001 not found at \(sourceURL.path)")
            exit(1)
        }
        
        do {
            let mapData = try Data(contentsOf: mapURL)
            let containerData = try Data(contentsOf: containerURL)
            let archive = try ResourceArchive.parse(map: mapData, container: containerData)
            print("==> Parse complete. Found \(archive.entries.count) entries.")
            
            // Find default palette
            let palettes = archive.entries(of: .palette)
            guard let firstPal = palettes.first,
                  case .palette(let palette) = firstPal.resource else {
                print("Error: No palette found in resources.")
                exit(1)
            }
            print("==> Using palette: \(firstPal.name)")
            
            let fm = FileManager.default
            try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)
            
            let screensURL = outputURL.appendingPathComponent("screens")
            let spritesURL = outputURL.appendingPathComponent("sprites")
            try fm.createDirectory(at: screensURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: spritesURL, withIntermediateDirectories: true)
            
            for entry in archive.entries {
                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                
                switch entry.resource {
                case .screen(let scr):
                    print("  Exporting screen: \(name)...")
                    let img = scr.rasterize(palette: palette)
                    let fileURL = screensURL.appendingPathComponent("\(name).png")
                    try writePNG(img, to: fileURL)
                    
                case .bitmap(let bmp):
                    print("  Exporting bitmap: \(name) (\(bmp.imageCount) frames)...")
                    let spriteDir = spritesURL.appendingPathComponent(name)
                    try fm.createDirectory(at: spriteDir, withIntermediateDirectories: true)
                    for i in 0 ..< bmp.imageCount {
                        let img = bmp.rasterize(sprite: i, palette: palette)
                        let fileURL = spriteDir.appendingPathComponent("frame_\(i).png")
                        try writePNG(img, to: fileURL)
                    }
                default:
                    break
                }
            }
            
            print("==> Done! All screens and sprites exported to \(outputURL.path)")
            
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func writePNG(_ image: RGBAImage, to url: URL) throws {
        let bytesPerRow = image.width * 4
        guard let provider = CGDataProvider(data: image.pixels as CFData) else {
            throw NSError(domain: "AssetDumper", code: 1, userInfo: [NSLocalizedDescriptionKey: "CGDataProvider init failed"])
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw NSError(domain: "AssetDumper", code: 2, userInfo: [NSLocalizedDescriptionKey: "CGImage init failed"])
        }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "AssetDumper", code: 3, userInfo: [NSLocalizedDescriptionKey: "CGImageDestination init failed"])
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "AssetDumper", code: 4, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed"])
        }
    }
}
