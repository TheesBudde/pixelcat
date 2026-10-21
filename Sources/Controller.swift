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
        panel.setFrameOrigin(NSPoint(x: (centerX - panel.frame.width / 2).rounded(), y: bottom.rounded()))
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
    private var ballWindow: PropWindow?
    private var dragOffset = CGPoint.zero
    private var lastDrag: (point: NSPoint, time: CFTimeInterval)?
    private var dragVelocity = CGVector.zero

    private(set) var pomodoro: Pomodoro?
    private(set) var timer: CatTimer?
    private var nextReminder = Date.distantFuture
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
    /// Gedankenblase „Pause“ über der Katze, solange sie an eine Pause erinnert
    private var bubble: ThoughtBubble?

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
    var breakLength: TimeInterval {
        get { brain.breakVisitLength }
        set { brain.breakVisitLength = newValue }
    }

    /// Streifzug: Die Katze ist draußen und kommt nur zu Pausen vorbei.
    var roaming: Bool {
        get { userRoaming }
        set {
            userRoaming = newValue
            brain.roaming = userRoaming || hiddenBecause != nil
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
        breakLength = TimeInterval(settings.breakLength * 60)
        if settings.awayMode != userRoaming { roaming = settings.awayMode }
        updateStatusText(force: true)
    }

    var isPlaying: Bool { ball != nil }
    /// Im Streifzug unterwegs (kein Pausenbesuch) – dann gibt es nichts zu füttern oder zu spielen
    var isOutAndAbout: Bool { brain.isOutAndAbout }
    /// Die Katze schläft fest (Pomodoro-Fokus oder laufender Timer).
    var isInFocus: Bool { brain.mode == .focus }
    private var soundsAllowed: Bool { sounds && !focusActive && hiddenBecause == nil }

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
            if soundsAllowed, Date().timeIntervalSince(meow.since) < 120 { Meow.play(meow.kind) }
        }
        // Gestreichelt oder angeklickt: abgelaufener Timer ist erledigt
        brain.onAcknowledged = { [weak self] in
            guard let self, timer?.finished == true else { return }
            timer = nil
            scheduleReminder()
            updateStatusText()
        }
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
        if !brain.isAway { panel.orderFrontRegardless() }
        ballWindow?.panel.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        bowlWindow?.panel.orderOut(nil)
        ballWindow?.panel.orderOut(nil)
    }

    // MARK: Menüaktionen

    func startle() { brain.startle() }
    func goToSleep() { brain.goToSleep() }

    func feed() {
        guard let frame = screen?.frame, !isInFocus, !brain.isAway else { return }
        if let bowl, bowl.food > 0 { return }
        // Irgendwo ins mittlere Drittel bis Fünftel, nicht direkt unter die Katze
        var x = frame.minX
        for _ in 0..<10 {
            x = .random(in: frame.minX + frame.width * 0.15...frame.maxX - frame.width * 0.15)
            if abs(x - catCenter) > 150 { break }
        }
        removeBowl()
        let bowl = Bowl(x: x)
        let window = PropWindow(columns: 14, rows: 6, scale: scale)
        self.bowl = bowl
        bowlWindow = window
        brain.bowl = bowl
        if isVisible {
            window.panel.orderFrontRegardless()
            panel.orderFrontRegardless()
        }
        brain.noticeSomething()
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
        pomodoro = Pomodoro(stage: .focus, ends: Date().addingTimeInterval(Double(focusMinutes) * 60))
        setPlaying(false)
        removeBowl()
        brain.mode = .focus
        updateStatusText()
    }

    func stopPomodoro() {
        bubble?.pop()
        pomodoro = nil
        brain.mode = .normal
        scheduleReminder()
        updateStatusText()
    }

    func startTimer(minutes: Double) {
        guard pomodoro == nil else { return }
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
    private var basketCatScale: CGFloat {
        let tile = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 0
        return CGFloat(tile > 0 ? tile : 48) * 0.94 / CGFloat(BasketArt.shared.width)
    }

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
        ballWindow?.scale = scale
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
        nextReminder = breakReminders
            ? Date().addingTimeInterval(.random(in: reminderMinutes) * 60)
            : .distantFuture
    }

    // MARK: Sensoren

    /// Videocall oder Bildschirmfreigabe → auf Streifzug (und erst 5 s nach dem Ende zurück).
    private func updateCallHiding(now: Date) {
        let reason = hideDuringCalls ? CallDetector.currentReason() : nil
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
        brain.suppressVisits = reason != nil
        brain.roaming = userRoaming || reason != nil
    }

    /// Fokus aktiv → leise und ruhig.
    private func updateFocus() {
        focusActive = respectFocus && focusMonitor.isFocused
        brain.calm = focusActive
    }

    /// Verkleidung an Feiertagen: Kürbis an Halloween, Weihnachtsmütze am 24./25.12., Partyhut am 31.12. und 1.1.
    private func updateOutfit() {
        if let outfitOverride {
            view.accessory = outfitOverride
            return
        }
        let day = Calendar.current.dateComponents([.month, .day], from: Date())
        switch (day.month, day.day) {
        case (10, 31): view.accessory = Frames.pumpkinHat
        case (12, 24), (12, 25): view.accessory = Frames.santaHat
        case (12, 31), (1, 1): view.accessory = Frames.partyHat
        default: view.accessory = nil
        }
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
            pomodoro = Pomodoro(stage: .rest, ends: now.addingTimeInterval(Double(breakMinutes) * 60))
            brain.mode = .focusBreak
            pendingMeow = (.breakStarts, now)
            showBubble(until: pomodoro.ends)
        case .rest:
            pomodoro = Pomodoro(stage: .focus, ends: now.addingTimeInterval(Double(focusMinutes) * 60))
            setPlaying(false)
            removeBowl()
            brain.mode = .focus
            if soundsAllowed { Meow.play(.backToWork) }
        }
        self.pomodoro = pomodoro
    }

    private func updateStatusText(force: Bool = false) {
        let text = pomodoro?.label(at: Date())
            ?? timer.map { $0.finished ? "0:00" : countdownText(until: $0.ends, from: Date()) }
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
        if basketInDock {
            NSApp.setActivationPolicy(.regular)
            NSApp.dockTile.contentView = basketTile
        } else {
            NSApp.dockTile.contentView = nil
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.dockTile.display()
        basketRefresh = 0
    }

    /// Wo das Körbchen im Dock sitzt – nur dann hüpft sie hinein (statt hinauszulaufen).
    private func updateBasketPosition() {
        guard basketInDock, let primary = primaryScreen else {
            brain.useBasket = false
            brain.basketX = nil
            return
        }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Pixelcat"
        brain.basketX = DockLocator.basketCenterX(appName: name, screen: primary)
        // Ins Körbchen steigen geht nur, wenn das Dock unten zu sehen ist
        let dockHeight = primary.visibleFrame.minY - primary.frame.minY
        brain.basketFloorY = primary.frame.minY + dockHeight * 0.22
        brain.useBasket = brain.basketX != nil && (screen == primary) && dockHeight > 20 && !isFullscreen
    }

    /// Dock-Symbol: leeres Körbchen – oder die Katze schläft darin (atmet, hebt ab und zu den Schwanz).
    private func updateBasketTile(dt: Double) {
        guard basketInDock else { return }
        tileClock += dt
        let inside = brain.isAway
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
            let hat = sprite.earAnchor != nil ? max(0, (view.accessory?.height ?? 0) - 2) : 0
            head = CGPoint(x: brain.x.rounded() + canvasX * scale,
                           y: brain.y.rounded() + CGFloat(look.hop + sprite.height + hat + 1) * scale)
        }
        bubble.update(dt: dt, head: head)
        if bubble.isGone {
            bubble.remove()
            self.bubble = nil
        }
    }

    // MARK: Takt

    /// Wie oft der Takt läuft: flüssig bei Bewegung, sparsam in Ruhe, fast gar nicht, wenn sie weg ist.
    private func adjustTickRate() {
        let mouse = NSEvent.mouseLocation
        let mouseNearCat = panel.isVisible && panel.frame.insetBy(dx: -100, dy: -100).contains(mouse)
        let interval: TimeInterval
        if !isVisible || brain.isAway {
            interval = 0.5
        } else if brain.needsSmoothMotion || ball != nil || mouseNearCat || brain.isBeingPetted
                    || bubble?.isPopping == true {
            interval = 1.0 / 30
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
        if basketInDock, brain.isAway, screenID != nil { screenID = nil }
        fullscreenRefresh -= dt
        if fullscreenRefresh <= 0 {
            fullscreenRefresh = 0.5
            isFullscreen = detectFullscreen()
        }
        basketRefresh -= dt
        if basketRefresh <= 0 {
            basketRefresh = 1
            updateBasketPosition()
        }
        updateBounds()
        brain.dockY = ground
        perchRefresh -= dt
        if perchRefresh <= 0, brain.climbingEnabled || brain.isOnWindow {
            perchRefresh = 0.2
            brain.setPerches(findPerches())
        }
        sensorRefresh -= dt
        if sensorRefresh <= 0 {
            sensorRefresh = 2
            updateCallHiding(now: date)
            updateFocus()
            updateOutfit()
        }
        updatePomodoro(now: date)
        updateTimer(now: date)
        updateStatusText()
        if pomodoro == nil, date >= nextReminder {
            if let timer {
                // Wartet sie schon auf Streicheln, ist ohnehin Pause
                if !timer.finished { takeBreakDuringTimer(now: date) }
            } else {
                pendingMeow = (.reminder, date)
                brain.remindToTakeBreak()
                showBubble(until: date.addingTimeInterval(breakLength))
            }
            scheduleReminder()
        }

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
        if let bowl, bowl.food <= 0, brain.phase != .eating {
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
            if bowl != nil { removeBowl() }
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
        panel.setFrameOrigin(NSPoint(x: (brain.x + half * scale - half * drawScale).rounded(), y: brain.y.rounded()))
        let look = brain.look
        if look != view.look { view.look = look }

        if let bowl, let bowlWindow {
            bowlWindow.view.sprite = bowl.food > 0.5 ? Frames.bowlFull
                : bowl.food > 0 ? Frames.bowlHalf : Frames.bowlEmpty
            bowlWindow.place(centerX: bowl.x, bottom: ground)
        }
        if let ball, let ballWindow {
            ballWindow.view.sprite = Int(ball.rolled / (3 * scale)) % 2 == 0 ? Frames.yarnA : Frames.yarnB
            ballWindow.place(centerX: ball.x, bottom: ground + ball.y)
        }
    }
}
