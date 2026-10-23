import AppKit
import SwiftUI

/// Pixelbilder für die Fenster (Einstellungen, Aufgaben, Einrichtung): die Katze als Bild, Pfotenabdrücke
/// und ein ruhiger, leicht durchscheinender Pixel-Hintergrund.

extension Sprite {
    /// Als Bild mit scharfen Pixeln (scale = Punkte pro Pixel)
    func nsImage(colors: [Character: CGColor], scale: CGFloat) -> NSImage {
        let size = NSSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)
            self.draw(in: ctx, x: 0, y: 0, scale: scale, colors: colors)
            return true
        }
    }
}

/// Ein Pixelbild in SwiftUI
struct PixelSprite: View {
    let sprite: Sprite
    var colors: [Character: CGColor]
    var scale: CGFloat = 4
    var mirrored = false

    var body: some View {
        Image(nsImage: sprite.nsImage(colors: colors, scale: scale))
            .interpolation(.none)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }
}

/// Die Katze in ihrem Fell, je nach Pose blinzelnd, atmend (schläft) oder laufend
struct PixelCat: View {
    enum Pose { case sit, sleep, walk, stand, petted }

    var coat: Coat
    var pose: Pose = .sit
    var scale: CGFloat = 5
    var mirrored = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5)
            PixelSprite(sprite: sprite(tick: tick), colors: coat.colors, scale: scale, mirrored: mirrored)
        }
    }

    private func sprite(tick: Int) -> Sprite {
        switch pose {
        case .sit: return tick % 9 == 0 ? Frames.sit.withClosedEyes : Frames.sit
        case .sleep: return tick % 4 < 2 ? Frames.sleepA : Frames.sleepB
        case .walk: return tick % 2 == 0 ? Frames.walkA : Frames.walkB
        case .stand: return Frames.stand
        case .petted: return Frames.petStandTall
        }
    }
}

enum PixelArt {
    /// Pfotenabdruck
    static let paw = Sprite([
        ".K.K.",
        "K...K",
        ".KKK.",
        ".KKK.",
    ])
    /// Kleiner Fisch
    static let fish = Sprite([
        "..KKK..K",
        ".KKKKKKK",
        "KKKKKK.K",
        ".KKKKKKK",
        "..KKK..K",
    ])
    /// Herz
    static let heart = Sprite([
        ".KK.KK.",
        "KKKKKKK",
        "KKKKKKK",
        ".KKKKK.",
        "..KKK..",
        "...K...",
    ])
}

/// Ruhiger Hintergrund: sanfter Verlauf und ein paar blasse Pfoten, Fische und Herzen
struct PixelBackdrop: View {
    var opacity: Double = 0.07

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.clear, Color.orange.opacity(0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, size in
                    let ink = NSColor.labelColor.cgColor
                    let colors: [Character: CGColor] = ["K": ink]
                    // Feste, locker verteilte Stellen: ein Muster, das sich wiederholt
                    let spots: [(x: Double, y: Double, art: Int, turn: Double)] = [
                        (0.08, 0.10, 0, -0.3), (0.22, 0.04, 0, 0.2), (0.85, 0.08, 1, 0), (0.62, 0.18, 0, 0.4),
                        (0.93, 0.30, 2, 0), (0.12, 0.38, 1, 0), (0.40, 0.30, 0, -0.2), (0.75, 0.46, 0, 0.3),
                        (0.30, 0.55, 2, 0), (0.05, 0.66, 0, 0.1), (0.55, 0.64, 1, 0), (0.88, 0.70, 0, -0.4),
                        (0.20, 0.82, 0, 0.3), (0.68, 0.86, 2, 0), (0.45, 0.94, 0, -0.1), (0.95, 0.95, 1, 0),
                    ]
                    let arts = [PixelArt.paw, PixelArt.fish, PixelArt.heart]
                    let tile = max(size.height, 600.0)
                    var top = 0.0
                    while top < size.height {
                        for spot in spots {
                            let sprite = arts[spot.art]
                            let point = CGPoint(x: spot.x * size.width, y: top + spot.y * tile)
                            context.drawLayer { layer in
                                layer.translateBy(x: point.x, y: point.y)
                                layer.rotate(by: .radians(spot.turn))
                                let image = sprite.nsImage(colors: colors, scale: 3)
                                layer.draw(Image(nsImage: image).interpolation(.none), at: .zero)
                            }
                        }
                        top += tile
                    }
                }
                .opacity(opacity)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
