import AppKit

/// Echte Katzenaufnahmen (CC0, „Cat Purr & Meow“ von Kerzoven, opengameart.org),
/// zugeschnitten und leise abgespielt.
@MainActor
enum Meow {
    enum Kind: String {
        /// Weiches Miau – die Pause beginnt
        case breakStarts = "miau-pause"
        /// Miau mit Schnurren – zurück an die Arbeit
        case backToWork = "miau-arbeit"
        /// Kurzes Miau – Zeit für eine Pause
        case reminder = "miau-erinnerung"
    }

    private static var sounds: [Kind: NSSound] = [:]

    static func play(_ kind: Kind) {
        let sound = sounds[kind] ?? load(kind)
        sound?.stop()
        sound?.play()
    }

    private static func load(_ kind: Kind) -> NSSound? {
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false)
        else { return nil }
        sound.volume = 0.4
        sounds[kind] = sound
        return sound
    }
}

/// Schnurren beim Streicheln: läuft in Schleife, blendet sanft ein und aus.
@MainActor
final class Purr {
    private var sound: NSSound?
    private var volume: Float = 0
    private static let fullVolume: Float = 0.45

    func update(dt: Double, active: Bool) {
        let target: Float = active ? Self.fullVolume : 0
        let step = Float(dt) * (active ? 0.9 : 0.6)
        volume = volume < target ? min(target, volume + step) : max(target, volume - step)

        if volume > 0 {
            if sound == nil, let url = Bundle.main.url(forResource: "schnurren", withExtension: "wav") {
                sound = NSSound(contentsOf: url, byReference: false)
                sound?.loops = true
            }
            sound?.volume = volume
            if sound?.isPlaying == false { sound?.play() }
        } else if sound?.isPlaying == true {
            sound?.stop()
        }
    }

    /// Sofort verstummen (z. B. wenn das Fenster zugeht)
    func stop() {
        volume = 0
        sound?.stop()
    }
}
