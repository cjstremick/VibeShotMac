import AppKit

/// Pixel-backed rendering shared by clipboard, PNG, sharing, printing and crop.
/// Editor geometry is expressed in points with a top-left origin.
enum CompositeRenderer {
    enum RenderError: LocalizedError {
        case invalidImage, allocationFailed, encodingFailed
        var errorDescription: String? { "The screenshot could not be rendered." }
    }

    static func render(base: NSImage, elements: [any MarkupElement]) throws -> NSImage {
        guard let source = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              base.size.width > 0, base.size.height > 0 else { throw RenderError.invalidImage }
        guard let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.allocationFailed
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.scaleBy(x: CGFloat(source.width) / base.size.width,
                        y: CGFloat(source.height) / base.size.height)
        context.translateBy(x: 0, y: base.size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for element in elements.sorted(by: { $0.zOrder < $1.zOrder }) {
            element.draw(in: context, mode: .output)
        }
        guard let image = context.makeImage() else { throw RenderError.allocationFailed }
        return NSImage(cgImage: image, size: base.size)
    }

    static func crop(_ image: NSImage, topOriginRect rect: CGRect) throws -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.size.width > 0, image.size.height > 0 else { throw RenderError.invalidImage }
        let bounded = rect.intersection(CGRect(origin: .zero, size: image.size))
        guard !bounded.isEmpty else { throw RenderError.invalidImage }
        let scaleX = CGFloat(source.width) / image.size.width
        let scaleY = CGFloat(source.height) / image.size.height
        // CGImage crop rectangles address pixels from the top left.
        let pixels = CGRect(x: bounded.minX * scaleX, y: bounded.minY * scaleY,
                            width: bounded.width * scaleX, height: bounded.height * scaleY).integral
            .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let cropped = source.cropping(to: pixels) else { throw RenderError.invalidImage }
        return NSImage(cgImage: cropped, size: NSSize(width: pixels.width / scaleX, height: pixels.height / scaleY))
    }

    static func png(_ image: NSImage) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        return data
    }
}
