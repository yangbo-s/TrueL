import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Convert Apple's prerender without changing its mask, art, or white background.
// Runtime Dock images need the 824 / 1024 body-to-canvas ratio used by macOS.
enum IconError: Error { case invalid(String) }

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw IconError.invalid("Cannot read \(path)")
    }
    return image
}

func bitmap(width: Int, height: Int) throws -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconError.invalid("Cannot allocate image")
    }
    return context
}

func write(_ image: CGImage, _ path: String) throws {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                           UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.invalid("Cannot create \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.invalid("Cannot save \(path)") }
}

func prepare(_ source: String, _ dock: String, _ preview: String) throws {
    let image = try load(source)
    guard image.width == 412 && image.height == 412 else {
        throw IconError.invalid("Expected Apple's 412 × 412 prerender")
    }
    let previewContext = try bitmap(width: 412, height: 412)
    previewContext.draw(image, in: CGRect(x: 0, y: 0, width: 412, height: 412))
    try write(previewContext.makeImage()!, preview)
    let context = try bitmap(width: 512, height: 512)
    context.draw(image, in: CGRect(x: 50, y: 50, width: 412, height: 412))
    try write(context.makeImage()!, dock)
}

func validate(_ path: String) throws {
    let image = try load(path)
    guard image.width == 512 && image.height == 512 else {
        throw IconError.invalid("Expected 512 × 512 Dock image: \(path)")
    }
    let context = try bitmap(width: 512, height: 512)
    context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var opaque = 0, ink = 0, teal = 0, white = 0
    var minX = 512, minY = 512, maxX = -1, maxY = -1
    for y in 0..<512 {
        for x in 0..<512 {
            let i = (y * 512 + x) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2]), a = Int(pixels[i + 3])
            if a > 0 {
                guard x >= 50 && x < 462 && y >= 50 && y < 462 else {
                    throw IconError.invalid("Nontransparent Dock margin: \(path)")
                }
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
            if a > 250 {
                opaque += 1
                if r > 245 && g > 245 && b > 245 { white += 1 }
                if r < 40 && g < 40 && b < 40 { ink += 1 }
                if r < 60 && g > 100 && g < 200 && b > 90 && b < 180 { teal += 1 }
            }
        }
    }
    guard minX == 50 && maxX == 461 && minY == 50 && maxY == 461,
          opaque > 120_000, white > 50_000, ink > 1_000, teal > 1_000 else {
        throw IconError.invalid("Unexpected mask or palette in \(path): \(minX),\(minY)–\(maxX),\(maxY), white \(white), ink \(ink), teal \(teal)")
    }
    print("Validated \(URL(fileURLWithPath: path).lastPathComponent): 512 × 512, 50 px transparent margin, white / black / teal")
}

func sheet(_ folder: String, _ output: String) throws {
    let width = 1024, height = 370
    let context = try bitmap(width: width, height: height)
    context.setFillColor(CGColor(gray: 0.82, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium),
                                               .foregroundColor: NSColor(white: 0.15, alpha: 1)]
    for (index, name) in ["Default", "Dark", "TintedDark", "ClearLight"].enumerated() {
        let image = try load("\(folder)/\(name).png")
        let x = 24 + index * 250
        context.draw(image, in: CGRect(x: x, y: 116, width: 224, height: 224))
        (name as NSString).draw(at: NSPoint(x: x, y: 86), withAttributes: attrs)
    }
    let image = try load("\(folder)/Default.png")
    context.draw(image, in: CGRect(x: 24, y: 22, width: 32, height: 32))
    context.draw(image, in: CGRect(x: 76, y: 22, width: 16, height: 16))
    ("3A · native macOS renditions · 32 / 16 px" as NSString).draw(at: NSPoint(x: 120, y: 25), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    try write(context.makeImage()!, output)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "prepare" where args.count == 4: try prepare(args[1], args[2], args[3])
    case "validate" where args.count > 1: for path in args.dropFirst() { try validate(path) }
    case "sheet" where args.count == 3: try sheet(args[1], args[2])
    default: throw IconError.invalid("Usage: icon-assets prepare SOURCE DOCK PREVIEW | validate PNG... | sheet FOLDER OUTPUT")
    }
} catch {
    fputs("Icon assets: \(error)\n", stderr)
    exit(1)
}
