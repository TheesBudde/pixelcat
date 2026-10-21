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
