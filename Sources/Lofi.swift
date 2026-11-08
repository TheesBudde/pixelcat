import Foundation

// MARK: - Akkorde

/// Ein Akkord aus der Auswahl im Beat-Baukasten. Gespeichert wird nur der Name.
struct LofiChord: Codable, Hashable {
    let name: String
    /// MIDI-Töne (60 = mittleres C)
    let notes: [Int]

    /// Weiche Septakkorde, wie man sie aus Lo-Fi kennt
    static let palette: [LofiChord] = [
        LofiChord(name: "Cmaj7", notes: [48, 52, 55, 59]),
        LofiChord(name: "Dm7", notes: [50, 53, 57, 60]),
        LofiChord(name: "Em7", notes: [52, 55, 59, 62]),
        LofiChord(name: "Fmaj7", notes: [53, 57, 60, 64]),
        LofiChord(name: "G7", notes: [43, 47, 50, 53]),
        LofiChord(name: "Am7", notes: [45, 48, 52, 55]),
        LofiChord(name: "Bbmaj7", notes: [46, 50, 53, 57]),
        LofiChord(name: "Ebmaj7", notes: [51, 55, 58, 62]),
        LofiChord(name: "Abmaj7", notes: [44, 48, 51, 55]),
        LofiChord(name: "Gm7", notes: [43, 46, 50, 53]),
        LofiChord(name: "Cm7", notes: [48, 51, 55, 58]),
        LofiChord(name: "Fm7", notes: [41, 44, 48, 51]),
        LofiChord(name: "E7", notes: [40, 44, 47, 50]),
        LofiChord(name: "A7", notes: [45, 49, 52, 55]),
    ]

    static func named(_ name: String) -> LofiChord? { palette.first { $0.name == name } }

    init(name: String, notes: [Int]) {
        self.name = name
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        self = Self.named(name) ?? Self.palette[0]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

// MARK: - Beat

/// Ein selbst gebauter Lo-Fi-Beat: ein Takt Schlagzeug im 16er-Raster, vier Akkorde (einer pro Takt), Tempo, Swing,
/// Wärme und Knistern. Daraus wird ein Loop von vier Takten gerechnet.
struct LofiBeat: Codable, Equatable, Identifiable {
    enum Instrument: String, Codable, CaseIterable {
        case kick, snare, hat
    }

    /// Was zu einem Zeitpunkt im Loop erklingt
    enum Voice: Equatable {
        case kick, snare, hat, chord
    }

    struct Event: Equatable {
        var instrument: Voice
        /// Sekunden ab Taktanfang
        var time: Double
        var chord: LofiChord?
    }

    static let stepsPerBar = 16
    static let barsPerLoop = 4
    static let tempoRange = 60...100

    var id: UUID
    var name: String
    var bpm: Int
    /// 0 = gerade, 0,6 = stark geshuffelt
    var swing: Double
    var kick: [Bool]
    var snare: [Bool]
    var hat: [Bool]
    var chords: [LofiChord]
    /// Lautstärke von Akkorden und Bass (0…1)
    var chordVolume: Double
    /// 0 = klar, 1 = sehr dumpf und warm
    var warmth: Double
    /// Plattenknistern (0…1)
    var crackle: Double

    var barSeconds: Double { 60.0 / Double(bpm) * 4 }
    var stepSeconds: Double { barSeconds / Double(Self.stepsPerBar) }
    var loopSeconds: Double { barSeconds * Double(Self.barsPerLoop) }

    func steps(for instrument: Instrument) -> [Bool] {
        switch instrument {
        case .kick: return kick
        case .snare: return snare
        case .hat: return hat
        }
    }

    mutating func set(_ instrument: Instrument, step: Int, on: Bool) {
        guard (0..<Self.stepsPerBar).contains(step) else { return }
        switch instrument {
        case .kick: kick[step] = on
        case .snare: snare[step] = on
        case .hat: hat[step] = on
        }
    }

    /// Wann jeder Schritt erklingt: Zwischenschläge (2., 4., … Sechzehntel) rutschen mit Swing nach hinten
    func stepTime(_ step: Int) -> Double {
        let straight = Double(step) * stepSeconds
        return step % 2 == 1 ? straight + swing * stepSeconds * 0.66 : straight
    }

    /// Alles, was in einem Takt erklingt (Zeit ab Taktanfang)
    func events(bar: Int) -> [Event] {
        var events: [Event] = [Event(instrument: .chord, time: 0, chord: chords[bar % chords.count])]
        for instrument in Instrument.allCases {
            let voice: Voice = instrument == .kick ? .kick : instrument == .snare ? .snare : .hat
            for (step, on) in steps(for: instrument).enumerated() where on {
                events.append(Event(instrument: voice, time: stepTime(step)))
            }
        }
        return events.sorted { $0.time < $1.time }
    }

    /// Ein leerer Beat zum Selberbauen (mit einer ruhigen Akkordfolge)
    static func empty(name: String) -> LofiBeat {
        LofiBeat(id: UUID(), name: name, bpm: 75, swing: 0.3,
                 kick: Array(repeating: false, count: stepsPerBar), snare: Array(repeating: false, count: stepsPerBar),
                 hat: Array(repeating: false, count: stepsPerBar),
                 chords: ["Fmaj7", "Em7", "Dm7", "Cmaj7"].compactMap(LofiChord.named),
                 chordVolume: 0.7, warmth: 0.5, crackle: 0.3)
    }

    /// „Speichern unter …“: neuer Beat mit gleichem Inhalt und eigenem Namen
    func copy(named newName: String) -> LofiBeat {
        var copy = self
        copy.id = UUID()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? name + L10n.s(" (Kopie)", " (copy)") : trimmed
        return copy
    }

    /// Das Original eines fertigen Beats (nil bei eigenen Beats)
    static func original(of beat: LofiBeat) -> LofiBeat? { presets.first { $0.id == beat.id } }

    /// Ein fertiger Beat, der geändert wurde: lässt sich aufs Original zurücksetzen
    var canReset: Bool { Self.original(of: self).map { $0 != self } ?? false }

    private static func pattern(_ text: String) -> [Bool] {
        Array(text.filter { $0 != " " }.map { $0 == "x" }.prefix(stepsPerBar))
    }

    /// Fertige Beats zum Loslegen (feste IDs, damit die Auswahl beim Neustart erhalten bleibt)
    static let presets: [LofiBeat] = [
        LofiBeat(id: UUID(uuidString: "6C0F7A6E-0B1D-4C3A-9E51-0A7C1F000001")!,
                 name: L10n.s("Morgenkaffee", "Morning coffee"), bpm: 78, swing: 0.3,
                 kick: pattern("x... .... x.x. ...."), snare: pattern(".... x... .... x..."),
                 hat: pattern("x.x. x.x. x.x. x.xx"),
                 chords: ["Fmaj7", "Em7", "Dm7", "Cmaj7"].compactMap(LofiChord.named),
                 chordVolume: 0.7, warmth: 0.5, crackle: 0.35),
        LofiBeat(id: UUID(uuidString: "6C0F7A6E-0B1D-4C3A-9E51-0A7C1F000002")!,
                 name: L10n.s("Regen am Fenster", "Rainy window"), bpm: 70, swing: 0.4,
                 kick: pattern("x... ..x. .x.. ...."), snare: pattern(".... x... .... x..."),
                 hat: pattern("x.x. x.x. x.x. x.x."),
                 chords: ["Am7", "Dm7", "G7", "Cmaj7"].compactMap(LofiChord.named),
                 chordVolume: 0.75, warmth: 0.7, crackle: 0.55),
        LofiBeat(id: UUID(uuidString: "6C0F7A6E-0B1D-4C3A-9E51-0A7C1F000003")!,
                 name: L10n.s("Mitternacht", "Midnight"), bpm: 66, swing: 0.25,
                 kick: pattern("x... .... ..x. ...."), snare: pattern(".... x... .... x..."),
                 hat: pattern("x... x... x... x.x."),
                 chords: ["Ebmaj7", "Cm7", "Abmaj7", "Bbmaj7"].compactMap(LofiChord.named),
                 chordVolume: 0.8, warmth: 0.8, crackle: 0.4),
        LofiBeat(id: UUID(uuidString: "6C0F7A6E-0B1D-4C3A-9E51-0A7C1F000004")!,
                 name: L10n.s("Lernsession", "Study session"), bpm: 84, swing: 0.2,
                 kick: pattern("x... ...x x... ...."), snare: pattern(".... x... .... x..x"),
                 hat: pattern("xxx. xxx. xxx. xx.x"),
                 chords: ["Dm7", "G7", "Cmaj7", "A7"].compactMap(LofiChord.named),
                 chordVolume: 0.65, warmth: 0.4, crackle: 0.25),
    ]
}

// MARK: - Klang

/// Rechnet einen Beat in einen nahtlosen Loop (Mono, -1…1). Alles selbst erzeugt: Kick, Snare und Hi-Hat aus Sinus und
/// Rauschen, Akkorde als weiches E-Piano mit leichtem Bandleiern, dazu Bass, Knistern und ein dumpfer Filter.
enum LofiRenderer {
    static func render(_ beat: LofiBeat, sampleRate: Double = 44_100) -> [Float] {
        let count = Int((beat.loopSeconds * sampleRate).rounded())
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        var random = SeededRandom(seed: 0x51A7_C0FF)

        /// Klang ab `start` (Sekunden) hineinschreiben, über das Loop-Ende hinaus wieder von vorn
        func add(at start: Double, length: Double, _ sample: (Double) -> Double) {
            let first = Int((start * sampleRate).rounded())
            let samples = Int(length * sampleRate)
            for i in 0..<samples {
                let value = sample(Double(i) / sampleRate)
                out[(first + i) % count] += Float(value)
            }
        }

        for bar in 0..<LofiBeat.barsPerLoop {
            let barStart = Double(bar) * beat.barSeconds
            for event in beat.events(bar: bar) {
                let start = barStart + event.time
                switch event.instrument {
                case .kick:
                    var phase = 0.0
                    add(at: start, length: 0.45) { t in
                        let frequency = 48 + 85 * exp(-t / 0.035)
                        phase += 2 * .pi * frequency / sampleRate
                        return sin(phase) * exp(-t / 0.22) * 0.85
                    }
                case .snare:
                    add(at: start, length: 0.3) { t in
                        let noise = random.next() * exp(-t / 0.07) * 0.28
                        let body = sin(2 * .pi * 185 * t) * exp(-t / 0.045) * 0.22
                        return noise + body
                    }
                case .hat:
                    var last = 0.0
                    add(at: start, length: 0.08) { t in
                        let noise = random.next()
                        let bright = noise - last
                        last = noise
                        return bright * exp(-t / 0.018) * 0.09
                    }
                case .chord:
                    guard let chord = event.chord, beat.chordVolume > 0 else { continue }
                    let volume = beat.chordVolume
                    for note in chord.notes {
                        let frequency = 440 * pow(2, Double(note - 69) / 12)
                        add(at: start, length: beat.barSeconds + 0.4) { t in
                            // Bandleiern: ganz leicht schwankende Tonhöhe
                            let wobble = 1 + 0.0025 * sin(2 * .pi * 0.6 * (start + t))
                            let x = 2 * .pi * frequency * wobble * t
                            let attack = min(1, t / 0.012)
                            let tone = sin(x) + 0.22 * exp(-t / 0.35) * sin(2 * x) + 0.06 * sin(3 * x)
                            let release = t > beat.barSeconds ? exp(-(t - beat.barSeconds) / 0.08) : 1
                            return tone * attack * exp(-t / 1.6) * release * 0.075 * volume
                        }
                    }
                    // Bass: Grundton eine Oktave tiefer, auf Schlag 1 und 3
                    let root = 440 * pow(2, Double(chord.notes[0] - 12 - 69) / 12)
                    for beatStart in [0.0, beat.barSeconds / 2] {
                        add(at: start + beatStart, length: beat.barSeconds / 2) { t in
                            let attack = min(1, t / 0.02)
                            return sin(2 * .pi * root * t) * attack * exp(-t / 0.9) * 0.22 * volume
                        }
                    }
                }
            }
        }

        // Knistern: leises Rauschen und einzelne Knackser
        if beat.crackle > 0 {
            for i in 0..<count {
                var value = random.next() * 0.004
                if random.unit() < 0.00035 { value += random.next() * 0.25 }
                out[i] += Float(value * beat.crackle)
            }
        }

        // Wärme: Tiefpass (zweimal herum, damit der Loop nahtlos ist)
        let cutoff = 9_000 - 7_400 * min(1, max(0, beat.warmth))
        let alpha = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
        var state: Float = 0
        for pass in 0..<2 {
            for i in 0..<count {
                state += alpha * (out[i] - state)
                if pass == 1 { out[i] = state }
            }
        }

        // Nicht übersteuern
        let peak = out.map(abs).max() ?? 0
        if peak > 0.9 {
            let gain = 0.9 / peak
            for i in 0..<count { out[i] *= gain }
        }
        return out
    }
}

/// Immer gleicher Zufall, damit ein Beat jedes Mal gleich klingt
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0…1
    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    /// -1…1
    mutating func next() -> Double { unit() * 2 - 1 }
}

// MARK: - Wann die Musik läuft

/// Entscheidet, ob gerade Musik laufen soll: Klick im Menü, Pomodoro (Fokus an, Pause aus) und Videocalls.
/// Ein Klick während eines Pomodoros gilt bis zur nächsten Phase.
struct MusicCoordinator: Equatable {
    /// Im Menü eingeschaltet (außerhalb eines Pomodoros)
    var manualOn = false
    /// Einstellung: im Pomodoro-Fokus abspielen, in der Pause nicht
    var playDuringFocus = false
    /// Einstellung: in Videocalls pausieren
    var pauseInCalls = true
    var inCall = false
    /// Laufender Pomodoro (nil = keiner)
    var pomodoroStage: Pomodoro.Stage? {
        didSet { if pomodoroStage != oldValue { override = nil } }
    }
    /// Im Menü während dieser Pomodoro-Phase umgeschaltet
    private(set) var override: Bool?

    /// Der Pomodoro bestimmt gerade, ob Musik läuft
    private var pomodoroDecides: Bool { playDuringFocus && pomodoroStage != nil }

    /// Soll sie laufen, abgesehen vom Videocall?
    var wanted: Bool {
        if let override { return override }
        return pomodoroDecides ? pomodoroStage == .focus : manualOn
    }

    var shouldPlay: Bool { wanted && !(inCall && pauseInCalls) }

    /// Klick im Menü: an oder aus
    mutating func toggle() {
        if pomodoroDecides {
            override = !wanted
        } else {
            manualOn.toggle()
            override = nil
        }
    }
}

// MARK: - Spotify und Apple Music

/// Was abgespielt wird
enum MusicPlayback: Equatable {
    case beat(LofiBeat)
    case spotify(uri: String)
    case appleMusic(playlist: String)
}

/// Aus einem geteilten Spotify-Link („Teilen › Link kopieren“) die Spotify-URI machen
enum SpotifyLink {
    private static let kinds = ["playlist", "album", "artist", "track", "show", "episode"]

    static func uri(from text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("spotify:") {
            let parts = text.split(separator: ":")
            guard parts.count == 3, kinds.contains(String(parts[1])), isID(parts[2]) else { return nil }
            return text
        }
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host == "open.spotify.com"
        else { return nil }
        // z. B. /playlist/ID oder /intl-de/playlist/ID
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: kinds.contains), index + 1 < parts.count, isID(parts[index + 1])
        else { return nil }
        return "spotify:\(parts[index]):\(parts[index + 1])"
    }

    /// Zum Anzeigen: aus „spotify:playlist:ID“ wieder den Link machen
    static func webLink(for uri: String) -> String {
        let parts = uri.split(separator: ":")
        guard parts.count == 3 else { return uri }
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }

    private static func isID<S: StringProtocol>(_ id: S) -> Bool {
        id.count >= 10 && id.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

/// Die Spotify-App oder die Musik-App fernsteuern (AppleScript). macOS fragt dafür einmal nach der Erlaubnis.
enum ExternalMusic {
    enum App: String, CaseIterable {
        case spotify, music

        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var scriptName: String { self == .spotify ? "Spotify" : "Music" }
        var title: String { self == .spotify ? "Spotify" : L10n.s("Musik", "Music") }
    }

    static func app(for playback: MusicPlayback) -> App? {
        switch playback {
        case .beat: return nil
        case .spotify: return .spotify
        case .appleMusic: return .music
        }
    }

    /// Text in AppleScript-Anführungszeichen
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Playlist von vorn starten. Mit Zufall: Spotify beginnt sonst oft trotzdem mit dem ersten Titel und mischt erst
    /// danach – deshalb gleich stumm einen Titel weiter, dann geht es jedes Mal woanders los.
    static func playScript(_ playback: MusicPlayback, shuffle: Bool) -> String {
        switch playback {
        case .beat:
            return ""
        case .spotify(let uri):
            guard shuffle else {
                return """
                tell application "Spotify"
                    set shuffling to false
                    play track \(quoted(uri))
                end tell
                """
            }
            // Stumm starten und einen Titel weiter, dann die Lautstärke zurück (auch wenn etwas schiefgeht)
            return """
            tell application "Spotify"
                set shuffling to true
                set savedVolume to sound volume
                set sound volume to 0
                try
                    play track \(quoted(uri))
                    delay 0.6
                    next track
                    delay 0.3
                end try
                set sound volume to savedVolume
            end tell
            """
        case .appleMusic(let playlist):
            return """
            tell application "Music"
                set shuffle enabled to \(shuffle)
                play playlist \(quoted(playlist))
            end tell
            """
        }
    }

    /// Musik einschalten. Spotify verrät nicht, aus welcher Playlist der laufende Titel kommt: Damit nie etwas anderes
    /// weiterläuft, startet dort immer die eigene Playlist. Die Musik-App macht nach einer Pause weiter, solange noch
    /// die eigene Playlist läuft.
    static func startScript(_ playback: MusicPlayback, afterPause: Bool, shuffle: Bool) -> String {
        guard afterPause, case .appleMusic(let playlist) = playback else { return playScript(playback, shuffle: shuffle) }
        return """
        tell application "Music"
            try
                if name of current playlist is \(quoted(playlist)) then
                    play
                    return
                end if
            end try
            set shuffle enabled to \(shuffle)
            play playlist \(quoted(playlist))
        end tell
        """
    }

    /// Spotify bzw. Musik hat sich beim Abspielen nach vorn gedrängt: dann soll die App, in der man gerade war, zurück
    static func shouldRestoreFocus(before: String?, now: String?, app: App) -> Bool {
        guard let before, before != app.bundleID else { return false }
        return now == app.bundleID
    }

    /// Was die Musik-App gerade tut. Spotify verrät nur, ob es spielt (nicht welche Playlist), die Musik-App auch den
    /// Namen der laufenden Playlist: „playing|Lo-Fi“.
    static func statusScript(_ app: App) -> String {
        switch app {
        case .spotify:
            return "tell application \"Spotify\" to return (player state as text)"
        case .music:
            return """
            tell application "Music"
                set playerState to player state as text
                set listName to ""
                try
                    set listName to name of current playlist
                end try
                return playerState & "|" & listName
            end tell
            """
        }
    }

    /// Läuft noch, was Pixelcat gestartet hat? Pausiert, gestoppt oder (bei Musik) eine andere Playlist: nein.
    /// Unklare Antworten zählen als ja, damit der Haken nicht grundlos verschwindet.
    static func isStillOurs(_ playback: MusicPlayback, status: String) -> Bool {
        let text = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts[0] == "paused" || parts[0] == "stopped" { return false }
        if case .appleMusic(let playlist) = playback, parts.count > 1, !parts[1].isEmpty, parts[1] != playlist { return false }
        return true
    }

    static func pauseScript(_ app: App) -> String { "tell application \"\(app.scriptName)\" to pause" }
    static func resumeScript(_ app: App) -> String { "tell application \"\(app.scriptName)\" to play" }
    static let playlistsScript = "tell application \"Music\" to get name of every user playlist"
}

/// Einstellungen › Musik: woher die Musik kommt
enum MusicSourceKind: String, CaseIterable {
    case beat, spotify, appleMusic
}
