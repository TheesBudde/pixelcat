import AppKit
import AVFoundation

// Werbeclip für Instagram (9:16, 30 s): rendert jede Szene mit den echten Pixelbildern der App und schreibt ein
// H.264-Video. Die Musik kommt aus music.py und wird in promo.sh dazugemischt.
// Aufruf: build/promo-bin <video.mov> <screenshot-ordner>

let width = 1080, height = 1920, fps = 30, seconds = 30
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let shots = CommandLine.arguments[2]

// MARK: Hilfen

func ease(_ t: Double) -> Double { t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t) }
func progress(_ t: Double, _ start: Double, _ length: Double) -> Double { ease((t - start) / length) }
func cg(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

/// Zentrierter Text (y = Unterkante des Textblocks)
func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, centerX: CGFloat, y: CGFloat,
          alpha: CGFloat = 1, width: CGFloat = 960) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: roundedFont(size, weight),
        .foregroundColor: NSColor(cgColor: color)!.withAlphaComponent(alpha),
        .paragraphStyle: style,
    ]
    let string = NSAttributedString(string: string, attributes: attributes)
    let bounds = string.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    string.draw(with: NSRect(x: centerX - width / 2, y: y, width: width, height: ceil(bounds.height)),
                options: [.usesLineFragmentOrigin])
}

/// Ein Pixelbild mit linker unterer Ecke bei (x, y), auf Wunsch gespiegelt
func sprite(_ ctx: CGContext, _ sprite: Sprite, colors: [Character: CGColor], x: CGFloat, y: CGFloat, scale: CGFloat,
            mirrored: Bool = false, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: x, y: y)
    if mirrored {
        ctx.translateBy(x: CGFloat(sprite.width) * scale, y: 0)
        ctx.scaleBy(x: -1, y: 1)
    }
    sprite.draw(in: ctx, x: 0, y: 0, scale: scale, colors: colors)
    ctx.restoreGState()
}

func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

/// Mauszeiger von macOS (Spitze bei x, y)
func cursor(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat = 1.6) {
    let points: [(CGFloat, CGFloat)] = [(0, 0), (0, -21), (5, -16), (9, -25), (12, -24), (8, -15), (15, -15)]
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x, y: y))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: x + point.0 * size, y: y + point.1 * size)) }
    path.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: cg(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(cg(0x000000))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(cg(0xFFFFFF))
    ctx.setLineWidth(2.4)
    ctx.strokePath()
}

func loadImage(_ name: String) -> CGImage? {
    NSImage(contentsOfFile: shots + "/" + name)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Ein Fenster-Screenshot mit runden Ecken und Schatten, von unten hereingleitend
func window(_ ctx: CGContext, _ image: CGImage, crop: CGRect? = nil, centerX: CGFloat, top: CGFloat, width: CGFloat,
            appear: Double, zoom: CGFloat = 1) {
    let source = crop.flatMap { image.cropping(to: $0) } ?? image
    let w = width * zoom
    let h = w * CGFloat(source.height) / CGFloat(source.width)
    let rect = CGRect(x: centerX - w / 2, y: top - h - CGFloat(1 - appear) * 260, width: w, height: h)
    ctx.saveGState()
    ctx.setAlpha(CGFloat(appear))
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: cg(0x2B1D16, 0.35))
    roundedRect(ctx, rect, radius: 22, fill: cg(0xFFFFFF))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(CGFloat(appear))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(source, in: rect)
    ctx.restoreGState()
}

// MARK: Bühne

let ink = cg(0x2B1D16)
let coat = Coat.orange.colors
let screen = CGRect(x: 40, y: 560, width: 1000, height: 650)   // der Mac-Bildschirm
let dockTop = screen.minY + 96
let catScale: CGFloat = 8

/// Hintergrund: warmer Verlauf mit blassen Pfoten
func background(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(0xFFF1E3), cg(0xFFD9C7)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: 0, y: 0), options: [])
    let paw = PixelArt.paw
    for (index, spot) in [(120, 1780), (930, 1700), (80, 1330), (990, 1270), (150, 420), (900, 380), (520, 230),
                          (300, 1860), (760, 1880), (40, 900), (1030, 860)].enumerated() {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(spot.0), y: CGFloat(spot.1))
        ctx.rotate(by: CGFloat(index % 3) * 0.35 - 0.3)
        sprite(ctx, paw, colors: ["K": cg(0xC96F2E)], x: 0, y: 0, scale: 7, alpha: 0.12)
        ctx.restoreGState()
    }
}

/// Der Mac: Rahmen, Hintergrundbild, Menüleiste mit dem Katzensymbol, Dock
func mac(_ ctx: CGContext, t: Double) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 46, color: cg(0x2B1D16, 0.35))
    roundedRect(ctx, screen.insetBy(dx: -14, dy: -14), radius: 34, fill: cg(0x1F1D24))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.clip()
    let wallpaper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [cg(0x3A4FCF), cg(0x8E5BE0), cg(0xF06BB0)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(wallpaper, start: CGPoint(x: screen.minX, y: screen.maxY),
                           end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    // Menüleiste
    let bar = CGRect(x: screen.minX, y: screen.maxY - 34, width: screen.width, height: 34)
    ctx.setFillColor(cg(0xFFFFFF, 0.28))
    ctx.fill(bar)
    if let icon = Frames.menuBarIcon().cgImage(forProposedRect: nil, context: nil, hints: nil) {
        // Vorlagenbild: als weiße Silhouette zeichnen
        let rect = CGRect(x: screen.maxX - 150, y: bar.minY + 6, width: 28, height: 22)
        ctx.saveGState()
        ctx.clip(to: rect, mask: icon)
        ctx.setFillColor(cg(0xFFFFFF))
        ctx.fill(rect)
        ctx.restoreGState()
    }
    text("9:41", size: 21, weight: .semibold, color: cg(0xFFFFFF), centerX: screen.maxX - 60, y: bar.minY + 4, width: 100)
    for (index, word) in ["", "Finder", "Ablage", "Bearbeiten"].enumerated() where index > 0 {
        text(word, size: 19, weight: index == 1 ? .bold : .regular, color: cg(0xFFFFFF), centerX: screen.minX + 40 + CGFloat(index) * 110,
             y: bar.minY + 6, width: 140)
    }
    // Dock mit bunten Symbolen
    let dock = CGRect(x: screen.midX - 330, y: screen.minY + 14, width: 660, height: 82)
    roundedRect(ctx, dock, radius: 24, fill: cg(0xFFFFFF, 0.32))
    let colors: [UInt32] = [0x2F80ED, 0x27AE60, 0xF2994A, 0xEB5757, 0x9B51E0, 0x56CCF2, 0xF2C94C, 0x6FCF97, 0x333A45]
    for (index, color) in colors.enumerated() {
        let rect = CGRect(x: dock.minX + 18 + CGFloat(index) * 70, y: dock.minY + 12, width: 58, height: 58)
        roundedRect(ctx, rect, radius: 14, fill: cg(color))
        roundedRect(ctx, rect.insetBy(dx: 16, dy: 16), radius: 6, fill: cg(0xFFFFFF, 0.55))
    }
    ctx.restoreGState()
}

/// Die Katze auf dem Dock: x ist die Mitte, steht auf der Dock-Oberkante
func cat(_ ctx: CGContext, _ pose: Sprite, centerX: CGFloat, mirrored: Bool = false, lift: CGFloat = 0, scale: CGFloat = catScale) {
    // Nur innerhalb des Bildschirms (beim Hereinlaufen nicht über den Rahmen)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.clip()
    sprite(ctx, pose, colors: coat, x: centerX - CGFloat(pose.width) * scale / 2, y: dockTop + lift, scale: scale, mirrored: mirrored)
    ctx.restoreGState()
}

/// Leiste unten: alle Funktionen als Kapseln, die gerade gezeigte leuchtet
func features(_ ctx: CGContext, active: Int, alpha: CGFloat = 1) {
    let names = ["Auf dem Dock", "Pausen", "Trinken & Augen", "Tag planen", "Statistik"]
    let font = roundedFont(27, .bold)
    let widths = names.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width + 40 }
    let rows = [[0, 1, 2], [3, 4]]
    for (rowIndex, row) in rows.enumerated() {
        let total = row.map { widths[$0] }.reduce(0, +) + CGFloat(row.count - 1) * 14
        var x = 540 - total / 2
        let y: CGFloat = 470 - CGFloat(rowIndex) * 72
        for index in row {
            let on = index == active
            let rect = CGRect(x: x, y: y, width: widths[index], height: 56)
            roundedRect(ctx, rect, radius: 28, fill: on ? cg(0xC96F2E, alpha) : cg(0xFFFFFF, 0.55 * alpha))
            text(names[index], size: 27, weight: .bold, color: on ? cg(0xFFFFFF) : cg(0x8A6650), centerX: rect.midX, y: y + 11,
                 alpha: alpha, width: widths[index])
            x += widths[index] + 14
        }
    }
}

/// Gedankenblase über der Katze (Punkte zeigen auf den Kopf bei x, y)
func bubble(_ ctx: CGContext, _ text: String, choices: Bool = false, x: CGFloat, y: CGFloat, scale: CGFloat = 4.5,
            appear: Double = 1) -> CGRect {
    let frames = BubbleFrames(text: text, choices: choices)
    let pop = appear < 1 ? 0.6 + 0.4 * appear + 0.12 * sin(appear * .pi) : 1
    let s = scale * CGFloat(pop)
    let rect = CGRect(x: x - CGFloat(frames.width) * s / 2, y: y, width: CGFloat(frames.width) * s, height: CGFloat(frames.height) * s)
    sprite(ctx, frames.whole, colors: BubbleFrames.colors, x: rect.minX, y: rect.minY, scale: s, alpha: CGFloat(min(1, appear * 2)))
    return rect
}

/// Kopf der Katze (für die Blase): Mitte über den Ohren
func head(_ pose: Sprite, centerX: CGFloat, mirrored: Bool = false, lift: CGFloat = 0) -> CGPoint {
    let ears = pose.earAnchor?.center ?? pose.width / 2
    let column = mirrored ? pose.width - ears : ears
    return CGPoint(x: centerX - CGFloat(pose.width) * catScale / 2 + CGFloat(column) * catScale,
                   y: dockTop + lift + CGFloat(pose.height) * catScale + 10)
}

func heart(_ ctx: CGContext, x: CGFloat, y: CGFloat, t: Double, scale: CGFloat = 6) {
    sprite(ctx, PixelArt.heart, colors: ["K": cg(0xFF4D7A)], x: x, y: y + CGFloat(sin(t * 5) * 8), scale: scale)
}

/// Überschrift oben und Unterzeile, mit sanftem Einblenden (in: Sekunden seit Szenenbeginn)
func headline(_ title: String, _ subtitle: String?, local: Double, length: Double) {
    let fadeIn = progress(local, 0, 0.35), fadeOut = 1 - progress(local, length - 0.3, 0.3)
    let alpha = CGFloat(min(fadeIn, fadeOut))
    let rise = CGFloat(1 - fadeIn) * 30
    text(title, size: 74, weight: .heavy, color: ink, centerX: 540, y: 1430 - rise, alpha: alpha)
    if let subtitle {
        let subAlpha = CGFloat(min(progress(local, 0.25, 0.35), fadeOut))
        text(subtitle, size: 40, weight: .medium, color: cg(0x6B4A35), centerX: 540, y: 1360 - rise, alpha: subAlpha)
    }
}

// MARK: Szenen

let timeboxing = loadImage("timeboxing-hell.png")
let statistics = loadImage("statistik-letzte-orange.png")

func frame(_ ctx: CGContext, t: Double) {
    background(ctx)
    scene(ctx, t: t)
    // Welche Funktion gerade zu sehen ist (nicht im Titel und im Abspann), über allem
    if t >= 4, t < 26 {
        let active = t < 8 ? 0 : t < 14 ? 1 : t < 18 ? 2 : t < 22 ? 3 : 4
        features(ctx, active: active, alpha: CGFloat(progress(t, 4, 0.4) * (1 - progress(t, 25.7, 0.3))))
    }
}

func scene(_ ctx: CGContext, t: Double) {
    switch t {
    case ..<4:  // Titel: Sie läuft über das Dock
        mac(ctx, t: t)
        let walk = progress(t, 0.3, 2.6)
        let x = screen.minX - 60 + CGFloat(walk) * (screen.width / 2 + 60)
        if t < 2.9 {
            cat(ctx, Int(t / 0.14) % 2 == 0 ? Frames.walkA : Frames.walkB, centerX: x)
        } else {
            cat(ctx, t.truncatingRemainder(dividingBy: 1.3) < 0.12 ? Frames.sit.withClosedEyes : Frames.sit, centerX: x)
        }
        let alpha = CGFloat(progress(t, 0.2, 0.5) * (1 - progress(t, 3.7, 0.3)))
        let pop = 1 + 0.08 * sin(progress(t, 0.2, 0.5) * .pi)
        text("Pixelcat", size: 120 * pop, weight: .heavy, color: ink, centerX: 540, y: 1400, alpha: alpha)
        text("Eine Pixelkatze für deinen Mac", size: 42, weight: .medium, color: cg(0x6B4A35), centerX: 540, y: 1330,
             alpha: CGFloat(progress(t, 0.6, 0.5) * (1 - progress(t, 3.7, 0.3))))
    case ..<8:  // Sie schläft, wird gestreichelt und freut sich
        let local = t - 4
        mac(ctx, t: t)
        let x = screen.midX
        let petted = local > 2.0
        let pose = petted ? Frames.petStandTall : (Int(local / 0.9) % 2 == 0 ? Frames.sleepA : Frames.sleepB)
        cat(ctx, pose, centerX: x)
        if !petted {
            // Zzz
            for i in 0..<2 {
                let phase = (local * 0.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                text("z", size: 34 + CGFloat(i) * 8, weight: .heavy, color: cg(0xFFFFFF, 0.9), centerX: x + 90 + CGFloat(phase) * 40,
                     y: dockTop + 90 + CGFloat(phase) * 70, alpha: CGFloat(1 - phase), width: 80)
            }
        } else {
            heart(ctx, x: x - 20, y: dockTop + CGFloat(Frames.petStandTall.height) * catScale + 20, t: local)
        }
        // Der Mauszeiger streicht über sie
        let stroke = progress(local, 1.0, 1.0)
        let cx = x + 160 - CGFloat(stroke) * 200 + (local > 2 ? CGFloat(sin(local * 7) * 50) : 0)
        cursor(ctx, x: cx, y: dockTop + 130 + CGFloat(sin(local * 3) * 10))
        headline("Sie wohnt auf deinem Dock", local < 2 ? "und macht Nickerchen" : "und schnurrt beim Streicheln",
                 local: local, length: 4)
    case ..<14:  // Pausenfrage, Daumen hoch, Übungen
        let local = t - 8
        mac(ctx, t: t)
        let x = screen.midX
        if local < 2.4 {
            let pose = local > 1.9 ? Frames.petStandTall : Frames.sit
            cat(ctx, pose, centerX: x)
            let top = head(Frames.sit, centerX: x)
            let rect = bubble(ctx, "Pause?", choices: true, x: top.x, y: top.y, appear: progress(local, 0.3, 0.4))
            // Mauszeiger zum Daumen hoch, Klick
            let move = progress(local, 0.9, 0.8)
            let target = CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.33)
            let start = CGPoint(x: screen.maxX - 120, y: screen.minY + 200)
            let press: CGFloat = local > 1.75 && local < 1.95 ? 0.9 : 1
            cursor(ctx, x: start.x + (target.x - start.x) * CGFloat(move), y: start.y + (target.y - start.y) * CGFloat(move), size: 1.6 * press)
        } else {
            let exercise = local - 2.4
            let first = exercise < 1.8
            let up = Int(exercise / 0.6) % 2 == 0
            let pose = first ? (up ? Frames.exerciseUp : Frames.stand) : (up ? Frames.exerciseArch : Frames.stand)
            cat(ctx, pose, centerX: x)
            let top = head(Frames.stand, centerX: x)
            _ = bubble(ctx, first ? "Streck die Arme hoch!" : "Mach einen Katzenbuckel!", x: top.x, y: top.y + 40,
                       appear: progress(exercise.truncatingRemainder(dividingBy: 1.8), 0, 0.3))
        }
        headline("Sie erinnert dich an Pausen", "mit kleinen Übungen zum Mitmachen", local: local, length: 6)
    case ..<18:  // Trinken und Augenpause
        let local = t - 14
        mac(ctx, t: t)
        if local < 2 {
            let bowlX = screen.midX + 40
            sprite(ctx, local.truncatingRemainder(dividingBy: 0.5) < 0.25 ? Frames.waterFullA : Frames.waterFullB,
                   colors: PropColors.colors, x: bowlX - 48, y: dockTop, scale: catScale)
            let pose = Int(local / 0.25) % 2 == 0 ? Frames.drinkA : Frames.drinkB
            cat(ctx, pose, centerX: bowlX - 150)
            _ = bubble(ctx, "Trinken", x: bowlX - 110, y: dockTop + 170, appear: progress(local, 0.1, 0.35))
        } else {
            let pop = progress(local, 2.0, 0.4)
            let frames = LookoutArt.frames
            let window = frames[Int(local / 0.5) % frames.count]
            let s = catScale * CGFloat(0.7 + 0.3 * pop)
            let wx = screen.midX - CGFloat(LookoutArt.width) * s / 2
            sprite(ctx, window, colors: LookoutArt.colors, x: wx, y: dockTop, scale: s, alpha: CGFloat(pop))
            if local > 2.5 {
                let back = local.truncatingRemainder(dividingBy: 2) > 1.6 ? Frames.sitBackB : Frames.sitBackA
                cat(ctx, back, centerX: screen.midX, lift: CGFloat(LookoutArt.sillTop) * catScale)
            }
        }
        headline(local < 2 ? "Trinken nicht vergessen" : "Augenpause", local < 2 ? "Sie stellt dir einen Napf hin" : "Schau mit ihr in die Ferne",
                 local: local.truncatingRemainder(dividingBy: 2), length: 2)
    case ..<22:  // Tagesplanung
        let local = t - 18
        if let timeboxing {
            window(ctx, timeboxing, centerX: 540, top: 1290, width: 790, appear: progress(local, 0, 0.5),
                   zoom: 1 + CGFloat(local) * 0.012)
        }
        headline("Sie plant deinen Tag mit dir", "To-dos, Timeboxing, drei Ziele", local: local, length: 4)
    case ..<26:  // Statistik
        let local = t - 22
        if let statistics {
            window(ctx, statistics, crop: CGRect(x: 0, y: 0, width: 640, height: 600), centerX: 540, top: 1290, width: 770,
                   appear: progress(local, 0, 0.5), zoom: 1 + CGFloat(local) * 0.012)
        }
        headline("Sie zeigt dir deine Woche", "Pausen, Fokus, Stimmung. Alles bleibt auf deinem Mac", local: local, length: 4)
    default:  // Abspann: im Korb
        let local = t - 26
        mac(ctx, t: t)
        let art = BasketArt.shared
        let s: CGFloat = 8
        let bx = screen.midX - CGFloat(art.width) * s / 2
        sprite(ctx, art.back, colors: BasketArt.colors, x: bx, y: dockTop - 8, scale: s)
        let sleeping = Int(local / 0.9) % 2 == 0 ? Frames.sleepA : Frames.sleepB
        sprite(ctx, sleeping, colors: coat, x: screen.midX - CGFloat(sleeping.width) * s / 2, y: dockTop - 8 + CGFloat(art.catY) * s, scale: s)
        sprite(ctx, art.front, colors: BasketArt.colors, x: bx, y: dockTop - 8, scale: s)
        heart(ctx, x: screen.midX - 21, y: dockTop + 250, t: local, scale: 7)
        let alpha = CGFloat(progress(local, 0, 0.4))
        text("Pixelcat", size: 120, weight: .heavy, color: ink, centerX: 540, y: 1400, alpha: alpha)
        text("Kostenlos für macOS", size: 46, weight: .bold, color: cg(0xC96F2E), centerX: 540, y: 1325,
             alpha: CGFloat(progress(local, 0.3, 0.4)))
        let link = CGFloat(progress(local, 0.6, 0.4))
        roundedRect(ctx, CGRect(x: 170, y: 410, width: 740, height: 84), radius: 42, fill: cg(0x2B1D16, 0.92 * link))
        text("github.com/TheesBudde/pixelcat", size: 36, weight: .semibold, color: cg(0xFFFFFF), centerX: 540, y: 432,
             alpha: link)
    }
}

// MARK: Video schreiben

MainActor.assumeIsolated {
    _ = NSApplication.shared
    try? FileManager.default.removeItem(at: output)
    let writer = try! AVAssetWriter(outputURL: output, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    guard writer.status == .writing else {
        print("Videoschreiber startet nicht:", writer.status.rawValue, String(describing: writer.error))
        exit(1)
    }
    writer.startSession(atSourceTime: .zero)
    for index in 0..<(fps * seconds) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool else { print("kein Pufferpool"); exit(1) }
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { fatalError("kein Puffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setShouldAntialias(true)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        frame(ctx, t: Double(index) / Double(fps))
        NSGraphicsContext.current = nil
        // Ein paar Standbilder zur Kontrolle
        if index % 60 == 30, let image = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: output.deletingLastPathComponent()
                .appendingPathComponent("frame-\(index / 30).png"))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    print(writer.status == .completed ? "✓ Video: \(output.path)" : "Fehler: \(String(describing: writer.error))")

    // Musik dazu: Video und WAV zusammenführen, als MP4 mit AAC-Ton (Instagram)
    guard CommandLine.arguments.count >= 5 else { return }
    let music = URL(fileURLWithPath: CommandLine.arguments[3])
    let final = URL(fileURLWithPath: CommandLine.arguments[4])
    try? FileManager.default.removeItem(at: final)
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: output), audioAsset = AVURLAsset(url: music)
    let range = CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue(seconds), timescale: 1))
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try! videoTrack.insertTimeRange(range, of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
    try! audioTrack.insertTimeRange(range, of: audioAsset.tracks(withMediaType: .audio)[0], at: .zero)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    export.outputURL = final
    export.outputFileType = .mp4
    let exported = DispatchSemaphore(value: 0)
    export.exportAsynchronously { exported.signal() }
    exported.wait()
    print(export.status == .completed ? "✓ Mit Musik: \(final.path)" : "Fehler beim Zusammenführen: \(String(describing: export.error))")
}
