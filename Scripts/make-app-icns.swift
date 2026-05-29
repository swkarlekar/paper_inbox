import AppKit
import Foundation

struct IconImage {
    let type: String
    let pixels: Int
}

let images = [
    IconImage(type: "icp4", pixels: 16),
    IconImage(type: "ic11", pixels: 32),
    IconImage(type: "icp5", pixels: 32),
    IconImage(type: "ic12", pixels: 64),
    IconImage(type: "ic07", pixels: 128),
    IconImage(type: "ic13", pixels: 256),
    IconImage(type: "ic08", pixels: 256),
    IconImage(type: "ic14", pixels: 512),
    IconImage(type: "ic09", pixels: 512),
    IconImage(type: "ic10", pixels: 1024)
]

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-app-icns source.png output.icns\n".utf8))
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("could not read app icon source: \(sourceURL.path)\n".utf8))
    exit(66)
}

func appendFourCC(_ value: String, to data: inout Data) {
    precondition(value.utf8.count == 4)
    data.append(contentsOf: value.utf8)
}

func appendUInt32BE(_ value: Int, to data: inout Data) {
    var bigEndian = UInt32(value).bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

func pngData(for pixels: Int) throws -> Data {
    let size = NSSize(width: pixels, height: pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "PaperInboxIcon", code: 1)
    }

    bitmap.size = size

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PaperInboxIcon", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    sourceImage.draw(
        in: NSRect(origin: .zero, size: size),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PaperInboxIcon", code: 3)
    }

    return data
}

do {
    var chunks = Data()

    for image in images {
        let png = try pngData(for: image.pixels)
        appendFourCC(image.type, to: &chunks)
        appendUInt32BE(png.count + 8, to: &chunks)
        chunks.append(png)
    }

    var icns = Data()
    appendFourCC("icns", to: &icns)
    appendUInt32BE(chunks.count + 8, to: &icns)
    icns.append(chunks)

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try icns.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("could not create app icon: \(error.localizedDescription)\n".utf8))
    exit(70)
}
