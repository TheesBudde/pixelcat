import AppKit

// Rendert Pixelbilder zur Sichtprüfung nach build/preview/ – Aufruf: ./preview.sh
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/preview"

    /// Mehrere Bilder nebeneinander auf grauem Grund
    @MainActor func sheet(_ name: String, _ items: [(Sprite, [Character: CGColor])], scale: CGFloat = 4) {
        let gap: CGFloat = 6
        let width = items.reduce(gap) { $0 + CGFloat($1.0.width) * scale + gap }
        let height = (items.map { CGFloat($0.0.height) }.max() ?? 1) * scale + 2 * gap
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.setFillColor(gray: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var x = gap
        for (sprite, colors) in items {
            sprite.draw(in: ctx, x: x / scale, y: gap / scale, scale: scale, colors: colors)
            x += CGFloat(sprite.width) * scale + gap
        }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }

    let bubbles = ["Pause", "Trinken", "Feierabend", "Mama anrufen", "Steuererklärung bis Freitag abgeben!",
                   "Größe: 1/2 – (ok?) & 100%", String(repeating: "Ganz langer Text ", count: 6)]
    for (i, text) in bubbles.enumerated() {
        sheet("blase-\(i)", [(BubbleFrames(text: text).whole, BubbleFrames.colors)])
    }
    sheet("schrift", ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "ÄÖÜ ß 0123456789", ".,!?:;-+'\"()/&%#@=*_…"]
        .map { (BubbleFrames(text: $0).whole, BubbleFrames.colors) })
    sheet("trinken", [(Frames.drinkA, Coat.orange.colors), (Frames.drinkB, Coat.orange.colors),
                      (Frames.drinkA, Coat.black.colors), (Frames.drinkA, Coat.gray.colors),
                      (Frames.waterFullA, PropColors.colors), (Frames.waterFullB, PropColors.colors),
                      (Frames.waterHalf, PropColors.colors), (Frames.waterEmpty, PropColors.colors)], scale: 6)
    sheet("fenster", [(LookoutArt.frames[0], LookoutArt.colors), (LookoutArt.frames[5], LookoutArt.colors),
                      (Frames.sitBackA, Coat.orange.colors), (Frames.sitBackB, Coat.black.colors),
                      (Frames.sitBackA, Coat.gray.colors)], scale: 6)
    // Katze auf dem Fensterbrett, wie es auf dem Bildschirm aussieht
    do {
        let scale: CGFloat = 6
        let w = CGFloat(LookoutArt.width) * scale, h = CGFloat(LookoutArt.height + 6) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 3 + 40), pixelsHigh: Int(h),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.setFillColor(gray: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w * 3 + 40, height: h))
        for (i, coat) in [Coat.orange, .black, .gray].enumerated() {
            let ox = CGFloat(i) * (w + 20) / scale
            LookoutArt.frames[3].draw(in: ctx, x: ox, y: 0, scale: scale, colors: LookoutArt.colors)
            let cat = i == 1 ? Frames.sitBackB : Frames.sitBackA
            cat.draw(in: ctx, x: ox + CGFloat(LookoutArt.width - cat.width) / 2, y: CGFloat(LookoutArt.sillTop),
                     scale: scale, colors: coat.colors)
        }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/fenster-katze.png"))
    }
    // Feierabend: Katze mit Schlafmütze (wie in CatView gezeichnet)
    do {
        let scale: CGFloat = 6
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(32 * scale * 3), pixelsHigh: Int(26 * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 32 * scale * 3, height: 26 * scale).fill()
        for (i, (coat, sprite)) in [(Coat.orange, Frames.sit), (.black, Frames.stand), (.gray, Frames.sitBackA)].enumerated() {
            let view = CatView(frame: NSRect(x: 0, y: 0, width: 32 * scale, height: 26 * scale))
            view.scale = scale
            view.coat = coat
            view.accessory = Frames.nightCap
            var look = CatLook(sprite: sprite, facingRight: true)
            if sprite === Frames.sitBackA { look.drawX = (32 - sprite.width) / 2 }
            view.look = look
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.translateBy(x: CGFloat(i) * 32 * scale, y: 0)
            view.draw(view.bounds)
            NSGraphicsContext.current?.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/feierabend.png"))
    }
    print("Vorschau in \(out)")
}
