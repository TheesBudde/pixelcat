import AppKit

/// Randloses, durchsichtiges Fenster, das über allen anderen schwebt und auf allen Spaces bleibt.
@MainActor
func makeOverlayPanel() -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    return panel
}

// MARK: - Napf und Knäuel

/// Zeigt ein einzelnes Pixelbild (Napf oder Knäuel) in einem eigenen kleinen Fenster.
@MainActor
final class PropView: NSView {
    var sprite: Sprite? {
        didSet { if sprite !== oldValue { needsDisplay = true } }
    }
    var scale: CGFloat = 3 {
        didSet { needsDisplay = true }
    }
    var colors = PropColors.colors
    /// Hut und Fliege auf dem Bild (Pixel ab dessen linker unterer Ecke)
    var extras: [(sprite: Sprite, x: Int, y: Int)] = [] {
        didSet { needsDisplay = true }
    }
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var spriteOrigin: CGPoint {
        guard let sprite else { return .zero }
        let columns = Int(bounds.width / scale)
        return CGPoint(x: CGFloat((columns - sprite.width) / 2), y: 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard onMouseDown != nil, let sprite else { return nil }
        let p = convert(point, from: superview)
        let col = Int(floor(p.x / scale - spriteOrigin.x))
        let row = sprite.height - 1 - Int(floor(p.y / scale))
        for dy in -1...1 {
            for dx in -1...1 where sprite.pixel(col + dx, row + dy) != "." {
                return self
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }

    override func draw(_ dirtyRect: NSRect) {
        guard let sprite, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        sprite.draw(in: ctx, x: spriteOrigin.x, y: spriteOrigin.y, scale: scale, colors: colors)
        for extra in extras {
            extra.sprite.draw(in: ctx, x: spriteOrigin.x + CGFloat(extra.x), y: spriteOrigin.y + CGFloat(extra.y),
                              scale: scale, colors: Frames.accessoryColors)
        }
    }
}

@MainActor
final class PropWindow {
    let panel = makeOverlayPanel()
    let view = PropView()
    private let columns: Int
    private let rows: Int

    var scale: CGFloat {
        didSet { resize() }
    }

    init(columns: Int, rows: Int, scale: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.scale = scale
        panel.contentView = view
        resize()
    }

    private func resize() {
        let size = NSSize(width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = scale
    }

    func place(centerX: CGFloat, bottom: CGFloat) {
        let origin = NSPoint(x: (centerX - panel.frame.width / 2).rounded(), y: bottom.rounded())
        // Ein Fenster zu verschieben kostet den Fensterserver Arbeit – nur wenn es sich wirklich bewegt
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

// MARK: - Pomodoro

struct Pomodoro {
    enum Stage { case focus, rest }

    var stage: Stage
    var ends: Date

    /// Text für die Menüleiste, z. B. "24:13" oder "Pause 4:12".
    func label(at now: Date) -> String {
        let time = countdownText(until: ends, from: now)
        return stage == .focus ? time : L10n.s("Pause", "Break") + " " + time
    }
}

/// Restzeit als "4:12" bzw. "1:04:12".
func countdownText(until end: Date, from now: Date) -> String {
    let left = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
    return left >= 3600
        ? String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
        : String(format: "%d:%02d", left / 60, left % 60)
}

// MARK: - Timer

/// Selbst gestellter Timer: Die Katze schläft, bis er abläuft.
struct CatTimer {
    var ends: Date
    /// Läuft gerade eine Pause (Pausen-Erinnerung), während der Timer weiterzählt?
    var breakEnds: Date?
    /// Abgelaufen – die Katze wartet in der Mitte, bis man sie streichelt oder anklickt
    var finished = false
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

// MARK: - Steuerung

/// Hält alles zusammen: Katze, Napf, Knäuel, Pomodoro, Timer, Pausen-Erinnerung, Sensoren.
/// Ein Takt bewegt alles und zeichnet neu – 30-mal pro Sekunde, wenn sich etwas bewegt,
/// sonst seltener, um Energie zu sparen.
@MainActor
final class CatController {
    private let panel = makeOverlayPanel()
    private let view = CatView()
    private let brain = CatBrain()
    private var ticker: Timer?
    private var tickInterval: TimeInterval = 1.0 / 30
    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    private var lastPointer = NSEvent.mouseLocation
    /// Wie lange der Mauszeiger schon ruht
    private var pointerIdle = 0.0
    /// Wie weit die Maus schon über die Katze gestrichen ist
    private var strokeDistance: CGFloat = 0
    private(set) var isVisible = false

    private var bowl: Bowl?
    private var bowlWindow: PropWindow?
    private var ball: Ball?
    /// Vogel, während niemand am Rechner ist
    private var bird: Bird?
    /// Sprung aus dem Einrichtungsfenster aufs Dock
    private var dropWindow: PropWindow?
    private var dropTimer: Timer?
    private var birdWindow: PropWindow?
    /// Für diese Abwesenheit kam der Vogel schon (erst nach neuer Eingabe wieder)
    private var birdDoneForIdle = false
    /// „Jetzt zeigen“: Der Vogel bleibt eine Weile, auch wenn gerade jemand die Maus bewegt
    private var birdStaysUntil = Date.distantPast
    private var ballWindow: PropWindow?
    private var dragOffset = CGPoint.zero
    private var lastDrag: (point: NSPoint, time: CFTimeInterval)?
    private var dragVelocity = CGVector.zero

    private(set) var pomodoro: Pomodoro?
    private(set) var timer: CatTimer?
    private var nextReminder = Date.distantFuture
    /// Pausenfrage („Pause?“ mit Daumen) offen bis hierhin
    private var breakQuestionUntil: Date?
    /// Angenommene Pause läuft bis hierhin (Restzeit oben in der Menüleiste)
    private(set) var breakEnds: Date?
    /// Weggedrückte Pausen (nach Aktivität: nächste Erinnerung früher)
    private var snooze = BreakSnooze()
    /// Geführte Pause: Übungen nach Daumen hoch
    var guidedBreaks = true
    private var guided: (plan: GuidedBreak, start: Date, step: Int?)?
    /// Statistik (Pausen, aktive Arbeit, Pomodoros, Trinken)
    var stats: StatsStore?
    /// Apps, deren aktive Zeit mitgezählt wird (Bundle-IDs)
    var trackedApps: Set<String> = []
    /// Pomodoro-Pausen mit Übungen wie die geführte Pause
    var guidedPomodoros = true
    private var lastActiveCheck = Date()

    /// Ruhemodus: Sie geht in den Korb bzw. aus dem Bild – keine Erinnerungen, keine Töne, kein Vogel
    var silent = false {
        didSet {
            guard silent != oldValue else { return }
            if silent {
                cancelErrand()
                cancelBreak()
                errands.clearQueue()
                removeBird()
                setPlaying(false)
                removeBowl()
                bubble?.pop()
                nextReminder = .distantFuture
            } else {
                scheduleReminder()
            }
            brain.suppressVisits = hiddenBecause != nil || silent
            brain.roaming = userRoaming || hiddenBecause != nil || silent
            updateStatusText(force: true)
        }
    }
    static let breakQuestionTimeout: TimeInterval = 3 * 60
    private var perchRefresh = 0.0
    private var sensorRefresh = 0.0
    private var statusText: String?
    /// Meldet Änderungen des Texts neben dem Menüleisten-Symbol (nil = kein Text).
    var onStatusChange: ((String?) -> Void)?

    /// Auf welchem Bildschirm sie gerade ist (nil = Hauptbildschirm)
    private var screenID: CGDirectDisplayID?
    private let purr = Purr()
    let focusMonitor: FocusMonitor
    private var focusActive = false
    /// Gerade versteckt wegen Videocall oder Bildschirmfreigabe (und warum)
    private(set) var hiddenBecause: CallDetector.Reason?
    private var callEndedAt: Date?
    private var userRoaming = false

    /// Welches Miau beim nächsten Pausen-Strecken kommt (und seit wann es aussteht)
    private var pendingMeow: (kind: Meow.Kind, since: Date)?
    /// Gedankenblase über der Katze („Pause“ oder eine kleine Erinnerung)
    private var bubble: ThoughtBubble?

    /// Kleine Erinnerungen (trinken, Fenster, Aufgaben, Feierabend): geplant und nacheinander abgearbeitet
    private let errands = ErrandScheduler()
    private var activeErrand: (errand: Errand, since: Date)?
    /// Kurze Atempause zwischen zwei Erinnerungen
    private var nextErrandAllowed = Date.distantPast
    /// Die Blase der laufenden Erinnerung (wird sie von der Pausenblase ersetzt, ist sie weg)
    private weak var errandBubble: ThoughtBubble?
    /// Fenster der Augenpause: wo es steht, wie weit es eingeblendet ist (0…1) und ob es gerade verschwindet
    private var lookoutWindow: PropWindow?
    private var lookoutX: CGFloat = 0
    private var lookoutAppear = 0.0
    private var lookoutLeaving = false

    /// Ein Programm im Vollbild: Dann ist kein Dock da, und sie läuft am unteren Bildschirmrand
    private(set) var isFullscreen = false
    private var fullscreenRefresh = 0.0
    /// Körbchen im Dock: Dock-Symbol, in dem sie schläft, solange sie auf Streifzug ist
    private let basketTile = BasketTileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private var basketRefresh = 0.0
    private var tileClock = 0.0

    // MARK: Einstellungen

    var scale: CGFloat {
        didSet { if scale != oldValue { applyScale() } }
    }
    var coat: Coat {
        didSet { view.coat = coat }
    }
    var breakReminders = false {
        didSet { if breakReminders != oldValue { scheduleReminder() } }
    }
    /// Kletter-Modus: Die Katze darf auf offene Fenster.
    var climbing: Bool {
        get { brain.climbingEnabled }
        set {
            guard newValue != brain.climbingEnabled else { return }
            if newValue { brain.setPerches(findPerches()) }
            brain.climbingEnabled = newValue
        }
    }
    var sounds = true
    var purring = true
    var chaseCursor: Bool {
        get { brain.chaseEnabled }
        set { brain.chaseEnabled = newValue }
    }
    var multiScreen = true
    var hideDuringCalls = true {
        didSet { if !hideDuringCalls { setHidden(because: nil) } }
    }
    var respectFocus = true
    var basketInDock = false {
        didSet { if basketInDock != oldValue { updateDockPresence() } }
    }
    var focusMinutes = 25
    var breakMinutes = 5
    var reminderMinutes: ClosedRange<Double> = 45...55 {
        didSet { if reminderMinutes != oldValue { scheduleReminder() } }
    }
    /// Pausen-Erinnerung nach echter Aktivität statt in festen Abständen
    var breakByActivity = false {
        didSet { if breakByActivity != oldValue { scheduleReminder() } }
    }
    /// Nach so vielen Minuten Arbeit am Stück
    var activityMinutes = 50
    var breakLength: TimeInterval {
        get { brain.breakVisitLength }
        set { brain.breakVisitLength = newValue }
    }
    /// Trink-Erinnerung: alle so viele Minuten (nil = aus)
    var drinkMinutes: Int? {
        didSet { if drinkMinutes != oldValue { errands.configure(.drink, every: drinkMinutes.map(Double.init), now: Date()) } }
    }
    /// Feierabend: Uhrzeit (Minuten nach Mitternacht), nur werktags? (nil = aus)
    var quittingTime: (minutes: Int, weekdaysOnly: Bool)? {
        didSet {
            errands.configureQuittingTime(hour: (quittingTime?.minutes ?? 0) / 60, minute: (quittingTime?.minutes ?? 0) % 60,
                                          weekdaysOnly: quittingTime?.weekdaysOnly ?? true, enabled: quittingTime != nil)
            outfitTimes.quitting = quittingTime
        }
    }
    /// Wann sie was trägt (Feierabend, Schlafenszeit, Morgen)
    var outfitTimes = OutfitTimes() {
        didSet { updateOutfit() }
    }
    /// Aufgaben-Erinnerung: an/aus und die Aufgaben, jede zu ihrer Uhrzeit
    var tasksEnabled = false {
        didSet { if tasksEnabled != oldValue { configureTasks() } }
    }
    var taskList: [TaskItem] = [] {
        didSet { if taskList != oldValue { configureTasks() } }
    }
    /// An Aufgaben auch während Videocalls erinnern – die Katze bleibt dann versteckt, nur die Blase erscheint
    var tasksDuringCalls = false
    /// Motivation: an/aus und die eigenen Sprüche (leer = ihre eigenen)
    var motivationEnabled = false
    var motivationSayings: [String] = []
    private var lastSaying: String?
    /// Die Einstellungen sind einmal übernommen (danach ist es kein Start mehr)
    private var settingsApplied = false
    /// Augenpause: alle so viele Minuten (nil = aus)
    var eyeBreakMinutes: Int? {
        didSet {
            if eyeBreakMinutes != oldValue { errands.configure(.lookout, every: eyeBreakMinutes.map(Double.init), now: Date()) }
        }
    }

    /// Streifzug: Die Katze ist draußen und kommt nur zu Pausen vorbei.
    var roaming: Bool {
        get { userRoaming }
        set {
            userRoaming = newValue
            brain.roaming = userRoaming || hiddenBecause != nil || silent
        }
    }

    /// Alle Einstellungen auf einmal übernehmen.
    func apply(_ settings: AppSettings) {
        coat = settings.coat
        scale = settings.scale
        climbing = settings.climbing
        chaseCursor = settings.chaseCursor
        multiScreen = settings.multiScreen
        breakReminders = settings.breakReminders
        sounds = settings.sounds
        purring = settings.purring
        hideDuringCalls = settings.hideDuringCalls
        respectFocus = settings.respectFocus
        basketInDock = settings.basketInDock
        focusMinutes = settings.pomodoroFocus
        breakMinutes = settings.pomodoroBreak
        reminderMinutes = Double(settings.reminderMin)...Double(settings.reminderMax)
        activityMinutes = settings.activityMinutes
        breakByActivity = settings.breakByActivity
        breakLength = TimeInterval(settings.breakLength * 60)
        drinkMinutes = settings.drinkReminders ? settings.drinkInterval : nil
        eyeBreakMinutes = settings.eyeBreaks ? settings.eyeInterval : nil
        taskList = settings.taskItems
        tasksDuringCalls = settings.tasksDuringCalls
        meowForTasks = settings.meowForTasks
        birdAfterMinutes = settings.birdWhenAway ? settings.birdMinutes : nil
        tasksEnabled = settings.taskReminders
        let quitting = settings.quittingTimeEnabled ? (settings.quittingTime, settings.quittingWeekdaysOnly) : nil
        if quitting?.0 != quittingTime?.minutes || quitting?.1 != quittingTime?.weekdaysOnly {
            quittingTime = quitting.map { (minutes: $0.0, weekdaysOnly: $0.1) }
        }
        silent = settings.silentMode
        guidedBreaks = settings.guidedBreaks
        guidedPomodoros = settings.guidedPomodoros
        trackedApps = Set(settings.trackedApps)
        motivationEnabled = settings.motivationEnabled
        motivationSayings = settings.motivationSayings
        errands.configureMotivation(enabled: motivationEnabled, workdayEnd: quittingTime?.minutes,
                                    weekdaysOnly: quittingTime?.weekdaysOnly ?? false)
        let bedtime = settings.bedtimeEnabled ? settings.bedtime : nil
        let morningEnd = settings.morningOutfit ? settings.morningEnd : nil
        if bedtime != outfitTimes.bedtime || morningEnd != outfitTimes.morningEnd {
            outfitTimes.bedtime = bedtime
            outfitTimes.morningEnd = morningEnd
        }
        if settings.awayMode != userRoaming { roaming = settings.awayMode }
        updateStatusText(force: true)
        settingsApplied = true
    }

    var isPlaying: Bool { ball != nil }
    /// Im Streifzug unterwegs (kein Pausenbesuch) – dann gibt es nichts zu füttern oder zu spielen
    var isOutAndAbout: Bool { brain.isOutAndAbout }
    /// Die Katze schläft fest (Pomodoro-Fokus oder laufender Timer).
    var isInFocus: Bool { brain.mode == .focus }
    /// Miauen erlaubt: eingeschaltet, kein macOS-Fokus, kein Videocall
    var soundsAllowed: Bool { sounds && !focusActive && hiddenBecause == nil && !silent }
    /// Auch bei Aufgaben-Erinnerungen miauen
    var meowForTasks = false
    /// Vogel jagen, wenn so lange niemand am Rechner war (Minuten, nil = aus)
    var birdAfterMinutes: Int?
    /// Wie oft sie schon miaut hat (für den Selbsttest)
    private(set) var meowCount = 0

    private func meow(_ kind: Meow.Kind) {
        guard soundsAllowed else { return }
        Meow.play(kind)
        meowCount += 1
    }

    /// Beim Start im Streifzug gleich draußen sein, statt erst hinauszulaufen.
    func startRoamingOutside() {
        userRoaming = true
        brain.roaming = true
        updateBounds()
        brain.startOutside()
    }

    /// Zum Vorführen: immer Nachmittag (aktive Katze) und viel Klettern.
    func enableDemo() {
        let afternoon = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        brain.clock = { afternoon }
        brain.adventurousness = 2.2
    }

    /// Zum Ausprobieren der Verkleidungen ohne auf den Feiertag zu warten (Start mit --outfit pumpkin|santa|party).
    var outfitOverride: Sprite? {
        didSet { updateOutfit() }
    }

    init(scale: CGFloat, coat: Coat, focusMonitor: FocusMonitor) {
        self.scale = scale
        self.coat = coat
        self.focusMonitor = focusMonitor
        view.coat = coat
        panel.contentView = view
        view.onClick = { [weak self] in self?.brain.clicked() }
        // Miauen erst, wenn sie sich zur Pause streckt
        brain.onBreakStretch = { [weak self] in
            guard let self, let meow = pendingMeow else { return }
            pendingMeow = nil
            if Date().timeIntervalSince(meow.since) < 120 { self.meow(meow.kind) }
        }
        // Gestreichelt oder angeklickt: abgelaufener Timer ist erledigt
        brain.onAcknowledged = { [weak self] in
            guard let self, timer?.finished == true else { return }
            timer = nil
            scheduleReminder()
            updateStatusText()
        }
        brain.locateBasket = { [weak self] in self?.locateBasket() }
        applyScale()
        updateOutfit()
        // Der Takt läuft immer, damit Pomodoro und Timer auch bei ausgeblendeter Katze weiterzählen.
        restartTicker()
    }

    // MARK: Ein- und Ausblenden

    func show() {
        guard !isVisible else { return }
        isVisible = true
        updateBounds()
        if brain.x == 0 {
            brain.x = .random(in: brain.minX...max(brain.minX, brain.maxX))
        }
        tick()
        bowlWindow?.panel.orderFrontRegardless()
        lookoutWindow?.panel.orderFrontRegardless()
        if !brain.isAway { panel.orderFrontRegardless() }
        ballWindow?.panel.orderFrontRegardless()
        birdWindow?.panel.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        bowlWindow?.panel.orderOut(nil)
        lookoutWindow?.panel.orderOut(nil)
        ballWindow?.panel.orderOut(nil)
        birdWindow?.panel.orderOut(nil)
    }

    /// Nach der Einrichtung: Die Katze springt aus dem Fenster (`rect`: dort steht sie, in Bildschirmpunkten),
    /// fällt aufs Dock und schrumpft dabei auf ihre Größe. Unten übernimmt die richtige Katze, dann `then`.
    func dropIn(from rect: NSRect, then: @escaping () -> Void) {
        updateBounds()
        brain.dockY = ground
        let sprite = Frames.stand
        let outfit = outfitNow()
        let startScale = max(1, rect.width / CGFloat(sprite.width))
        // Oben Platz für den Hut
        let window = PropWindow(columns: sprite.width, rows: sprite.height + 10, scale: startScale)
        window.view.colors = coat.colors
        window.view.sprite = sprite
        window.view.extras = outfit.pieces(on: sprite)
        let centerX = rect.midX
        let startBottom = rect.minY
        let target = scale
        var bottom = startBottom
        var vy: CGFloat = 320 // erst ein kleiner Hopser nach oben
        var last = CACurrentMediaTime()
        window.place(centerX: centerX, bottom: bottom)
        window.panel.orderFrontRegardless()
        dropWindow?.panel.orderOut(nil)
        dropTimer?.invalidate()
        dropWindow = window
        dropTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let now = CACurrentMediaTime()
                let dt = CGFloat(min(0.05, now - last))
                last = now
                vy -= 2400 * dt
                bottom += vy * dt
                // Je tiefer sie fällt, desto kleiner wird sie – unten hat sie genau ihre Größe
                let progress = min(1, max(0, (startBottom - bottom) / max(1, startBottom - self.ground)))
                window.scale = startScale + (target - startScale) * progress
                let pose = vy > 0 ? Frames.stand : Frames.walkA
                if window.view.sprite !== pose {
                    window.view.sprite = pose
                    window.view.extras = outfit.pieces(on: pose)
                }
                if bottom <= self.ground {
                    timer.invalidate()
                    self.dropTimer = nil
                    window.panel.orderOut(nil)
                    self.dropWindow = nil
                    self.brain.arrive(centerX: centerX)
                    if self.isVisible { self.tick() } else { self.show() }
                    then()
                    return
                }
                window.place(centerX: centerX, bottom: bottom)
            }
        }
    }

    // MARK: Menüaktionen

    func startle() { brain.startle() }
    func goToSleep() { brain.goToSleep() }

    func feed() {
        guard !isInFocus, !brain.isAway else { return }
        if let bowl, bowl.food > 0 { return }
        placeBowl(water: false)
        brain.noticeSomething()
    }

    /// Napf hinstellen – irgendwo ins mittlere Drittel bis Fünftel, nicht direkt unter die Katze.
    private func placeBowl(water: Bool) {
        guard let frame = screen?.frame else { return }
        var x = frame.minX
        for _ in 0..<10 {
            x = .random(in: frame.minX + frame.width * 0.15...frame.maxX - frame.width * 0.15)
            if abs(x - catCenter) > 150 { break }
        }
        removeBowl()
        let bowl = Bowl(x: x, water: water)
        let window = PropWindow(columns: 14, rows: 6, scale: scale)
        self.bowl = bowl
        bowlWindow = window
        brain.bowl = bowl
        updateBowlWindow()
        if isVisible {
            window.panel.orderFrontRegardless()
            if panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func updateBowlWindow() {
        guard let bowl, let bowlWindow else { return }
        if bowl.water {
            let ripple = Int(CACurrentMediaTime() / 0.6) % 2 == 0
            bowlWindow.view.sprite = bowl.food > 0.7 ? (ripple ? Frames.waterFullA : Frames.waterFullB)
                : bowl.food > 0 ? Frames.waterHalf : Frames.waterEmpty
        } else {
            bowlWindow.view.sprite = bowl.food > 0.5 ? Frames.bowlFull
                : bowl.food > 0 ? Frames.bowlHalf : Frames.bowlEmpty
        }
        bowlWindow.place(centerX: bowl.x, bottom: ground)
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            guard ball == nil, !isInFocus, !brain.isAway, let frame = screen?.frame else { return }
            // Das Knäuel kommt von oben hereingefallen, ein Stück neben der Katze
            let side: CGFloat = catCenter < frame.midX ? 1 : -1
            let ball = Ball(x: min(max(catCenter + side * 160 * scale / 3, frame.minX + 40), frame.maxX - 40))
            ball.y = 120 * scale / 3
            let window = PropWindow(columns: 9, rows: 9, scale: scale)
            window.view.onMouseDown = { [weak self] p in self?.grabBall(at: p) }
            window.view.onMouseDragged = { [weak self] p in self?.dragBall(to: p) }
            window.view.onMouseUp = { [weak self] _ in self?.releaseBall() }
            self.ball = ball
            ballWindow = window
            brain.ball = ball
            if isVisible { window.panel.orderFrontRegardless() }
            brain.noticeSomething()
        } else {
            ballWindow?.panel.orderOut(nil)
            ballWindow = nil
            ball = nil
            brain.ball = nil
        }
    }

    func startPomodoro() {
        guard timer == nil else { return }
        cancelErrand()
        cancelBreak()
        pomodoro = Pomodoro(stage: .focus, ends: Date().addingTimeInterval(Double(focusMinutes) * 60))
        setPlaying(false)
        removeBowl()
        brain.mode = .focus
        updateStatusText()
    }

    func stopPomodoro() {
        stopGuided()
        bubble?.pop()
        pomodoro = nil
        brain.mode = .normal
        scheduleReminder()
        updateStatusText()
    }

    func startTimer(minutes: Double) {
        guard pomodoro == nil else { return }
        cancelErrand()
        cancelBreak()
        timer = CatTimer(ends: Date().addingTimeInterval(minutes * 60))
        setPlaying(false)
        removeBowl()
        brain.mode = .focus
        updateStatusText()
    }

    func stopTimer() {
        if timer?.breakEnds != nil { bubble?.pop() }
        if timer?.finished == true {
            brain.acknowledge() // wie Streicheln
        }
        timer = nil
        brain.mode = .normal
        updateStatusText()
    }

    /// Timer abgelaufen oder Pause vorbei?
    private func updateTimer(now: Date) {
        guard var timer, !timer.finished else { return }
        if now >= timer.ends {
            // Abgelaufen – auch mitten in einer Pause: Sie (bleibt) wach, kommt in die Mitte
            // und wartet dort, bis man sie streichelt oder anklickt.
            timer.finished = true
            timer.breakEnds = nil
            self.timer = timer
            brain.mode = .normal
            pendingMeow = (.breakStarts, now)
            brain.callToCenter(untilAcknowledged: true)
            scheduleReminder() // gilt als Pause; die nächste Erinnerung zählt neu
            return
        }
        if let breakEnds = timer.breakEnds, now >= breakEnds {
            // Pause vorbei, der Timer läuft weiter: wieder schlafen bzw. hinaus
            timer.breakEnds = nil
            brain.mode = .focus
        }
        self.timer = timer
    }

    /// Pausen-Erinnerung, während ein Timer läuft: eine Pause, der Timer zählt weiter.
    private func takeBreakDuringTimer(now: Date) {
        guard var timer, timer.breakEnds == nil else { return }
        timer.breakEnds = now.addingTimeInterval(breakLength)
        self.timer = timer
        brain.mode = .focusBreak
        pendingMeow = (.reminder, now)
        brain.callToCenter()
        showBubble(until: now.addingTimeInterval(breakLength))
    }

    // MARK: Knäuel ziehen und werfen

    private func grabBall(at point: NSPoint) {
        guard let ball else { return }
        ball.isHeld = true
        dragOffset = CGPoint(x: ball.x - point.x, y: ground + ball.y - point.y)
        lastDrag = (point, CACurrentMediaTime())
        dragVelocity = .zero
    }

    private func dragBall(to point: NSPoint) {
        guard let ball else { return }
        let now = CACurrentMediaTime()
        if let last = lastDrag, now > last.time {
            let dt = CGFloat(now - last.time)
            // geglättet, damit der Wurf nicht von einem einzelnen Ruckler abhängt
            dragVelocity.dx = dragVelocity.dx * 0.5 + (point.x - last.point.x) / dt * 0.5
            dragVelocity.dy = dragVelocity.dy * 0.5 + (point.y - last.point.y) / dt * 0.5
        }
        lastDrag = (point, now)
        ball.x = point.x + dragOffset.x
        ball.y = max(0, point.y + dragOffset.y - ground)
    }

    private func releaseBall() {
        guard let ball else { return }
        let limit = 1400 * scale / 3
        ball.isHeld = false
        ball.vx = max(-limit, min(limit, dragVelocity.dx))
        ball.vy = max(-limit, min(limit, dragVelocity.dy))
        lastDrag = nil
    }

    // MARK: Bildschirme

    /// Hauptbildschirm (mit der Menüleiste) – nach ihm richten sich die Fensterkoordinaten.
    private var primaryScreen: NSScreen? { NSScreen.screens.first }
    /// Der Bildschirm, auf dem die Katze gerade ist. Wird er abgesteckt, geht's zurück zum Hauptbildschirm.
    private var screen: NSScreen? {
        if let screenID, let current = NSScreen.screens.first(where: { $0.displayID == screenID }) { return current }
        return primaryScreen
    }
    /// Wo die Pfoten stehen: auf der Dock-Oberkante – im Vollbild am unteren Bildschirmrand.
    private var ground: CGFloat {
        guard let screen else { return 0 }
        return isFullscreen ? screen.frame.minY : screen.visibleFrame.minY
    }
    private var catCenter: CGFloat { brain.x + CGFloat(Layout.canvasWidth) / 2 * scale }

    /// Angrenzender Bildschirm links bzw. rechts (nur wenn angeschlossen und erlaubt).
    private func neighbor(left: Bool) -> NSScreen? {
        guard multiScreen, NSScreen.screens.count > 1, let current = screen else { return nil }
        return NSScreen.screens.first { other in
            other != current
                && (left ? abs(other.frame.maxX - current.frame.minX) < 2 : abs(other.frame.minX - current.frame.maxX) < 2)
                && other.frame.maxY > current.frame.minY && other.frame.minY < current.frame.maxY
        }
    }

    /// Fensterebene knapp über dem Dock – damit sie sichtbar ins Körbchen steigen kann.
    private static let aboveDockLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    /// So groß ist ein Katzenpixel im Dock-Symbol (Symbolgröße aus den Dock-Einstellungen).
    private var basketCatScale: CGFloat { BasketArt.shared.scale(forTile: dockTileSize) }
    /// Wie groß das Pixelcat-Symbol im Dock gerade ist (bei vollem Dock kleiner als eingestellt)
    private var dockTileSize: CGFloat = 48

    private func resizeCatWindow(to drawScale: CGFloat) {
        let size = NSSize(width: CGFloat(Layout.canvasWidth) * drawScale,
                          height: CGFloat(Layout.canvasHeight) * drawScale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = drawScale
    }

    private func applyScale() {
        let size = NSSize(width: CGFloat(Layout.canvasWidth) * scale,
                          height: CGFloat(Layout.canvasHeight) * scale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = scale
        brain.scale = scale
        bowlWindow?.scale = scale
        lookoutWindow?.scale = scale
        ballWindow?.scale = scale
        birdWindow?.scale = scale
        bubble?.scale = scale
        updateBounds()
    }

    private func updateBounds() {
        guard let frame = screen?.frame else { return }
        brain.minX = frame.minX - CGFloat(Layout.margin) * scale
        brain.maxX = frame.maxX - CGFloat(Layout.canvasWidth - Layout.margin) * scale
        brain.neighborLeft = neighbor(left: true) != nil
        brain.neighborRight = neighbor(left: false) != nil
    }

    /// Sie ist zum Nachbarbildschirm hinausgelaufen: Bildschirm wechseln und dort hereinkommen.
    private func handleScreenSwitch() {
        guard let left = brain.screenSwitchRequest else { return }
        brain.screenSwitchRequest = nil
        if let next = neighbor(left: left) {
            screenID = next.displayID
            updateBounds()
            brain.dockY = ground
            brain.setPerches([])
            perchRefresh = 0
            brain.arriveFromSide(left: !left)
        } else {
            brain.arriveFromSide(left: left) // Nachbar inzwischen weg: einfach zurück
        }
    }

    private func removeBowl() {
        bowlWindow?.panel.orderOut(nil)
        bowlWindow = nil
        bowl = nil
        brain.bowl = nil
    }

    private func scheduleReminder() {
        nextReminder = breakReminders && !breakByActivity
            ? Date().addingTimeInterval(.random(in: reminderMinutes) * 60)
            : .distantFuture
        activity.reset()
    }

    /// Wie lange am Stück gearbeitet wird (für die Pausen-Erinnerung nach Aktivität)
    private var activity = ActivityTracker()
    private var lastActivityCheck = CACurrentMediaTime()

    /// Sekunden seit der letzten Eingabe (Tastatur, Maus, Trackpad) – ohne Sonderrechte, ohne Tasten mitzulesen
    private static var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Nach Aktivität: Ist genug am Stück gearbeitet worden, ist es Zeit für eine Pause.
    private func isActivityBreakDue() -> Bool {
        let now = CACurrentMediaTime()
        let dt = now - lastActivityCheck
        lastActivityCheck = now
        guard breakReminders, breakByActivity, pomodoro == nil, !silent, breakQuestionUntil == nil, breakEnds == nil else {
            activity.reset()
            return false
        }
        let idle = Self.secondsSinceInput
        activity.update(dt: dt, idle: idle)
        // Eine echte Pause (lange nichts getan): wieder der volle Abstand
        if idle >= activity.restAfter { snooze.rested() }
        return activity.activeSeconds >= snooze.minutes(base: activityMinutes) * 60
    }

    /// Pausen-Erinnerung: zur Mitte, strecken, Blase „Pause“ – während eines Timers als Pause im Timer.
    private func remindToTakeBreak(now: Date) {
        if let timer {
            // Wartet sie schon auf Streicheln, ist ohnehin Pause
            if !timer.finished { takeBreakDuringTimer(now: now) }
            scheduleReminder()
            return
        }
        guard breakQuestionUntil == nil, breakEnds == nil, brain.mode == .normal else { return }
        // Sie kommt in die Mitte und fragt: Pause? Daumen hoch oder runter
        pendingMeow = (.reminder, now)
        brain.callToCenter(visitLength: Self.breakQuestionTimeout + 30)
        let until = now.addingTimeInterval(Self.breakQuestionTimeout)
        breakQuestionUntil = until
        nextReminder = .distantFuture
        bubble?.remove()
        bubble = ThoughtBubble(text: L10n.s("Pause?", "Break?"), ends: until, scale: scale) { [weak self] yes in
            self?.answerBreak(yes, now: Date())
        }
    }

    /// „Jetzt fragen“ in den Einstellungen (und Selbsttest): die Pausenfrage gleich zeigen
    func askForBreakNow() {
        remindToTakeBreak(now: Date())
    }

    /// Angenommene Pause vorzeitig beenden (Selbsttest)
    func endBreak() {
        guard breakEnds != nil else { return }
        breakEnds = Date()
        updateBreak(now: Date())
    }

    /// Antwort auf die Pausenfrage
    func answerBreak(_ yes: Bool, now: Date) {
        guard breakQuestionUntil != nil else { return }
        breakQuestionUntil = nil
        bubble?.pop()
        if yes {
            beginBreak(now: now)
        } else {
            // Später: zurück zum Gewohnten; die nächste Erinnerung zählt neu (nach Aktivität früher)
            stats?.record { $0.breaksSkipped += 1 }
            brain.declineBreak()
            if breakByActivity { snooze.snoozed() }
            scheduleReminder()
        }
    }

    /// Pause beginnt (Daumen hoch oder „Pause machen“ im Menü): Sie freut sich und bleibt da, bis die Pause
    /// vorbei ist; oben läuft die Restzeit. Geführt macht sie danach Übungen vor.
    private func beginBreak(now: Date) {
        snooze.rested()
        activity.reset()
        nextReminder = .distantFuture
        stats?.record { $0.breaksTaken += 1 }
        breakEnds = now.addingTimeInterval(breakLength)
        brain.mode = .focusBreak
        brain.rejoice()
        if guidedBreaks { startGuided(length: breakLength, now: now) }
        updateStatusText(force: true)
    }

    /// Menü „Pause machen“: jederzeit eine Pause, ohne zu fragen
    func startBreakNow() {
        guard pomodoro == nil, timer == nil, breakEnds == nil else { return }
        if breakQuestionUntil != nil {
            answerBreak(true, now: Date()) // die offene Frage gleich mit beantworten
            return
        }
        cancelErrand()
        bubble?.pop()
        beginBreak(now: Date())
    }

    /// Pausenfrage ohne Antwort und angenommene Pause zu Ende bringen
    private func updateBreak(now: Date) {
        if let until = breakQuestionUntil, now >= until {
            if Self.secondsSinceInput >= 120 {
                // Niemand da: Das war ohnehin eine Pause
                breakQuestionUntil = nil
                bubble?.pop()
                snooze.rested()
                stats?.record { $0.breaksTaken += 1 }
                brain.declineBreak()
                scheduleReminder()
            } else {
                answerBreak(false, now: now) // weitergearbeitet: wie Daumen runter
            }
        }
        updateGuidedBreak(now: now)
        if let ends = breakEnds, now >= ends {
            breakEnds = nil
            stopGuided()
            brain.mode = .normal
            meow(.backToWork)
            scheduleReminder()
            updateStatusText(force: true)
        }
    }

    /// Geführte Pause: zur rechten Zeit die nächste Übung, darüber der Satz in der Gedankenblase
    private func updateGuidedBreak(now: Date) {
        guard var guided else { return }
        let index = guided.plan.stepIndex(at: now.timeIntervalSince(guided.start))
        guard index != guided.step else { return }
        guided.step = index
        self.guided = guided
        guard let index else { return }
        let step = guided.plan.steps[index]
        brain.exercise = step.exercise
        bubble?.remove()
        bubble = ThoughtBubble(text: step.text, ends: guided.start.addingTimeInterval(step.end), scale: scale)
    }

    /// Übungsfolge für eine Pause dieser Länge – nach kurzem Freuen geht es los
    private func startGuided(length: TimeInterval, now: Date) {
        guided = (GuidedBreak(length: length), now.addingTimeInterval(1.5), nil)
    }

    /// Übungen vorbei: Blase weg, normal weiter
    private func stopGuided() {
        guard guided != nil else { return }
        guided = nil
        brain.exercise = nil
        bubble?.pop()
    }

    /// Pomodoro, Timer oder Ruhemodus beginnt: Pausenfrage und Pause sind vorbei
    private func cancelBreak() {
        if breakQuestionUntil != nil {
            breakQuestionUntil = nil
            bubble?.pop()
        }
        if breakEnds != nil {
            breakEnds = nil
            bubble?.pop()
            if brain.mode == .focusBreak, pomodoro == nil, timer == nil { brain.mode = .normal }
        }
        guided = nil
        brain.exercise = nil
    }

    /// Aktive Arbeit für die Statistik: Zeit, in der in der letzten Minute etwas getippt oder geklickt wurde
    private func countActiveTime(now: Date) {
        let elapsed = now.timeIntervalSince(lastActiveCheck)
        lastActiveCheck = now
        if elapsed > 0, elapsed < 30, Self.secondsSinceInput < 60 {
            // Musik: Es läuft Ton, aber kein Call (und nicht gerade ihr eigenes Schnurren)
            let music = CallDetector.audioIsPlaying() && hiddenBecause == nil && !brain.isBeingPetted
                && !CallDetector.microphoneInUse()
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            stats?.record(at: now) {
                $0.activeSeconds += elapsed
                if music { $0.musicSeconds += elapsed }
                if let app, trackedApps.contains(app) { $0.apps[app, default: 0] += elapsed }
            }
        }
        stats?.save()
    }

    // MARK: Sensoren

    /// Videocall oder Bildschirmfreigabe → auf Streifzug (und erst 5 s nach dem Ende zurück).
    private func updateCallHiding(now: Date) {
        let reason = simulatedCall ?? (hideDuringCalls ? CallDetector.currentReason() : nil)
        if let reason {
            callEndedAt = nil
            setHidden(because: reason)
        } else if hiddenBecause != nil {
            if let ended = callEndedAt {
                if now.timeIntervalSince(ended) > 5 { setHidden(because: nil) }
            } else {
                callEndedAt = now
            }
        }
    }

    private func setHidden(because reason: CallDetector.Reason?) {
        guard (reason == nil) != (hiddenBecause == nil) || reason != hiddenBecause else { return }
        hiddenBecause = reason
        brain.suppressVisits = reason != nil || silent
        brain.roaming = userRoaming || reason != nil || silent
    }

    /// Fokus aktiv → leise und ruhig.
    private func updateFocus() {
        focusActive = respectFocus && focusMonitor.isFocused
        brain.calm = focusActive
    }

    /// Verkleidung an Feiertagen: Kürbis an Halloween, Weihnachtsmütze am 24./25.12., Partyhut am 31.12. und 1.1. –
    /// die gehen immer vor. Sonst je nach Tageszeit: Zylinder und Fliege nach Feierabend, Schlafmütze ab der
    /// Schlafenszeit, Schlafmaske auf der Stirn am Morgen.
    private func updateOutfit() {
        let outfit = outfitNow()
        if view.accessory !== outfit.hat { view.accessory = outfit.hat }
        view.accessoryDrop = outfit.drop
        if view.collar !== outfit.collar { view.collar = outfit.collar }
    }

    /// Was sie jetzt trägt: Feiertage zuerst, dann nach Tageszeit (auch für die Einrichtung)
    func outfitNow() -> Frames.Outfit {
        var hat: Sprite?, drop = 0, collar: Sprite?
        let day = Calendar.current.dateComponents([.month, .day], from: Date())
        if let outfitOverride {
            hat = outfitOverride
        } else {
            switch (day.month, day.day) {
            case (10, 31): hat = Frames.pumpkinHat
            case (12, 24), (12, 25): hat = Frames.santaHat
            case (12, 31), (1, 1): hat = Frames.partyHat
            default:
                // Während der Feierabend-Ankündigung (auch beim Vorführen) immer im Anzug
                let outfit = activeErrand?.errand.kind == .quittingTime ? .evening : outfitTimes.outfit(at: Date())
                switch outfit {
                case .evening: hat = Frames.topHat; collar = Frames.bowTie
                case .night: hat = Frames.nightCap
                case .morning: hat = Frames.sleepMask; drop = 2
                case nil: break
                }
            }
        }
        return Frames.Outfit(hat: hat, drop: drop, collar: collar)
    }

    /// Streicheln: Die Maus bewegt sich über der Katze, ohne zu klicken.
    /// Die Mausposition wird einfach abgefragt – dafür braucht es keine Sonderrechte.
    private func checkStroking() {
        let mouse = NSEvent.mouseLocation
        defer { lastMouse = mouse }
        let origin = panel.frame.origin
        let local = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        guard isVisible, panel.isVisible, NSEvent.pressedMouseButtons == 0, view.isCat(at: local) else {
            strokeDistance = 0
            return
        }
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        guard moved > 0.5 else { return }
        strokeDistance += moved
        if strokeDistance > 25 * scale / 3 || brain.isBeingPetted {
            brain.stroke()
        }
    }

    /// Mauszeiger für die Jagd: nur wenn er auf ihrem Bildschirm knapp über dem Dock ist.
    private func updatePointer(dt: Double) {
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - lastPointer.x, mouse.y - lastPointer.y) > 1 {
            pointerIdle = 0
        } else {
            pointerIdle += dt
        }
        lastPointer = mouse
        if let frame = screen?.frame, frame.contains(mouse),
           mouse.y >= ground, mouse.y <= ground + 110 * scale / 3 {
            brain.cursor = (mouse.x, mouse.y, pointerIdle)
        } else {
            brain.cursor = nil
        }
    }

    // MARK: Fensterkanten

    /// Normale Fenster (Ebene 0) in Bildschirmkoordinaten, von vorne nach hinten –
    /// ohne die eigenen und ohne die Vorschaubilder vom Stage Manager. Die meldet macOS als
    /// winzige Fenster der jeweiligen App; zu jedem gibt es ein gleich großes „WindowManager“-Fenster.
    private func visibleWindows() -> [(id: Int, rect: CGRect)] {
        // Innerhalb eines Takts nur einmal fragen (Vollbild und Kletterplätze teilen sich die Liste)
        if let cache = windowListCache, cache.time == lastTick { return cache.windows }
        let windows = readVisibleWindows()
        windowListCache = (lastTick, windows)
        return windows
    }
    private var windowListCache: (time: CFTimeInterval, windows: [(id: Int, rect: CGRect)])?

    private func readVisibleWindows() -> [(id: Int, rect: CGRect)] {
        guard let primary = primaryScreen,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windows: [(id: Int, rect: CGRect)] = []
        var thumbnails: [CGRect] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { continue }
            let rect = CGRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY,
                              width: bounds.width, height: bounds.height)
            if (info[kCGWindowOwnerName as String] as? String) == "WindowManager" {
                thumbnails.append(rect)
                continue
            }
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1
            else { continue }
            windows.append((id, rect))
        }
        return windows.filter { window in
            !thumbnails.contains { abs($0.minX - window.rect.minX) < 1.5 && abs($0.minY - window.rect.minY) < 1.5
                && abs($0.width - window.rect.width) < 1.5 && abs($0.height - window.rect.height) < 1.5 }
        }
    }

    /// Vollbild: volle Breite, reicht bis ganz unten und oben bis an den Rand
    /// (bei Macs mit Notch bleibt oben der Streifen neben der Notch frei).
    private func coversScreen(_ rect: CGRect, _ screen: NSScreen) -> Bool {
        let frame = screen.frame
        let topGap = max(screen.safeAreaInsets.top, 0) + 2
        return abs(rect.minX - frame.minX) < 2 && abs(rect.width - frame.width) < 2
            && abs(rect.minY - frame.minY) < 2 && rect.maxY >= frame.maxY - topGap
    }

    /// Sichtbare Oberkanten der offenen Fenster auf ihrem Bildschirm.
    /// Die Fensterpositionen liefert macOS ohne Sonderrechte (nur Titel wären geschützt).
    /// Ist ein Fenster im Vollbild oder in Split View, gibt es nichts zum Klettern.
    private func findPerches() -> [Perch] {
        guard let screen else { return [] }
        let frame = screen.frame
        var windows: [(id: Int, rect: CGRect)] = []
        for window in visibleWindows() {
            guard window.rect.width >= 120, window.rect.height >= 80, window.rect.intersects(frame) else { continue }
            if coversScreen(window.rect, screen) || window.rect.height >= frame.height - 2 { return [] }
            windows.append(window)
        }
        return Self.perches(on: windows, frame: frame, visible: screen.visibleFrame, scale: scale)
    }

    /// Die Fenster kommen von vorne nach hinten sortiert.
    static func perches(on windows: [(id: Int, rect: CGRect)], frame: CGRect, visible: CGRect,
                        scale: CGFloat) -> [Perch] {
        var perches: [Perch] = []
        for (index, window) in windows.enumerated() {
            let top = window.rect.maxY
            guard top < visible.maxY - 18 * scale, top > visible.minY + 20 * scale else { continue }
            // Was von der Oberkante nicht von Fenstern weiter vorne verdeckt ist
            var segments = [(max(window.rect.minX, frame.minX), min(window.rect.maxX, frame.maxX))]
            for front in windows[..<index]
            where front.rect.minY <= top + 8 * scale && front.rect.maxY >= top {
                segments = segments.flatMap { segment -> [(CGFloat, CGFloat)] in
                    let (a, b) = segment
                    guard front.rect.maxX > a, front.rect.minX < b else { return [segment] }
                    return [(a, front.rect.minX), (front.rect.maxX, b)].filter { $0.1 - $0.0 > 1 }
                }
            }
            guard let longest = segments.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }),
                  longest.1 - longest.0 >= 30 * scale
            else { continue }
            perches.append(Perch(id: window.id, y: top, minX: longest.0, maxX: longest.1,
                                 left: window.rect.minX, right: window.rect.maxX, bottom: window.rect.minY))
        }
        return perches
    }

    // MARK: Uhren

    private func updatePomodoro(now: Date) {
        guard var pomodoro, now >= pomodoro.ends else { return }
        switch pomodoro.stage {
        case .focus:
            // Fokuszeit vorbei: aufwachen, strecken, Pause machen
            stats?.record { $0.pomodoros += 1 }
            pomodoro = Pomodoro(stage: .rest, ends: now.addingTimeInterval(Double(breakMinutes) * 60))
            brain.mode = .focusBreak
            pendingMeow = (.breakStarts, now)
            // Geführt: Übungen statt der Blase „Pause“
            if guidedPomodoros {
                startGuided(length: pomodoro.ends.timeIntervalSince(now), now: now)
            } else {
                showBubble(until: pomodoro.ends)
            }
        case .rest:
            stopGuided()
            pomodoro = Pomodoro(stage: .focus, ends: now.addingTimeInterval(Double(focusMinutes) * 60))
            setPlaying(false)
            removeBowl()
            brain.mode = .focus
            meow(.backToWork)
        }
        self.pomodoro = pomodoro
    }

    private func updateStatusText(force: Bool = false) {
        let text = pomodoro?.label(at: Date())
            ?? timer.map { $0.finished ? "0:00" : countdownText(until: $0.ends, from: Date()) }
            ?? breakEnds.map { L10n.s("Pause", "Break") + " " + countdownText(until: $0, from: Date()) }
        if text != statusText || force {
            statusText = text
            onStatusChange?(text)
        }
    }

    // MARK: Vollbild und Körbchen

    /// Bedeckt ein Fenster den ganzen Bildschirm, läuft ein Programm im Vollbild (dann ist das Dock weg).
    private func detectFullscreen() -> Bool {
        guard let screen else { return false }
        return visibleWindows().contains { coversScreen($0.rect, screen) }
    }

    /// Dock-Symbol ein- oder ausblenden.
    private func updateDockPresence() {
        let policy: NSApplication.ActivationPolicy = basketInDock ? .regular : .accessory
        let changes = NSApp.activationPolicy() != policy
        if basketInDock {
            NSApp.setActivationPolicy(.regular)
            NSApp.dockTile.contentView = basketTile
        } else {
            NSApp.dockTile.contentView = nil
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.dockTile.display()
        basketRefresh = 0
        // Beim Wechsel gibt macOS den Fokus an ein anderes Programm ab (womöglich eins im Vollbild).
        // Ist gerade ein Fenster von Pixelcat offen (Einstellungen, Einrichtung), holt es ihn zurück.
        if changes, let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Der Bildschirm mit dem Dock (es kann auf jeden Bildschirm wandern)
    private var dockScreen: NSScreen? { DockLocator.dockScreen() }

    /// Kann sie gerade ins Körbchen steigen? Günstig – läuft jede Sekunde. Wo genau das Körbchen sitzt,
    /// wird erst gelesen, wenn sie es braucht (`locateBasket`).
    private func updateBasketAvailability() {
        guard basketInDock, let dock = dockScreen else {
            brain.useBasket = false
            brain.dockSideIsLeft = nil
            return
        }
        let edge = DockLocator.edge
        // Ohne Bedienungshilfen vor dem Herausklettern kurz warten, bis das Dock eine Verschiebung gespeichert hat
        brain.emergeDelay = DockLocator.isTrusted ? 0 : 2
        // Steht das Dock seitlich, geht sie zu dieser Seite hinaus
        brain.dockSideIsLeft = edge == .left ? true : edge == .right ? false : nil
        // Hineinsteigen geht nur, wenn das Dock unten auf ihrem Bildschirm zu sehen ist
        // (nicht bei automatisch ausgeblendetem Dock oder im Vollbild)
        let dockHeight = dock.visibleFrame.minY - dock.frame.minY
        brain.useBasket = edge == .bottom && dockHeight > 20 && screen?.displayID == dock.displayID && !isFullscreen
    }

    /// Genau jetzt nachsehen, wo das Körbchen im Dock sitzt und wie groß das Symbol ist.
    private func locateBasket() {
        guard basketInDock, let dock = dockScreen else { return }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Pixelcat"
        let tile = DockLocator.basketTile(appName: name, screen: dock)
        brain.basketX = tile?.center.x
        if let tile {
            dockTileSize = tile.size
            // Genau dort, wo die Katze im Dock-Symbol liegt
            brain.basketFloorY = tile.center.y + BasketArt.shared.catBottom(fromCenterOfTile: tile.size)
        }
    }

    /// Dock-Symbol: leeres Körbchen – oder die Katze schläft darin (atmet, hebt ab und zu den Schwanz).
    private func updateBasketTile(dt: Double) {
        guard basketInDock, !calibrating else { return }
        let inside = brain.isInBasketPicture
        // Frisch hineingelegt: ausgeatmet und Schwanz unten anfangen – wie das letzte Bild der Katze davor
        tileClock = inside && !basketTile.catInside ? 0 : tileClock + dt
        let breathIn = Int(tileClock / 1.1) % 2 == 1
        let tailUp = tileClock.truncatingRemainder(dividingBy: 6.5) > 5.4
        if basketTile.catInside != inside || basketTile.breathIn != breathIn || basketTile.tailUp != tailUp
            || basketTile.coat != coat {
            basketTile.catInside = inside
            basketTile.breathIn = breathIn
            basketTile.tailUp = tailUp
            basketTile.coat = coat
            NSApp.dockTile.display()
        }
    }

    // MARK: Nachmessen (Start mit PIXELCAT_CALIBRATE=1)

    private var calibrating = false
    private var calibrationPanel: NSPanel?

    /// Zum Nachmessen, ob die Animation genau auf dem Dock-Symbol liegt: erst zeigt nur das Symbol die schlafende
    /// Katze (A), dann ist das Symbol leer und darüber liegt das letzte Bild der Animation – genau so berechnet
    /// wie beim Hineinlegen (B). Zwei Bildschirmfotos zeigen jede Abweichung.
    func runCalibration() {
        calibrating = true
        hide()
        basketTile.blank = false
        basketTile.catInside = true
        basketTile.breathIn = false
        basketTile.tailUp = false
        basketTile.coat = coat
        NSApp.dockTile.display()
        print("Kalibrierung A: Symbol mit Katze"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            MainActor.assumeIsolated { self?.calibrationOverlay() }
        }
    }

    private func calibrationOverlay() {
        locateBasket()
        guard let basketX = brain.basketX, let floor = brain.basketFloorY else {
            print("Kalibrierung: Korb nicht gefunden"); fflush(stdout)
            return
        }
        let drawScale = basketCatScale
        let size = NSSize(width: CGFloat(Layout.canvasWidth) * drawScale, height: CGFloat(Layout.canvasHeight) * drawScale)
        // wie in updateCatWindow: Fenster auf ganze Bildschirmpixel, Rand relativ dazu
        let origin = NSPoint(x: pixelRound(basketX - CGFloat(Layout.canvasWidth) / 2 * drawScale), y: pixelRound(floor))
        let art = BasketArt.shared
        let catView = CatView(frame: NSRect(origin: .zero, size: size))
        catView.scale = drawScale
        catView.coat = coat
        catView.look = CatLook(sprite: Frames.sleepA, facingRight: true)
        catView.basketFront = CGPoint(x: (basketX - CGFloat(art.width) / 2 * drawScale - origin.x) / drawScale,
                                      y: (floor - CGFloat(art.catY) * drawScale - origin.y) / drawScale)
        let panel = makeOverlayPanel()
        panel.level = Self.aboveDockLevel
        panel.ignoresMouseEvents = true
        panel.contentView = catView
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        calibrationPanel = panel
        basketTile.blank = true
        NSApp.dockTile.display()
        let reserved = (dockScreen.map { $0.visibleFrame.minY - $0.frame.minY }) ?? 0
        print("Kalibrierung B: Schätzung Mitte x=\(basketX) y=\(floor - BasketArt.shared.catBottom(fromCenterOfTile: dockTileSize)) "
              + "Kachel=\(dockTileSize) Dockhöhe=\(reserved)")
        fflush(stdout)
        // C: beides weg – der Hintergrund allein
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                self?.calibrationPanel?.orderOut(nil)
                print("Kalibrierung C: nur Hintergrund"); fflush(stdout)
            }
        }
    }

    /// Auf ganze Bildschirmpixel runden (auf Retina-Bildschirmen halbe Punkte)
    private func pixelRound(_ value: CGFloat) -> CGFloat {
        let factor = (screen ?? primaryScreen)?.backingScaleFactor ?? 1
        return (value * factor).rounded() / factor
    }

    // MARK: Selbsttest

    /// Was gerade los ist – für den Selbsttest (Start mit --selftest)
    struct Snapshot {
        var phase: String
        var catCenter: CGFloat
        var catFrame: NSRect?
        var isAway: Bool
        var errand: ErrandKind?
        var bowl: (x: CGFloat, water: Bool, food: Double, frame: NSRect?)?
        var lookout: (x: CGFloat, frame: NSRect?, alpha: CGFloat, catAbove: Bool)?
        var bubble: (frame: NSRect?, popping: Bool)?
        var hat: String?
        var scale: CGFloat
        var idleSeconds: Double
        var queued: [ErrandKind]
        var meows: Int
    }

    func snapshot() -> Snapshot {
        var hat: String?
        switch view.accessory {
        case nil: hat = nil
        case let a where a === Frames.topHat: hat = "Zylinder"
        case let a where a === Frames.nightCap: hat = "Schlafmütze"
        case let a where a === Frames.sleepMask: hat = "Schlafmaske"
        default: hat = "Feiertagshut"
        }
        var catAbove = false
        if let lookoutWindow, panel.isVisible, lookoutWindow.panel.isVisible {
            // Reihenfolge der eigenen Fenster: vorne zuerst
            let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { $0[kCGWindowNumber as String] as? Int }
            if let cat = order.firstIndex(of: panel.windowNumber), let window = order.firstIndex(of: lookoutWindow.panel.windowNumber) {
                catAbove = cat < window
            }
        }
        return Snapshot(
            phase: "\(brain.phase)", catCenter: catCenter, catFrame: panel.isVisible ? panel.frame : nil,
            isAway: brain.isAway, errand: activeErrand?.errand.kind,
            bowl: bowl.map { ($0.x, $0.water, $0.food, bowlWindow?.panel.isVisible == true ? bowlWindow?.panel.frame : nil) },
            lookout: lookoutWindow.map { (lookoutX, $0.panel.isVisible ? $0.panel.frame : nil,
                                         $0.panel.alphaValue, catAbove) },
            bubble: bubble.map { ($0.visibleFrame, $0.isPopping) },
            hat: hat, scale: scale, idleSeconds: Self.secondsSinceInput, queued: errands.queuedKinds, meows: meowCount)
    }

    /// Selbsttest: Aufgaben vorübergehend setzen (die Einstellungen bleiben unberührt)
    /// (nil = wieder die eigenen Aufgaben)
    func selfTestTasks(_ items: [TaskItem]?) {
        if let items {
            errands.configureTasks(items, enabled: false, now: Date())
        } else {
            configureTasks()
        }
    }

    /// Selbsttest: einen Videocall bzw. eine Bildschirmfreigabe nachspielen (nil = vorbei)
    var simulatedCall: CallDetector.Reason? {
        didSet { sensorRefresh = 0 }
    }

    /// Wird gerade der Bildschirm geteilt (oder im Selbsttest so getan)?
    private var screenIsShared: Bool {
        simulatedCall.map { $0 == .screenSharing } ?? CallDetector.screenIsShared()
    }

    /// Selbsttest: wie ein Klick auf die Blase
    func selfTestPopBubble() {
        bubble?.pop()
    }

    // MARK: Kleine Erinnerungen

    /// Aus den Einstellungen („Jetzt zeigen“): gleich als Nächstes zeigen.
    func showErrandNow(_ kind: ErrandKind) {
        if kind == .bird { birdStaysUntil = Date().addingTimeInterval(25) }
        errands.requestNow(kind)
        nextErrandAllowed = .distantPast
    }

    /// Aus dem Aufgabenfenster: genau diese Aufgabe gleich zeigen.
    func showTaskNow(_ id: UUID) {
        errands.requestTask(id)
        nextErrandAllowed = .distantPast
    }

    /// Beim Start holt sie verpasste Aufgaben nach, bei späteren Änderungen nicht
    private func configureTasks() {
        errands.configureTasks(taskList, enabled: tasksEnabled, now: Date(), launch: !settingsApplied)
    }

    /// Ein Spruch: einer der eigenen oder, ohne eigene, einer von ihr – nicht zweimal hintereinander derselbe
    private func nextSaying(now: Date) -> String {
        var sayings = motivationSayings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if sayings.isEmpty { sayings = Self.ownSayings(morning: Calendar.current.component(.hour, from: now) < 12) }
        let choices = sayings.count > 1 ? sayings.filter { $0 != lastSaying } : sayings
        let saying = choices.randomElement() ?? ""
        lastSaying = saying
        return saying
    }

    /// Ihre eigenen Sprüche, morgens zum Loslegen, später zum Durchhalten
    static func ownSayings(morning: Bool) -> [String] {
        morning
            ? [L10n.s("Heute wird ein guter Tag!", "Today is going to be great!"),
               L10n.s("Du schaffst das!", "You've got this!"),
               L10n.s("Ein Schritt nach dem anderen.", "One step at a time."),
               L10n.s("Auf geht's!", "Let's go!")]
            : [L10n.s("Fast geschafft, weiter so!", "Almost there, keep going!"),
               L10n.s("Stolz auf dich!", "Proud of you!"),
               L10n.s("Das war richtig gut heute.", "You did great today."),
               L10n.s("Du schaffst das!", "You've got this!")]
    }

    /// Fällige Erinnerungen einsammeln; läuft keine, die nächste starten – sobald die Katze frei ist.
    private func updateErrands(now: Date) {
        errands.collectDue(now: now)
        // Ruhemodus: nichts erinnern (verpasste Erinnerungen holt sie danach nicht nach)
        if silent {
            errands.clearQueue()
            return
        }
        if let active = activeErrand {
            if errandFinished(active.errand, since: active.since, now: now) { finishErrand(now: now) }
            return
        }
        guard now >= nextErrandAllowed, canRunErrand else { return }
        // Im Videocall nur Aufgaben (falls so eingestellt) – und nie, während der Bildschirm geteilt wird
        let allowed: (ErrandKind) -> Bool = hiddenBecause == nil ? { _ in true }
            : { [tasksDuringCalls, screenIsShared] kind in kind == .task && tasksDuringCalls && !screenIsShared }
        guard let errand = errands.popNext(where: allowed) else { return }
        startErrand(errand, now: now)
    }

    /// Frei für eine Erinnerung: sichtbar, kein Fokus/Timer, keine Pause, nichts zu fressen oder zu spielen,
    /// nicht gerade beim Hinein- oder Herausklettern. (Was im Videocall erlaubt ist, entscheidet `updateErrands`.)
    private var canRunErrand: Bool {
        isVisible && brain.mode == .normal && pomodoro == nil && timer == nil
            && bubble == nil && bowl == nil && ball == nil && !brain.isAboveDock && !brain.awaitingAcknowledgement
    }

    /// Im Videocall ist die Katze versteckt: Dann steht die Aufgaben-Blase über dem Katzenkorb im Dock
    /// bzw. unten rechts am Bildschirm.
    private var bubbleAnchorWithoutCat: CGPoint? {
        guard isVisible, let frame = (dockScreen ?? screen)?.frame else { return nil }
        if basketInDock, brain.useBasket || brain.basketX != nil, let basketX = brain.basketX {
            return CGPoint(x: basketX, y: ground)
        }
        return CGPoint(x: frame.maxX - 70 * scale / 3, y: ground + 2 * scale)
    }

    private func startErrand(_ errand: Errand, now: Date) {
        activeErrand = (errand, now)
        switch errand.kind {
        case .drink:
            // Napf hinstellen und fragen: Trinkst du mit? Daumen hoch zählt in der Statistik
            placeBowl(water: true)
            showErrandBubble(L10n.s("Trinken?", "Drink?"), for: 4 * 60) { [weak self] yes in
                self?.answerDrink(yes)
            }
            meow(.reminder)
        case .lookout:
            placeLookout()
            meow(.reminder)
        case .quittingTime:
            // Mit Schlafmütze in die Mitte, strecken und „Feierabend“ denken
            showErrandBubble(L10n.s("Feierabend", "Off work"), for: 60)
            updateOutfit()
            if soundsAllowed { pendingMeow = (.breakStarts, now) }
            brain.callToCenter(visitLength: 75)
            return
        case .motivation:
            // Eine Gedankenblase mit dem Spruch – im Streifzug oder Körbchen kommt sie dafür herein
            showErrandBubble(nextSaying(now: now), for: 40)
            meow(.reminder)
            if brain.isOutAndAbout { brain.startErrandVisit(for: 5 * 60) } else { brain.noticeSomething() }
            return
        case .bird:
            releaseBird()
            // Aus dem Streifzug oder Körbchen kommt sie herein und schaut sich erst etwas verlegen um
            if brain.isOutAndAbout {
                brain.peeksLeft = 3
                brain.startErrandVisit(for: 3 * 60 * 60)
            } else {
                brain.peeksLeft = 1
                brain.noticeSomething()
            }
            return
        case .task:
            // Nur die Blase – sie wird dafür nicht geweckt; im Streifzug oder Körbchen kommt sie herein
            // (im Videocall bleibt sie versteckt, die Blase steht dann über dem Korb im Dock)
            if hiddenBecause != nil, basketInDock { locateBasket() }
            showErrandBubble(errand.text ?? "", for: 35)
            if meowForTasks { meow(.reminder) } // (im Videocall nie – dann ist sie still)
            if brain.isOutAndAbout { brain.startErrandVisit(for: 5 * 60) }
            return
        }
        // Im Streifzug oder im Körbchen kommt sie dafür herein, sonst wird sie aufmerksam
        if brain.isOutAndAbout {
            brain.startErrandVisit(for: 5 * 60)
        } else {
            brain.noticeSomething()
        }
    }

    private func errandFinished(_ errand: Errand, since: Date, now: Date) -> Bool {
        switch errand.kind {
        case .drink:
            // Fertig getrunken: Die Blase platzt; erledigt, sobald der Napf weggeräumt ist
            if let bowl, bowl.water, bowl.food <= 0 { errandBubble?.pop() }
            return bowl?.water != true || now.timeIntervalSince(since) > 4 * 60
        case .lookout:
            return lookoutWindow == nil || now.timeIntervalSince(since) > 4 * 60
        case .quittingTime, .task, .motivation:
            return errandBubble == nil
        case .bird:
            // Jemand ist zurück: Der Vogel fliegt davon, erledigt ist es, wenn er weg ist
            if let bird, !bird.isLeaving, now >= birdStaysUntil, Self.secondsSinceInput < 2 { bird.leave() }
            return bird == nil
        }
    }

    private func finishErrand(now: Date) {
        if activeErrand?.errand.kind == .bird {
            removeBird()
            // Im Streifzug oder Körbchen zügig zurück
            if brain.roaming { brain.hurryOut = true }
        }
        if let bowl, bowl.water { removeBowl() }
        removeLookout()
        errandBubble?.pop()
        brain.endErrandVisit()
        activeErrand = nil
        nextErrandAllowed = now.addingTimeInterval(15)
    }

    // MARK: Vogel

    /// Lange niemand am Rechner? Dann kommt ein Vogel vorbei – einmal pro Abwesenheit.
    private func checkForBird(now: Date) {
        let idle = Self.secondsSinceInput
        if idle < 5 { birdDoneForIdle = false }
        guard let minutes = birdAfterMinutes, !silent, !birdDoneForIdle, idle >= Double(minutes) * 60, activeErrand == nil,
              canRunErrand, hiddenBecause == nil, !brain.calm else { return }
        birdDoneForIdle = true
        startErrand(Errand(kind: .bird), now: now)
    }

    /// Der Vogel fliegt von einer Seite herein, hoch oben
    private func releaseBird() {
        guard bird == nil, let frame = screen?.frame else { return }
        let fromLeft = Bool.random()
        let bird = Bird(x: fromLeft ? frame.minX - 30 : frame.maxX + 30, y: ground + 150 * scale / 3)
        let window = PropWindow(columns: BirdArt.width, rows: BirdArt.height, scale: scale)
        window.view.colors = BirdArt.colors
        window.view.sprite = BirdArt.up
        self.bird = bird
        birdWindow = window
        brain.bird = bird
        if isVisible { window.panel.orderFrontRegardless() }
    }

    private func removeBird() {
        birdWindow?.panel.orderOut(nil)
        birdWindow = nil
        bird = nil
        brain.bird = nil
        brain.peeksLeft = 0
    }

    /// Pomodoro oder Timer beginnt: laufende Erinnerung abbrechen (Napf und Fenster weg)
    private func cancelErrand() {
        guard activeErrand != nil else { return }
        finishErrand(now: Date())
    }

    /// Augenpause: Fenster aufploppen lassen – irgendwo in der Mitte, nicht direkt bei der Katze.
    private func placeLookout() {
        guard let frame = screen?.frame else { return }
        var x = frame.midX
        for _ in 0..<10 {
            x = .random(in: frame.minX + frame.width * 0.2...frame.maxX - frame.width * 0.2)
            if abs(x - catCenter) > 120 { break }
        }
        removeLookout()
        let window = PropWindow(columns: LookoutArt.width, rows: LookoutArt.height, scale: scale)
        window.view.colors = LookoutArt.colors
        window.view.sprite = LookoutArt.frames[0]
        window.panel.alphaValue = 0
        lookoutWindow = window
        lookoutX = x
        lookoutAppear = 0
        lookoutLeaving = false
        window.place(centerX: x, bottom: ground)
        if isVisible {
            window.panel.orderFrontRegardless()
            if panel.isVisible { panel.order(.above, relativeTo: window.panel.windowNumber) }
        }
        brain.lookout = x
        brain.onLookoutDone = { [weak self] in self?.lookoutLeaving = true }
    }

    /// Einblenden mit kleinem Federn, Wolke ziehen lassen, nach dem Hinausschauen ausblenden.
    private func updateLookoutWindow(dt: Double) {
        guard let window = lookoutWindow else { return }
        if lookoutLeaving {
            lookoutAppear -= dt / 0.6
            if lookoutAppear <= 0 { return removeLookout() }
        } else {
            lookoutAppear = min(1, lookoutAppear + dt / 0.45)
        }
        let t = lookoutAppear
        // Etwas über die volle Größe hinaus und zurück („ploppt auf“)
        let pop = lookoutLeaving ? 0.85 + 0.15 * t : 1 + 0.12 * sin(t * .pi) - 0.4 * (1 - t) * (1 - t)
        let size = scale * CGFloat(pop)
        if abs(window.scale - size) > 0.01 { window.scale = size }
        window.panel.alphaValue = CGFloat(min(1, t * 1.6))
        window.view.sprite = LookoutArt.frames[Int(CACurrentMediaTime() / 1.6) % LookoutArt.frames.count]
        window.place(centerX: lookoutX, bottom: ground)
    }

    private func removeLookout() {
        lookoutWindow?.panel.orderOut(nil)
        lookoutWindow = nil
        lookoutLeaving = false
        brain.lookout = nil
    }

    /// Antwort auf „Trinken?“: Daumen hoch – sie freut sich und trinkt mit; runter – der Napf kommt weg
    func answerDrink(_ yes: Bool) {
        guard activeErrand?.errand.kind == .drink else { return }
        errandBubble?.pop()
        if yes {
            stats?.record { $0.drinks += 1 }
            brain.rejoice()
        } else {
            stats?.record { $0.drinksSkipped += 1 }
            removeBowl()
        }
    }

    private func showErrandBubble(_ text: String, for seconds: TimeInterval, onChoice: ((Bool) -> Void)? = nil) {
        bubble?.remove()
        let new = ThoughtBubble(text: text, ends: Date().addingTimeInterval(seconds), scale: scale, onChoice: onChoice)
        bubble = new
        errandBubble = new
    }

    // MARK: Gedankenblase

    /// Blase „Pause“ über der Katze zeigen, bis die Pause vorbei ist (eine eventuelle alte verschwindet).
    private func showBubble(until end: Date) {
        bubble?.remove()
        bubble = ThoughtBubble(text: L10n.s("Pause", "Break"), ends: end, scale: scale)
    }

    /// Blase über dem Kopf halten; am Pausenende platzt sie, danach wird sie weggeräumt.
    private func updateBubble(dt: Double, now: Date) {
        guard let bubble else { return }
        if !bubble.isPopping, now >= bubble.ends { bubble.pop() }
        var head: CGPoint?
        if isVisible, !brain.isAway, let look = view.look {
            // Kopfmitte zwischen den Ohren, darüber ggf. noch der Feiertagshut
            let sprite = look.sprite
            let column = CGFloat(look.drawX) + CGFloat(sprite.earAnchor?.center ?? sprite.width / 2) + 0.5
            let canvasX = look.facingRight ? column : CGFloat(Layout.canvasWidth) - column
            let hat = sprite.earAnchor != nil ? max(0, (view.accessory?.height ?? 0) - 2 - view.accessoryDrop) : 0
            head = CGPoint(x: brain.x.rounded() + canvasX * scale,
                           y: brain.y.rounded() + CGFloat(look.hop + sprite.height + hat + 1) * scale)
        } else if hiddenBecause != nil, bubble === errandBubble {
            head = bubbleAnchorWithoutCat
        }
        bubble.update(dt: dt, head: head)
        if bubble.isGone {
            bubble.remove()
            self.bubble = nil
        }
    }

    // MARK: Takt

    /// Wie oft der Takt läuft: flüssig bei Bewegung, sparsam in Ruhe, fast gar nicht, wenn sie weg ist.
    /// So selten wie möglich aufwachen: flüssig nur, wenn sich etwas bewegt.
    private func adjustTickRate() {
        // Die Maus zählt nur, wenn sie sich gerade bei der Katze bewegt (zum Streicheln)
        let mouseNearCat = pointerIdle < 1 && panel.isVisible
            && panel.frame.insetBy(dx: -100, dy: -100).contains(NSEvent.mouseLocation)
        let interval: TimeInterval
        if bird != nil {
            interval = 1.0 / 30 // der Vogel fliegt flüssig, auch während sie noch im Korb liegt
        } else if !isVisible || brain.isAway {
            interval = 0.5
        } else if brain.needsSmoothMotion || ball != nil || mouseNearCat || brain.isBeingPetted
                    || bubble?.isPopping == true || (lookoutWindow != nil && (lookoutAppear < 1 || lookoutLeaving)) {
            interval = 1.0 / 30
        } else if brain.phase == .sleeping {
            interval = 1.0 / 4 // im Schlaf nur Atmen und Schwanzspitze
        } else {
            interval = 1.0 / 8
        }
        if interval != tickInterval {
            tickInterval = interval
            restartTicker()
        }
    }

    private func restartTicker() {
        ticker?.invalidate()
        let ticker = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.tolerance = tickInterval * 0.2
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.6)
        lastTick = now
        let date = Date()

        if screenID != nil, screen?.displayID != screenID { screenID = nil } // Bildschirm abgesteckt
        // Wer im Körbchen liegt, kommt beim Hauptbildschirm (mit dem Dock) wieder heraus
        if basketInDock, brain.isAway, let dock = dockScreen, screen?.displayID != dock.displayID {
            screenID = dock.displayID == primaryScreen?.displayID ? nil : dock.displayID
        }
        // Die Fensterliste ist der teuerste Blick auf den Bildschirm: in Ruhe seltener
        let calm = brain.isAway || !brain.needsSmoothMotion
        fullscreenRefresh -= dt
        if fullscreenRefresh <= 0 {
            fullscreenRefresh = brain.isAway ? 2 : calm ? 1 : 0.5
            isFullscreen = detectFullscreen()
        }
        basketRefresh -= dt
        if basketRefresh <= 0 {
            basketRefresh = 1
            updateBasketAvailability()
        }
        updateBounds()
        brain.dockY = ground
        perchRefresh -= dt
        if perchRefresh <= 0, brain.climbingEnabled || brain.isOnWindow {
            // Oben auf einem Fenster oder beim Klettern genau verfolgen, unten auf dem Dock reicht seltener
            perchRefresh = brain.isOnWindow || !calm ? 0.2 : 1
            brain.setPerches(findPerches())
        }
        sensorRefresh -= dt
        if sensorRefresh <= 0 {
            sensorRefresh = 2
            updateCallHiding(now: date)
            updateFocus()
            updateOutfit()
            if isActivityBreakDue() { remindToTakeBreak(now: date) }
            checkForBird(now: date)
            countActiveTime(now: date)
            // Aufgaben-Blase im Videocall: Beginnt jemand, den Bildschirm zu teilen, sofort weg
            if hiddenBecause != nil, activeErrand?.errand.kind == .task, screenIsShared { errandBubble?.pop() }
        }
        updatePomodoro(now: date)
        updateTimer(now: date)
        updateBreak(now: date)
        updateStatusText()
        if pomodoro == nil, !silent, date >= nextReminder {
            remindToTakeBreak(now: date)
        }

        updateErrands(now: date)

        checkStroking()
        updatePointer(dt: dt)
        brain.update(dt: dt)
        handleScreenSwitch()
        purr.update(dt: dt, active: purring && soundsAllowed && isVisible && brain.isBeingPetted)

        if let ball, let frame = screen?.visibleFrame {
            let radius = 4 * scale
            ball.update(dt: dt, minX: frame.minX + radius, maxX: frame.maxX - radius,
                        maxY: frame.height - 9 * scale, unit: scale / 3)
        }
        if let bird, let frame = screen?.frame {
            bird.update(dt: dt, minX: frame.minX, maxX: frame.maxX, ground: ground, top: frame.maxY, unit: scale / 3)
            if bird.isGone {
                removeBird()
            } else if let birdWindow {
                // Auch während sie noch im Korb liegt oder hereinkommt
                birdWindow.view.sprite = BirdArt.frame(bird)
                birdWindow.place(centerX: bird.x, bottom: bird.y)
            }
        }
        if let bowl, bowl.food <= 0, brain.phase != .eating, brain.phase != .drinking {
            bowl.emptyFor += dt
            if bowl.emptyFor > 12 { removeBowl() }
        }
        defer {
            updateBubble(dt: dt, now: date)
            updateBasketTile(dt: dt)
            adjustTickRate()
        }

        // Draußen auf Streifzug: Fenster weg (sonst tauchte es auf einem Nachbarbildschirm auf),
        // liegengebliebenes Spielzeug wird weggeräumt
        if brain.isAway {
            if ball != nil { setPlaying(false) }
            // (der Wassernapf einer Erinnerung bleibt – sie kommt ja gleich)
            if bowl != nil, activeErrand == nil { removeBowl() }
            updateBowlWindow()
            updateLookoutWindow(dt: dt)
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        guard isVisible else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }

        // visibleFrame endet unten an der Oberkante des Docks – genau da läuft die Katze
        // Beim Hinein- und Heraussteigen steht sie vor dem Dock und schrumpft bzw. wächst
        // zwischen normaler Größe und der Größe im Dock-Symbol
        let drawScale = brain.isAboveDock ? scale + (basketCatScale - scale) * brain.basketShrink : scale
        if view.scale != drawScale { resizeCatWindow(to: drawScale) }
        let level: NSWindow.Level = brain.isAboveDock ? Self.aboveDockLevel : .floating
        if panel.level != level { panel.level = level }
        let half = CGFloat(Layout.canvasWidth) / 2
        let origin = NSPoint(x: pixelRound(brain.x + half * scale - half * drawScale), y: pixelRound(brain.y))
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        // Im Körbchen: dessen vorderen Rand vor die Katze legen – genau wie im Dock-Symbol
        var front: CGPoint?
        if brain.isAboveDock, brain.basketShrink >= 1, let basketX = brain.basketX, let floor = brain.basketFloorY {
            let art = BasketArt.shared
            front = CGPoint(x: (basketX - CGFloat(art.width) / 2 * drawScale - origin.x) / drawScale,
                            y: (floor - CGFloat(art.catY) * drawScale - origin.y) / drawScale)
        }
        if view.basketFront != front { view.basketFront = front }
        let look = brain.look
        if look != view.look { view.look = look }

        updateBowlWindow()
        updateLookoutWindow(dt: dt)
        if let ball, let ballWindow {
            ballWindow.view.sprite = Int(ball.rolled / (3 * scale)) % 2 == 0 ? Frames.yarnA : Frames.yarnB
            ballWindow.place(centerX: ball.x, bottom: ground + ball.y)
        }
    }
}
