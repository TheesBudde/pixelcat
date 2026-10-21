import AppKit

/// Erzeugt PNG-Bilder: das App-Symbol (für build.sh) und eine Vorschau aller Posen.
enum Exporter {
    static func exportIconSet(to directory: String) throws {
        let dir = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for factor in [1, 2] {
                let suffix = factor == 2 ? "@2x" : ""
                let data = try png(width: base * factor, height: base * factor) { ctx in
                    drawIcon(in: ctx, size: CGFloat(base * factor))
                }
                try data.write(to: dir.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
            }
        }
    }

    /// Alle Posen in einer Fellfarbe (7 pro Zeile), darunter Napf und Wollknäuel.
    static func exportPreview(to path: String, coat: Coat) throws {
        let scale: CGFloat = 6
        let cell = 28
        let columns = 7
        let frames = Frames.all
        let rows = (frames.count + columns - 1) / columns + 1
        let width = columns * cell * Int(scale)
        let height = rows * cell * Int(scale)
        let data = try png(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (i, sprite) in frames.enumerated() {
                let x = CGFloat((i % columns) * cell + 2)
                let y = CGFloat((rows - 1 - i / columns) * cell + 2)
                sprite.draw(in: ctx, x: x, y: y, scale: scale, colors: coat.colors)
            }
            let props = [Frames.bowlFull, Frames.bowlHalf, Frames.bowlEmpty, Frames.yarnA, Frames.yarnB]
            for (i, sprite) in props.enumerated() {
                sprite.draw(in: ctx, x: CGFloat(i * cell + 2), y: 2, scale: scale, colors: PropColors.colors)
            }
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    private static func drawIcon(in ctx: CGContext, size: CGFloat) {
        // Abgerundetes Quadrat im Stil der macOS-Symbole
        let inset = size * 0.1
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225,
                          cornerHeight: rect.width * 0.225, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let colors = [CGColor(srgbRed: 0.55, green: 0.78, blue: 0.95, alpha: 1),
                      CGColor(srgbRed: 0.85, green: 0.93, blue: 1.0, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY),
                                   end: CGPoint(x: 0, y: rect.maxY), options: [])
        }
        // Boden, auf dem die Katze sitzt
        let groundHeight = rect.height * 0.26
        ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.36, blue: 0.52, alpha: 1))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: groundHeight))

        let sprite = Frames.sit
        var scale = rect.width * 0.62 / CGFloat(sprite.width)
        if scale >= 2 { scale = scale.rounded(.down) }
        let originX = (size - CGFloat(sprite.width) * scale) / 2 / scale
        let originY = (rect.minY + groundHeight) / scale
        sprite.draw(in: ctx, x: originX, y: originY, scale: scale, colors: Coat.black.colors)
    }

    private static func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        // Damit NSImage-Zeichnungen (Menüleisten-Symbol) in diesen Kontext gehen
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
