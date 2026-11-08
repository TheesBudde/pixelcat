import AppKit
import AVFoundation
import Combine

// MARK: - Eigene Beats abspielen

/// Spielt einen eigenen Beat in Schleife, mit sanftem Ein- und Ausblenden. Der Loop wird im Hintergrund gerechnet.
@MainActor
final class LofiPlayer {
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// Erst beim ersten Abspielen angelegt: Beim Start der App bleibt der Ton unberührt
    private lazy var engine: AVAudioEngine = {
        let engine = AVAudioEngine()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        return engine
    }()
    private lazy var node = AVAudioPlayerNode()
    private var current: LofiBeat?
    private var fade: Timer?
    private var renderTask: Task<Void, Never>?
    /// Wann der Loop zuletzt von vorn begann (für den Lauf-Balken im Baukasten)
    private(set) var loopStarted: Date?
    private(set) var isPlaying = false
    var volume: Float = 0.6 {
        didSet { if isPlaying, fade == nil { engine.mainMixerNode.outputVolume = volume } }
    }

    /// Beat abspielen (oder, falls er schon läuft und sich geändert hat, nahtlos austauschen)
    func play(_ beat: LofiBeat) {
        if isPlaying, current == beat { return }
        let wasPlaying = isPlaying && current != nil
        current = beat
        isPlaying = true
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            let samples = await Task.detached(priority: .userInitiated) { LofiRenderer.render(beat) }.value
            guard let self, !Task.isCancelled, self.isPlaying, self.current == beat else { return }
            self.start(samples, crossfade: wasPlaying)
        }
    }

    private func start(_ samples: [Float], crossfade: Bool) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            NSLog("Pixelcat: Ton lässt sich nicht starten: \(error.localizedDescription)")
            isPlaying = false
            return
        }
        // Beim Austauschen gleich weiter, sonst einblenden
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        loopStarted = Date()
        if !crossfade { engine.mainMixerNode.outputVolume = 0 }
        fadeTo(volume, over: crossfade ? 0.2 : 1.5)
    }

    /// Sofort verstummen (nur ein Hauch Ausblenden, damit es nicht knackt)
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        renderTask?.cancel()
        loopStarted = nil
        fadeTo(0, over: 0.06) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.node.stop()
            self.engine.pause()
        }
    }

    private func fadeTo(_ target: Float, over seconds: Double, then done: (() -> Void)? = nil) {
        fade?.invalidate()
        let start = engine.mainMixerNode.outputVolume
        let began = Date()
        fade = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let progress = Float(min(1, Date().timeIntervalSince(began) / seconds))
                self.engine.mainMixerNode.outputVolume = start + (target - start) * progress
                if progress >= 1 {
                    timer.invalidate()
                    self.fade = nil
                    done?()
                }
            }
        }
    }
}

// MARK: - Spotify und Musik-App

/// Erlaubnis und Steuerung für Spotify bzw. die Musik-App. macOS fragt einmal „Pixelcat möchte … steuern“.
@MainActor
final class MusicAppAccess: ObservableObject {
    enum State: Equatable {
        case notInstalled
        /// Installiert, aber noch nicht gefragt (oder die App läuft gerade nicht)
        case unknown
        case granted
        case denied
    }

    let app: ExternalMusic.App
    @Published private(set) var state: State = .unknown
    @Published private(set) var playlists: [String] = []
    @Published private(set) var busy = false

    init(app: ExternalMusic.App) {
        self.app = app
        refresh()
    }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil }
    private var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty }

    /// Ohne nachzufragen nachsehen, wie es steht
    func refresh() {
        guard isInstalled else { state = .notInstalled; return }
        guard isRunning else { if state != .granted && state != .denied { state = .unknown }; return }
        let bundleID = app.bundleID
        Task {
            let status = await Task.detached { Self.permission(bundleID, ask: false) }.value
            self.state = status
        }
    }

    /// Erlauben: App starten, falls nötig, dann fragt macOS
    func request() async {
        guard isInstalled else { state = .notInstalled; return }
        busy = true
        defer { busy = false }
        await launchIfNeeded()
        let bundleID = app.bundleID
        state = await Task.detached { Self.permission(bundleID, ask: true) }.value
        if state == .granted, app == .music { await loadPlaylists() }
    }

    /// Apple Music: die Playlists der Mediathek holen
    func loadPlaylists() async {
        guard app == .music else { return }
        if state != .granted { await request(); guard state == .granted else { return } }
        let result = await ExternalMusic.run(ExternalMusic.playlistsScript)
        if case .success(let names) = result { playlists = names }
    }

    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Systemeinstellungen › Datenschutz & Sicherheit › Automation
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func launchIfNeeded() async {
        guard !isRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // Kurz warten, bis sie Befehle annimmt
        for _ in 0..<20 where !isRunning { try? await Task.sleep(nanoseconds: 250_000_000) }
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    nonisolated private static func permission(_ bundleID: String, ask: Bool) -> State {
        var target = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &target) == noErr else {
                return OSStatus(procNotFound)
            }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        }
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unknown // noch nicht gefragt oder App läuft nicht
        }
    }
}

extension ExternalMusic {
    enum Failure: Error {
        case notInstalled, notPermitted, failed(String)
    }

    private static let queue = DispatchQueue(label: "pixelcat.music.applescript")

    /// AppleScript im Hintergrund ausführen; bei Listen die Einträge, sonst der Text
    static func run(_ source: String) async -> Result<[String], Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? "\(number)"
                    continuation.resume(returning: .failure(number == -1743 ? .notPermitted : .failed(message)))
                    return
                }
                var values: [String] = []
                if let result {
                    if result.numberOfItems > 0 {
                        for index in 1...result.numberOfItems {
                            if let text = result.atIndex(index)?.stringValue { values.append(text) }
                        }
                    } else if let text = result.stringValue {
                        values = [text]
                    }
                }
                continuation.resume(returning: .success(values))
            }
        }
    }
}

// MARK: - Zusammenspiel

/// Die Musik der App: Klick im Menü, Pomodoro und Videocalls entscheiden (`MusicCoordinator`), gespielt wird ein
/// eigener Beat oder eine Playlist in Spotify bzw. der Musik-App.
@MainActor
final class MusicController {
    private(set) var coordinator = MusicCoordinator()
    private let beats = LofiPlayer()
    private var playback: MusicPlayback?
    /// Was gerade läuft (bzw. zuletzt lief und nur pausiert ist)
    private var playing: MusicPlayback?
    private var pausedExternal: MusicPlayback?
    /// Etwas ging schief (z. B. keine Erlaubnis): Text für einen Hinweis und welche App
    var onProblem: ((String, ExternalMusic.App?) -> Void)?
    /// Musik an oder aus (für das Menü)
    var onChange: ((Bool) -> Void)?

    /// Der Beat-Baukasten ist offen: so lange schweigt die Musik im Menü, man hört nur den Baukasten
    private var builderOpen = false

    /// Spotify und Apple Music in zufälliger Reihenfolge
    private var shuffle = true
    /// Schaut regelmäßig nach, ob in Spotify bzw. Musik noch läuft, was Pixelcat gestartet hat
    private var watch: Timer?
    private var externalStarted = Date.distantPast

    var isOn: Bool { coordinator.shouldPlay }

    func setBuilderOpen(_ open: Bool) {
        guard open != builderOpen else { return }
        builderOpen = open
        update()
    }
    var isConfigured: Bool { playback != nil }

    func apply(_ settings: AppSettings) {
        coordinator.playDuringFocus = settings.musicDuringFocus
        coordinator.pauseInCalls = settings.musicPauseInCalls
        beats.volume = Float(settings.musicVolume)
        shuffle = settings.musicShuffle
        if settings.musicPlayback != playback {
            playback = settings.musicPlayback
            update(sourceChanged: true)
        } else {
            update()
        }
    }

    func toggle() {
        coordinator.toggle()
        if coordinator.wanted, playback == nil {
            coordinator.toggle()
            onProblem?(L10n.s("Wähle zuerst in den Einstellungen unter Musik, was laufen soll.",
                              "First choose what to play in Settings › Music."), nil)
            return
        }
        update()
    }

    func pomodoroChanged(_ stage: Pomodoro.Stage?) {
        coordinator.pomodoroStage = stage
        update()
    }

    func callChanged(_ inCall: Bool) {
        guard inCall != coordinator.inCall else { return }
        coordinator.inCall = inCall
        update()
    }

    /// Beim Beenden still werden (Spotify und Musik pausieren)
    func stopAll() {
        stopWatching()
        beats.stop()
        if let playing, let app = ExternalMusic.app(for: playing) {
            Task { _ = await ExternalMusic.run(ExternalMusic.pauseScript(app)) }
        }
        playing = nil
    }

    private func update(sourceChanged: Bool = false) {
        let shouldPlay = coordinator.shouldPlay && playback != nil && !builderOpen
        // Eigener Beat geändert (Baukasten): nahtlos austauschen
        if sourceChanged, shouldPlay, case .beat = playing, case .beat(let beat) = playback {
            playing = playback
            beats.play(beat)
            onChange?(coordinator.shouldPlay)
            return
        }
        if sourceChanged, let old = playing, old != playback {
            halt(old)
            playing = nil
            pausedExternal = nil
        }
        if shouldPlay, let playback {
            if playing != playback { start(playback) }
        } else if let current = playing {
            halt(current)
            playing = nil
        }
        onChange?(coordinator.shouldPlay)
    }

    private func start(_ playback: MusicPlayback) {
        playing = playback
        switch playback {
        case .beat(let beat):
            beats.play(beat)
        case .spotify, .appleMusic:
            guard let app = ExternalMusic.app(for: playback) else { return }
            // Nach einer Pause: Apple Music macht weiter, Spotify startet die eigene Playlist (siehe startScript)
            let script = ExternalMusic.startScript(playback, afterPause: pausedExternal == playback, shuffle: shuffle)
            pausedExternal = nil
            externalStarted = Date()
            startWatching()
            Task { await self.runExternal(script, app: app, playback: playback) }
        }
    }

    private func halt(_ playback: MusicPlayback) {
        switch playback {
        case .beat:
            beats.stop()
        case .spotify, .appleMusic:
            guard let app = ExternalMusic.app(for: playback) else { return }
            stopWatching()
            pausedExternal = playback
            Task { _ = await ExternalMusic.run(ExternalMusic.pauseScript(app)) }
        }
    }

    private func runExternal(_ script: String, app: ExternalMusic.App, playback: MusicPlayback) async {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil else {
            fail(L10n.s("\(app.title) ist auf diesem Mac nicht installiert.", "\(app.title) isn't installed on this Mac."), app)
            return
        }
        // Wo man gerade arbeitet: Spotify bzw. Musik soll sich nicht davor drängen
        let front = NSWorkspace.shared.frontmostApplication
        let access = MusicAppAccess(app: app)
        await access.launchIfNeeded()
        let result = await ExternalMusic.run(script)
        await keepInBackground(app, previous: front)
        guard playing == playback else { return }
        switch result {
        case .success:
            break
        case .failure(.notPermitted):
            fail(L10n.s("Pixelcat darf \(app.title) noch nicht steuern. Erlaube es unter Einstellungen › Musik.",
                        "Pixelcat isn't allowed to control \(app.title) yet. Allow it in Settings › Music."), app)
        case .failure(let error):
            fail(L10n.s("\(app.title) konnte nicht abspielen. Stimmt die Playlist?",
                        "\(app.title) couldn't play. Is the playlist right?") + " (\(error))", app)
        }
    }

    /// Hat sich die Musik-App nach vorn geholt, wird sie ausgeblendet (wie mit ⌘H): Dann rückt die vorige App wieder nach
    /// vorn. Einfach die vorige App aktivieren darf eine App im Hintergrund seit macOS 14 nicht mehr.
    private func keepInBackground(_ app: ExternalMusic.App, previous: NSRunningApplication?) async {
        for wait in [0.0, 0.3, 0.8, 1.5, 2.5] {
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            let front = NSWorkspace.shared.frontmostApplication
            guard ExternalMusic.shouldRestoreFocus(before: previous?.bundleIdentifier, now: front?.bundleIdentifier, app: app)
            else { continue }
            front?.hide()
            previous?.activate()
        }
    }

    // MARK: Hat jemand in Spotify bzw. Musik übernommen?

    private func startWatching() {
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStillOurs() }
        }
    }

    private func stopWatching() {
        watch?.invalidate()
        watch = nil
    }

    private func checkStillOurs() {
        // Kurz nach dem Start nicht (Spotify schaltet dabei selbst kurz um)
        guard let current = playing, let app = ExternalMusic.app(for: current),
              Date().timeIntervalSince(externalStarted) > 8 else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty else {
            return takenOver() // App beendet
        }
        Task {
            let result = await ExternalMusic.run(ExternalMusic.statusScript(app))
            guard self.playing == current, case .success(let values) = result else { return }
            if !ExternalMusic.isStillOurs(current, status: values.joined(separator: "|")) { self.takenOver() }
        }
    }

    /// Dort wurde pausiert oder etwas anderes gestartet: Pixelcat lässt los (ohne selbst zu pausieren), der Haken geht weg
    private func takenOver() {
        stopWatching()
        playing = nil
        pausedExternal = nil
        if coordinator.wanted { coordinator.toggle() }
        onChange?(coordinator.shouldPlay)
    }

    private func fail(_ message: String, _ app: ExternalMusic.App?) {
        stopWatching()
        playing = nil
        if coordinator.wanted { coordinator.toggle() }
        onChange?(coordinator.shouldPlay)
        onProblem?(message, app)
    }
}
