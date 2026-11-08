import AppKit

// Szenarien rund um den Katzenkorb – ausführen mit ./test.sh
// Jedes Szenario spielt Ereignisse zu festen Zeiten ab (Pause, Timer, Korb verschieben, Katzenkorb aus …) und prüft:
//   • Sie steigt immer genau an der Stelle hinein bzw. heraus, an der der Korb in diesem Moment steht.
//   • Am Ende liegt sie im Korb oder ist draußen – so wie erwartet (nichts geht verloren, nichts hängt).

final class Bed { var x: CGFloat? = 1200 }
typealias Event = (time: Double, label: String, run: @MainActor (CatBrain, Bed) -> Void)

MainActor.assumeIsolated {
    let dt = 1.0 / 30
    let afternoon = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
    var failed = 0

    @MainActor func scenario(_ name: String, seconds: Double, endsInBed: Bool, _ events: [Event]) {
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        b.useBasket = true
        b.emergeDelay = 2 // wie ohne Bedienungshilfen
        let bed = Bed()
        b.locateBasket = { b.basketX = bed.x; b.basketFloorY = bed.x == nil ? nil : 27 }
        var pending = events, t = 0.0, last = "", problems: [String] = []
        for _ in 0..<Int(seconds / dt) {
            while let e = pending.first, t >= e.time { e.run(b, bed); pending.removeFirst() }
            b.update(dt: dt)
            t += dt
            let phase = "\(b.phase)"
            if phase != last, phase == "enteringBasket" || phase == "leavingBasket", let bedX = bed.x {
                let mid = b.x + CGFloat(Layout.canvasWidth) / 2 * b.scale
                if abs(mid - bedX) > 1 {
                    problems.append(String(format: "%.1f s: %@ bei x=%.0f, Korb steht bei %.0f", t, phase, mid, bedX))
                }
            }
            last = phase
        }
        if b.isAway != endsInBed {
            problems.append("am Ende \(b.isAway ? "im Korb" : "draußen"), erwartet \(endsInBed ? "im Korb" : "draußen")")
        }
        print(problems.isEmpty ? "✓ \(name)" : "✗ \(name)\n    " + problems.joined(separator: "\n    "))
        if !problems.isEmpty { failed += 1 }
    }

    let bedOn: Event = (0, "Katzenkorb an", { b, _ in b.roaming = true })
    func at(_ t: Double, _ label: String, _ run: @escaping @MainActor (CatBrain, Bed) -> Void) -> Event { (t, label, run) }
    func move(_ t: Double, to x: CGFloat) -> Event { at(t, "Korb nach \(Int(x))") { _, bed in bed.x = x } }
    func breakStarts(_ t: Double) -> Event { at(t, "Pause") { b, _ in b.mode = .focusBreak } }
    func focus(_ t: Double) -> Event { at(t, "Fokus") { b, _ in b.mode = .focus } }
    func bedOff(_ t: Double) -> Event { at(t, "Katzenkorb aus") { b, _ in b.roaming = false } }
    func timerDone(_ t: Double) -> Event { at(t, "Timer fertig") { b, _ in b.callToCenter(untilAcknowledged: true) } }
    func click(_ t: Double) -> Event { at(t, "Klick") { b, _ in b.clicked() } }

    // Sie läuft ca. 14 s zum Korb, steigt bis ca. 17,5 s hinein und liegt dann drin.
    scenario("Hineinlegen", seconds: 25, endsInBed: true, [bedOn])
    scenario("Korb verschoben, während sie hinläuft", seconds: 25, endsInBed: true, [bedOn, move(3, to: 500)])
    scenario("Korb verschoben, während sie hineinsteigt", seconds: 25, endsInBed: true, [bedOn, move(15.5, to: 500)])
    scenario("Drin, Korb verschoben, Pause", seconds: 40, endsInBed: false, [bedOn, move(20, to: 500), breakStarts(25)])
    scenario("Drin, Korb verschoben, Pause vorbei", seconds: 50, endsInBed: true,
             [bedOn, move(20, to: 500), breakStarts(25), focus(34)])
    scenario("Drin, Korb verschoben, Katzenkorb aus", seconds: 35, endsInBed: false, [bedOn, move(20, to: 500), bedOff(25)])
    scenario("Drin, Korb verschoben, Timer, Klick", seconds: 50, endsInBed: true,
             [bedOn, move(20, to: 800), timerDone(25), click(36)])
    scenario("Zweimal hin und her, Korb jedes Mal woanders", seconds: 75, endsInBed: false,
             [bedOn, breakStarts(20), move(30, to: 400), focus(31), move(50, to: 1300), breakStarts(55)])
    scenario("Pause, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, breakStarts(16)])
    scenario("Pause und gleich wieder Fokus, während sie hineinsteigt", seconds: 30, endsInBed: true,
             [bedOn, breakStarts(15), focus(15.6)])
    scenario("Katzenkorb aus, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, bedOff(16)])
    scenario("Timer, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, move(14, to: 800), timerDone(15)])
    scenario("Erinnerung, während sie hineinsteigt (danach zurück)", seconds: 45, endsInBed: true,
             [bedOn, at(15, "Erinnerung") { b, _ in b.breakVisitLength = 5; b.callToCenter() }])
    scenario("Pause vorbei, während sie heraussteigt", seconds: 40, endsInBed: true, [bedOn, breakStarts(20), focus(20.5)])
    scenario("Korb verschoben, während sie heraussteigt", seconds: 40, endsInBed: false,
             [bedOn, breakStarts(20), move(20.5, to: 500)])
    scenario("Klick, während sie hineinsteigt", seconds: 25, endsInBed: true, [bedOn, click(16)])
    scenario("Vollbild, Pause, Vollbild aus, Pause", seconds: 55, endsInBed: false, [
        bedOn, at(14, "Vollbild an") { b, _ in b.useBasket = false; b.dockY = 0 }, breakStarts(15), focus(25),
        at(26, "Vollbild aus") { b, _ in b.useBasket = true; b.dockY = 57 }, breakStarts(45)])

    scenario("Dock speichert die Verschiebung erst nach der Pause-Anfrage", seconds: 40, endsInBed: false,
             [bedOn, move(20, to: 700), breakStarts(25), move(26, to: 400)])
    scenario("Katzenkorb aus und gleich wieder an (sie bleibt liegen)", seconds: 35, endsInBed: true,
             [bedOn, bedOff(25), at(25.5, "Katzenkorb an") { b, _ in b.roaming = true }])
    scenario("Videocall: Pause bleibt aus, nach dem Call heraus", seconds: 45, endsInBed: false, [
        bedOn, at(20, "Call") { b, _ in b.suppressVisits = true }, breakStarts(22),
        at(30, "Call vorbei") { b, _ in b.suppressVisits = false }])
    scenario("Videocall beginnt, während sie heraussteigt", seconds: 40, endsInBed: true, [
        bedOn, breakStarts(20), at(20.5, "Call") { b, _ in b.suppressVisits = true }])
    scenario("Aufscheuchen (Menü), während sie hineinsteigt", seconds: 25, endsInBed: true,
             [bedOn, at(16, "Aufscheuchen") { b, _ in b.startle() }])
    scenario("Korb verschwindet aus dem Dock, während sie drin liegt", seconds: 40, endsInBed: false,
             [bedOn, at(20, "Korb weg") { _, bed in bed.x = nil }, breakStarts(25)])

    // MARK: Kleine Erinnerungen

    @MainActor func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print(ok ? "✓ \(name)" : "✗ \(name)\n    \(detail())")
        if !ok { failed += 1 }
    }

    /// Lässt die Katze laufen und merkt sich, wie lange sie in welcher Phase war und wo sie dabei stand
    @MainActor func run(_ b: CatBrain, seconds: Double, every: Double = 1.0 / 30, _ step: ((Double) -> Void)? = nil)
        -> (phases: [String: Double], firstAt: [String: CGFloat]) {
        var phases: [String: Double] = [:], firstAt: [String: CGFloat] = [:]
        var t = 0.0
        while t < seconds {
            step?(t)
            b.update(dt: every)
            t += every
            let name = "\(b.phase)"
            phases[name, default: 0] += every
            if firstAt[name] == nil { firstAt[name] = b.x + CGFloat(Layout.canvasWidth) / 2 * b.scale }
        }
        return (phases, firstAt)
    }
    @MainActor func freshBrain() -> CatBrain {
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        return b
    }

    print("\nTrinken")
    do {
        let b = freshBrain()
        let bowl = Bowl(x: 900, water: true)
        b.bowl = bowl
        b.noticeSomething()
        let result = run(b, seconds: 60)
        let drank = result.phases["drinking"] ?? 0
        check("trinkt 20–30 Sekunden am Wassernapf", drank >= 20 && drank <= 31, "trank \(drank) s")
        let mouth = result.firstAt["drinking"] ?? 0
        check("steht dabei am Napf", abs(mouth - 900) < 40, "Mitte bei \(mouth), Napf bei 900")
        check("Napf ist danach leer (wird weggeräumt)", bowl.food <= 0, "Füllstand \(bowl.food)")
    }
    do {
        // Im Körbchen: Sie kommt heraus, trinkt und legt sich danach wieder hinein
        let b = freshBrain()
        b.useBasket = true
        b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
        b.roaming = true
        _ = run(b, seconds: 25)
        let bowl = Bowl(x: 500, water: true)
        b.bowl = bowl
        b.startErrandVisit(for: 300)
        var ended = false
        let result = run(b, seconds: 120) { _ in
            if bowl.food <= 0, !ended { ended = true; b.bowl = nil; b.endErrandVisit() }
        }
        check("Körbchen: kommt zum Trinken heraus", (result.phases["leavingBasket"] ?? 0) > 0)
        check("Körbchen: trinkt", (result.phases["drinking"] ?? 0) >= 20, "\(result.phases["drinking"] ?? 0) s")
        check("Körbchen: liegt danach wieder im Korb", b.isAway, "Phase \(b.phase)")
    }
    do {
        // Streifzug ohne Körbchen: von der Seite herein und wieder hinaus
        let b = freshBrain()
        b.roaming = true
        _ = run(b, seconds: 25)
        let bowl = Bowl(x: 700, water: true)
        b.bowl = bowl
        b.startErrandVisit(for: 300)
        var ended = false
        let result = run(b, seconds: 140) { _ in
            if bowl.food <= 0, !ended { ended = true; b.bowl = nil; b.endErrandVisit() }
        }
        check("Streifzug: trinkt", (result.phases["drinking"] ?? 0) >= 20)
        check("Streifzug: ist danach wieder draußen", b.isAway, "Phase \(b.phase)")
    }

    print("\nAugenpause")
    do {
        let b = freshBrain()
        var done = false
        var backPose = false
        b.lookout = 800
        b.onLookoutDone = { done = true }
        b.noticeSomething()
        let result = run(b, seconds: 50) { _ in
            if b.phase == .gazing {
                let look = b.look
                backPose = (look.sprite === Frames.sitBackA || look.sprite === Frames.sitBackB) && look.hop == LookoutArt.sillTop
            }
        }
        let gazed = result.phases["gazing"] ?? 0
        check("schaut 25 Sekunden aus dem Fenster", gazed >= 24 && gazed <= 26, "schaute \(gazed) s")
        let at = result.firstAt["gazing"] ?? 0
        check("sitzt dabei mittig vor dem Fenster", abs(at - 800) < 4 * b.scale, "Mitte bei \(at), Fenster bei 800")
        check("meldet danach „fertig“ (Fenster verschwindet)", done && b.lookout == nil)
        check("Pose: von hinten, auf dem Fensterbrett", backPose)
    }
    do {
        // Im Körbchen: heraus, hinausschauen, zurück in den Korb
        let b = freshBrain()
        b.useBasket = true
        b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
        b.roaming = true
        _ = run(b, seconds: 25)
        b.lookout = 600
        b.onLookoutDone = { b.endErrandVisit() }
        b.startErrandVisit(for: 300)
        let result = run(b, seconds: 120)
        check("Körbchen: schaut hinaus", (result.phases["gazing"] ?? 0) >= 24, "\(result.phases["gazing"] ?? 0) s")
        check("Körbchen: liegt danach wieder im Korb", b.isAway, "Phase \(b.phase)")
    }
    do {
        // Gestreichelt mitten im Hinausschauen: danach geht sie wieder hin
        let b = freshBrain()
        b.lookout = 700
        b.noticeSomething()
        var petted = false
        let result = run(b, seconds: 80) { _ in
            if !petted, b.phase == .gazing { petted = true; b.stroke() }
        }
        check("nach Streicheln schaut sie weiter hinaus", (result.phases["gazing"] ?? 0) >= 24 && b.lookout == nil,
              "\(result.phases["gazing"] ?? 0) s")
    }

    print("\nÜberschneidungen")
    do {
        // Pausen-Erinnerung kommt, während sie trinkt: erst austrinken, dann zur Pause in die Mitte
        let b = freshBrain()
        let bowl = Bowl(x: 300, water: true)
        b.bowl = bowl
        b.noticeSomething()
        var called = false
        let result = run(b, seconds: 80) { _ in
            if !called, b.phase == .drinking { called = true; b.remindToTakeBreak() }
        }
        check("trinkt trotz Pausen-Erinnerung zu Ende", (result.phases["drinking"] ?? 0) >= 24, "\(result.phases["drinking"] ?? 0) s")
        check("danach Pause in der Mitte (strecken)", (result.phases["stretching"] ?? 0) > 0)
    }
    do {
        // Pomodoro-Fokus beginnt mitten im Hinausschauen: Sie hört auf und schläft
        let b = freshBrain()
        b.lookout = 600
        b.noticeSomething()
        var focused = false
        _ = run(b, seconds: 60) { _ in
            if !focused, b.phase == .gazing { focused = true; b.lookout = nil; b.mode = .focus }
        }
        check("Fokus beendet das Hinausschauen, sie schläft", [.sleeping, .lyingDown, .sittingDown].contains(b.phase), "\(b.phase)")
    }
    do {
        // Trinken und danach Fenster (wie zwei Erinnerungen hintereinander)
        let b = freshBrain()
        let bowl = Bowl(x: 1000, water: true)
        b.bowl = bowl
        b.noticeSomething()
        var stage = 0
        let result = run(b, seconds: 150) { _ in
            if stage == 0, bowl.food <= 0 { stage = 1; b.bowl = nil; b.lookout = 400 }
        }
        check("trinkt und schaut danach hinaus", (result.phases["drinking"] ?? 0) >= 24 && (result.phases["gazing"] ?? 0) >= 24)
    }

    print("\nPausen nach Aktivität")
    do {
        var tracker = ActivityTracker()
        for _ in 0..<(30 * 30) { tracker.update(dt: 2, idle: 3) }          // 30 Minuten tippen
        check("zählt aktive Zeit", abs(tracker.activeSeconds - 1800) < 1, "\(tracker.activeSeconds)")
        for _ in 0..<60 { tracker.update(dt: 2, idle: 30) }                 // 2 Minuten lesen
        check("kurzes Lesen zählt mit", abs(tracker.activeSeconds - 1920) < 1, "\(tracker.activeSeconds)")
        for _ in 0..<90 { tracker.update(dt: 2, idle: 120) }                // länger nichts, aber keine 5 Minuten
        check("ab 1 Minute Leerlauf zählt nichts mehr dazu", abs(tracker.activeSeconds - 1920) < 1, "\(tracker.activeSeconds)")
        tracker.update(dt: 2, idle: 301)                                    // 5 Minuten weg
        check("5 Minuten weg zählt als Pause (von vorne)", tracker.activeSeconds == 0, "\(tracker.activeSeconds)")
    }

    print("\nFeierabend")
    do {
        let cal = Calendar.current
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        // 22.10.2026 ist ein Donnerstag, der 24. ein Samstag
        let s = ErrandScheduler()
        s.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: true, enabled: true)
        s.collectDue(now: at(22, 17, 29))
        check("vor 17:30 nichts", s.queue.isEmpty)
        s.collectDue(now: at(22, 17, 31))
        check("um 17:30 kommt der Feierabend", s.popNext()?.kind == .quittingTime)
        s.collectDue(now: at(22, 22, 0))
        check("am selben Abend nur einmal", s.queue.isEmpty)
        // Das Programm läuft weiter (es sieht die Uhrzeit, wenn sie erreicht wird)
        s.collectDue(now: at(23, 17, 29))
        s.collectDue(now: at(23, 17, 31))
        check("läuft das Programm bis Freitag weiter: Freitag zählt", s.popNext()?.kind == .quittingTime)
        s.collectDue(now: at(24, 17, 29))
        s.collectDue(now: at(24, 17, 31))
        check("samstags nicht (nur werktags)", s.queue.isEmpty)

        let late = ErrandScheduler()
        late.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: false, enabled: true)
        late.collectDue(now: at(22, 19, 0))
        late.collectDue(now: at(22, 19, 1))
        check("erst abends gestartet: keine nachträgliche Ankündigung", late.queue.isEmpty)
        late.collectDue(now: at(24, 17, 29))
        late.collectDue(now: at(24, 17, 31))
        check("über Nacht weiterlaufend: am nächsten Tag wieder (auch am Wochenende, wenn so eingestellt)",
              late.popNext()?.kind == .quittingTime)

        // Mac im Ruhezustand über Nacht: am Morgen kein Feierabend vom Vorabend
        let sleepy = ErrandScheduler()
        sleepy.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: false, enabled: true)
        sleepy.collectDue(now: at(22, 17, 0))
        sleepy.collectDue(now: at(23, 8, 0))
        check("nach einer Nacht im Ruhezustand: kein Feierabend am Morgen", sleepy.queue.isEmpty)
        let nap = ErrandScheduler()
        nap.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: false, enabled: true)
        nap.collectDue(now: at(22, 17, 20))
        nap.collectDue(now: at(22, 17, 50))
        check("kurz zugeklappt: Feierabend kommt beim Aufklappen", nap.popNext()?.kind == .quittingTime)
    }

    // Feste Tage in deutscher Zeit (24. Oktober 2026 ist ein Samstag)
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    print("\nAufgaben")
    do {
        let start = at(20, 8)
        let s = ErrandScheduler()
        s.calendar = berlin
        let call = TaskItem(text: "Mama anrufen", time: 14 * 60)
        let tax = TaskItem(text: "Steuer", time: 9 * 60 + 30)
        s.configureTasks([call, tax, TaskItem(text: "   ", time: 10 * 60)], enabled: true, now: start, launch: true)
        var shown: [String: [Date]] = [:]
        var t = start
        while t <= at(21, 23) {
            s.collectDue(now: t)
            while let errand = s.popNext() { shown[errand.text ?? "?", default: []].append(t) }
            t += 60
        }
        check("jede Aufgabe einmal am Tag zu ihrer Uhrzeit",
              shown["Mama anrufen"] == [at(20, 14), at(21, 14)] && shown["Steuer"] == [at(20, 9, 30), at(21, 9, 30)],
              "\(shown)")
        check("leere Einträge zählen nicht", shown["?"] == nil && shown.count == 2, "\(shown.keys)")

        // Mac im Ruhezustand: bis zu 3 Stunden später holt sie es nach, danach erst morgen wieder
        let sleepy = ErrandScheduler()
        sleepy.calendar = berlin
        sleepy.configureTasks([call], enabled: true, now: start, launch: true)
        sleepy.collectDue(now: at(20, 13))
        sleepy.collectDue(now: at(20, 16, 30))
        check("nach dem Aufwachen holt sie die Aufgabe nach", sleepy.popNext()?.text == "Mama anrufen")
        let late = ErrandScheduler()
        late.calendar = berlin
        late.configureTasks([call], enabled: true, now: start, launch: true)
        late.collectDue(now: start)
        late.collectDue(now: at(20, 17, 30))
        check("mehr als 3 Stunden zu spät: erst morgen wieder", late.popNext() == nil)

        // Start um 15 Uhr: Die Aufgabe von 14 Uhr kommt gleich
        let launch = ErrandScheduler()
        launch.calendar = berlin
        launch.configureTasks([call], enabled: true, now: at(20, 15), launch: true)
        launch.collectDue(now: at(20, 15))
        check("beim Start holt sie Verpasstes nach", launch.popNext()?.text == "Mama anrufen")

        // Neu angelegt für eine Uhrzeit, die heute schon vorbei ist: erst morgen
        let fresh = ErrandScheduler()
        fresh.calendar = berlin
        fresh.configureTasks([], enabled: true, now: at(20, 15), launch: true)
        fresh.configureTasks([call], enabled: true, now: at(20, 15, 1))
        fresh.collectDue(now: at(20, 15, 2))
        let notToday = fresh.popNext() == nil
        fresh.collectDue(now: at(21, 14))
        check("neue Aufgabe für eine vergangene Uhrzeit kommt erst morgen", notToday && fresh.popNext()?.text == "Mama anrufen")
        var moved = call
        moved.time = 16 * 60
        fresh.configureTasks([moved], enabled: true, now: at(21, 15))
        fresh.collectDue(now: at(21, 16))
        check("auf später verstellt: kommt heute noch einmal", fresh.popNext()?.text == "Mama anrufen")

        let often = TaskItem(text: "Wasser", time: 11 * 60)
        // Ausgeschaltet: nichts wird fällig, „Jetzt zeigen“ geht trotzdem
        let off = ErrandScheduler()
        off.configureTasks([often], enabled: false, now: start)
        off.collectDue(now: start.addingTimeInterval(3600))
        check("ausgeschaltet kommt nichts", off.popNext() == nil)
        off.requestTask(often.id)
        check("eine bestimmte Aufgabe vorführen", off.popNext()?.text == "Wasser")
        off.requestNow(.task)
        check("„Jetzt zeigen“ nimmt irgendeine Aufgabe", off.popNext()?.kind == .task)

        // Umbenannt, während sie wartet: Es erscheint der neue Text
        let rename = ErrandScheduler()
        rename.configureTasks([often], enabled: false, now: start)
        rename.requestTask(often.id)
        var renamed = often
        renamed.text = "Wasser trinken!"
        rename.configureTasks([renamed], enabled: false, now: start)
        check("umbenannte Aufgabe zeigt den neuen Text", rename.popNext()?.text == "Wasser trinken!")
        // Gelöscht, während sie wartet: kommt nicht mehr
        rename.requestTask(often.id)
        rename.configureTasks([], enabled: false, now: start)
        check("gelöschte Aufgabe kommt nicht mehr", rename.popNext() == nil)

        // Speichern und Laden
        let restored = TaskItem(dictionary: tax.dictionary)
        check("Aufgabe übersteht Speichern und Laden", restored == tax)
        let old = TaskItem(dictionary: ["text": "Alt", "minutes": 30])
        check("frühere Aufgaben mit Abstand kommen um 10 Uhr", old?.time == TaskItem.defaultTime && old?.text == "Alt")

        let lines = PixelFont.lines("Steuererklärung bis Freitag abgeben!", maxWidth: BubbleFrames.maxTextWidth, maxLines: 3)
        check("langer Text wird an Wortgrenzen umbrochen", lines == ["STEUERERKLÄRUNG", "BIS FREITAG", "ABGEBEN!"], "\(lines)")
        let long = PixelFont.lines(String(repeating: "Wort ", count: 30), maxWidth: BubbleFrames.maxTextWidth, maxLines: 3)
        check("zu langer Text endet nach drei Zeilen mit …", long.count == 3 && long[2].hasSuffix("…"), "\(long)")
    }

    print("\nMotivation")
    do {
        func sayings(workdayEnd: Int?, weekdaysOnly: Bool = false, from: Date, to: Date) -> [Date] {
            let s = ErrandScheduler()
            s.calendar = berlin
            s.random = { 0.5 }
            s.configureMotivation(enabled: true, workdayEnd: workdayEnd, weekdaysOnly: weekdaysOnly)
            var times: [Date] = []
            var t = from
            while t <= to {
                s.collectDue(now: t)
                while let errand = s.popNext() { if errand.kind == .motivation { times.append(t) } }
                t += 60
            }
            return times
        }
        let normal = sayings(workdayEnd: 17 * 60 + 30, from: at(20, 7), to: at(21, 23))
        let hours = normal.map { berlin.component(.hour, from: $0) }
        check("morgens und gegen Feierabend, zwei am Tag", hours == [9, 16, 9, 16], "\(hours)")
        let spaced = zip(normal, normal.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= ErrandScheduler.motivationSpacing }
        check("mindestens 4 Stunden dazwischen", spaced)
        let long = sayings(workdayEnd: 20 * 60, from: at(20, 7), to: at(20, 23))
        check("an einem langen Tag einer mehr in der Mitte", long.count == 3,
              "\(long.map { berlin.component(.hour, from: $0) })")
        let weekend = sayings(workdayEnd: 17 * 60 + 30, weekdaysOnly: true, from: at(24, 7), to: at(25, 23))
        check("nur werktags: am Wochenende keine", weekend.isEmpty, "\(weekend)")
        // Mac im Ruhezustand: kurz danach kommt er noch, viel später nicht mehr
        let s = ErrandScheduler()
        s.calendar = berlin
        s.random = { 0.5 }
        s.configureMotivation(enabled: true, workdayEnd: 17 * 60 + 30, weekdaysOnly: false)
        s.collectDue(now: at(20, 7))
        s.collectDue(now: at(20, 12))
        check("viel später: der Morgenspruch fällt aus", s.popNext() == nil)
        // Im Videocall wartet er (nur Aufgaben dürfen)
        s.collectDue(now: at(20, 16, 40))
        check("im Videocall wartet er", s.popNext(where: { $0 == .task }) == nil && s.queuedKinds == [.motivation])
        s.configureMotivation(enabled: false, workdayEnd: 17 * 60 + 30, weekdaysOnly: false)
        check("ausgeschaltet: weg aus der Schlange", s.queuedKinds.isEmpty)
        let own = CatController.ownSayings(morning: true)
        check("ohne eigene Sprüche hat sie eigene", own.count >= 3 && own.allSatisfy { $0.count <= TasksView.maxLength })
    }

    print("\nWarteschlange")
    do {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let s = ErrandScheduler()
        s.random = { 0.5 } // ohne Zufallsschwankung
        s.configure(.drink, every: 30, now: start)
        s.configure(.lookout, every: 20, now: start)
        s.collectDue(now: start.addingTimeInterval(19 * 60))
        check("vor der Zeit ist nichts fällig", s.queue.isEmpty)
        s.collectDue(now: start.addingTimeInterval(31 * 60))
        check("beide fällig, Augenpause zuerst", s.queue.map(\.kind) == [.lookout, .drink] || s.queue.map(\.kind) == [.drink, .lookout],
              "\(s.queue.map(\.kind))")
        s.collectDue(now: start.addingTimeInterval(32 * 60))
        check("jede Art nur einmal in der Schlange", s.queue.count == 2, "\(s.queue.count)")
        _ = s.popNext(); _ = s.popNext()
        check("Schlange danach leer", s.popNext() == nil)
        s.configure(.drink, every: nil, now: start)
        s.collectDue(now: start.addingTimeInterval(200 * 60))
        check("ausgeschaltet kommt nichts mehr", !s.queue.contains { $0.kind == .drink })
        s.requestNow(.drink)
        check("„Jetzt zeigen“ kommt sofort", s.popNext()?.kind == .drink)
        // Im Videocall nur Aufgaben: Die anderen warten in der Schlange
        s.configureTasks([TaskItem(text: "Mama anrufen", time: 10 * 60)], enabled: true, now: start)
        s.requestNow(.task)
        s.requestNow(.lookout)
        let inCall = s.popNext(where: { $0 == .task })
        check("im Call kommt nur die Aufgabe dran", inCall?.kind == .task && inCall?.text == "Mama anrufen")
        check("die Augenpause wartet bis nach dem Call", s.queue.map(\.kind) == [.lookout], "\(s.queue.map(\.kind))")
        check("im Call ohne Aufgaben-Erlaubnis: nichts", s.popNext(where: { _ in false }) == nil && s.queue.count == 1)
    }

    print("\nVogel, wenn niemand da ist")
    @MainActor func birdScenario(_ name: String, roaming: Bool) {
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        b.useBasket = true
        b.emergeDelay = 2
        b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
        b.roaming = roaming
        for _ in 0..<Int(25 / dt) { b.update(dt: dt) }
        let wasAway = b.isAway
        // Der Vogel kommt: aus dem Korb heraus, umschauen, jagen
        let bird = Bird(x: 1400, y: 57 + 150)
        b.bird = bird
        if b.isOutAndAbout {
            b.peeksLeft = 3
            b.startErrandVisit(for: 3 * 60 * 60)
        } else {
            b.peeksLeft = 1
            b.noticeSomething()
        }
        var seen = Set<String>()
        for _ in 0..<Int(60 / dt) {
            bird.update(dt: dt, minX: 0, maxX: 1440, ground: 57, top: 900, unit: 1)
            b.update(dt: dt)
            seen.insert("\(b.phase)")
        }
        let chased = seen.contains("chasing") && (seen.contains("jumping") || seen.contains("batting"))
        // Jemand ist zurück: Der Vogel fliegt davon
        bird.leave()
        var flewOff = false
        for _ in 0..<Int(10 / dt) {
            bird.update(dt: dt, minX: 0, maxX: 1440, ground: 57, top: 900, unit: 1)
            b.update(dt: dt)
            if bird.isGone { flewOff = true; break }
        }
        b.bird = nil
        b.endErrandVisit()
        if roaming { b.hurryOut = true }
        var back: Double?
        for i in 0..<Int(30 / dt) {
            b.update(dt: dt)
            if b.isAway, back == nil { back = Double(i) * dt }
        }
        var problems: [String] = []
        if roaming, !wasAway { problems.append("lag vorher nicht im Korb") }
        if !chased { problems.append("hat nicht gejagt: \(seen.sorted())") }
        if !flewOff { problems.append("Vogel ist nicht weggeflogen") }
        if roaming, back == nil { problems.append("ist nicht zurück in den Korb") }
        if !roaming, b.isAway { problems.append("ist ohne Streifzug verschwunden") }
        let detail = back.map { String(format: " (zurück im Korb nach %.0f s)", $0) } ?? ""
        print(problems.isEmpty ? "✓ \(name)\(detail)" : "✗ \(name)\n    " + problems.joined(separator: "\n    "))
        if !problems.isEmpty { failed += 1 }
    }
    birdScenario("aus dem Katzenkorb: heraus, jagen, schnell zurück", roaming: true)
    birdScenario("ohne Korb und Streifzug: jagen, danach normal weiter", roaming: false)

    print("\nPausenfrage")
    do {
        var snooze = BreakSnooze()
        var steps = [snooze.minutes(base: 50)]
        for _ in 0..<4 {
            snooze.snoozed()
            steps.append(snooze.minutes(base: 50))
        }
        check("weggedrückt: jedes Mal früher, aber nie unter 15 Minuten", steps == [50, 30, 18, 15, 15], "\(steps)")
        snooze.rested()
        check("nach einer echten Pause wieder der volle Abstand", snooze.minutes(base: 50) == 50)
        snooze.snoozed()
        check("kurzer Abstand bleibt mindestens 15 Minuten", snooze.minutes(base: 20) == 15 && snooze.minutes(base: 15) == 15)

        @MainActor func bedCat() -> CatBrain {
            let b = CatBrain()
            b.clock = { afternoon }
            b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
            b.useBasket = true
            b.emergeDelay = 2
            b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
            b.roaming = true
            for _ in 0..<Int(25 / dt) { b.update(dt: dt) }
            return b
        }
        // Daumen runter: Sie geht gleich wieder in den Korb
        let no = bedCat()
        no.callToCenter(visitLength: ErrandScheduler.motivationSpacing)
        for _ in 0..<Int(20 / dt) { no.update(dt: dt) }
        let cameOut = !no.isAway
        no.declineBreak()
        var backAfter: Double?
        for i in 0..<Int(40 / dt) {
            no.update(dt: dt)
            if no.isAway, backAfter == nil { backAfter = Double(i) * dt }
        }
        check("Daumen runter: aus dem Korb gekommen und gleich wieder zurück", cameOut && backAfter != nil,
              "draußen: \(cameOut), zurück nach \(backAfter.map { String(format: "%.0f s", $0) } ?? "–")")
        // Daumen hoch: Sie freut sich und bleibt, bis die Pause vorbei ist
        let yes = bedCat()
        yes.callToCenter(visitLength: ErrandScheduler.motivationSpacing)
        for _ in 0..<Int(20 / dt) { yes.update(dt: dt) }
        yes.mode = .focusBreak
        yes.rejoice()
        let happy = "\(yes.phase)" == "petted"
        var stayed = true
        for _ in 0..<Int(5 * 60 / dt) {
            yes.update(dt: dt)
            if yes.isAway { stayed = false }
        }
        yes.mode = .normal
        var returned = false
        for _ in 0..<Int(40 / dt) {
            yes.update(dt: dt)
            if yes.isAway { returned = true }
        }
        check("Daumen hoch: freut sich, bleibt die ganze Pause und geht danach zurück", happy && stayed && returned,
              "freut sich: \(happy), geblieben: \(stayed), zurück: \(returned)")
    }

    print("\nStatistik")
    do {
        let store = StatsStore(url: nil)
        store.calendar = berlin
        store.calendar.firstWeekday = 2 // Montag
        store.record(at: at(19, 10)) { $0.breaksTaken += 2; $0.activeSeconds += 3600 }   // Montag
        store.record(at: at(21, 15)) { $0.breaksSkipped += 1; $0.pomodoros += 3 }       // Mittwoch
        store.record(at: at(25, 9)) { $0.drinks += 4 }                                   // Sonntag
        store.record(at: at(13, 9)) { $0.breaksTaken += 1 }                              // Woche davor
        let week = store.week(containing: at(22, 12))
        check("die Woche geht von Montag bis Sonntag", week.days.count == 7
              && berlin.component(.day, from: week.days.first!.date) == 19
              && berlin.component(.day, from: week.days.last!.date) == 25)
        let total = week.total
        check("Wochensumme stimmt", total.breaksTaken == 2 && total.breaksSkipped == 1 && total.pomodoros == 3
              && total.drinks == 4 && total.activeSeconds == 3600, "\(total)")
        check("Woche davor einzeln", store.week(containing: at(22, 12), offset: -1).total.breaksTaken == 1)
        check("zurückblättern nur, wenn es davor Daten gibt",
              store.hasData(before: week.start) && !store.hasData(before: store.week(containing: at(22, 12), offset: -1).start))
        check("aktive Zeit lesbar", StatsView.hoursText(45 * 60) == "45 min" && StatsView.hoursText(3.5 * 3600) == "3 h 30 min")
        // Ältere Dateien ohne Musik und Apps lassen sich weiter lesen
        let old = Data(#"{"breaksTaken":2,"activeSeconds":600}"#.utf8)
        let decoded = try? JSONDecoder().decode(DayStats.self, from: old)
        check("alte Statistik-Dateien bleiben lesbar", decoded?.breaksTaken == 2 && decoded?.musicSeconds == 0
              && decoded?.apps.isEmpty == true)
        let merged = DayStats(musicSeconds: 60, apps: ["anki": 100]) + DayStats(musicSeconds: 30, apps: ["anki": 50, "word": 10])
        check("Musik und Apps werden zusammengezählt", merged.musicSeconds == 90 && merged.apps == ["anki": 150, "word": 10])
    }

    print("\nTag starten und beenden")
    do {
        var ritual = DayRitual(enabled: true, start: 9 * 60, end: 17 * 60 + 30, weekdaysOnly: true)
        ritual.calendar = berlin
        let empty = DayJournal()
        check("vor Arbeitsbeginn wird nicht gefragt", ritual.due(now: at(20, 8, 30), journal: empty, idle: 5, notBefore: nil) == nil)
        check("ab Arbeitsbeginn: Tag starten?", ritual.due(now: at(20, 9, 5), journal: empty, idle: 5, notBefore: nil) == .start)
        check("nur, wenn man am Mac ist", ritual.due(now: at(20, 9, 5), journal: empty, idle: 300, notBefore: nil) == nil)
        check("nach Daumen runter erst später wieder",
              ritual.due(now: at(20, 9, 10), journal: empty, idle: 5, notBefore: at(20, 9, 20)) == nil
              && ritual.due(now: at(20, 9, 21), journal: empty, idle: 5, notBefore: at(20, 9, 20)) == .start)
        var started = DayJournal()
        started.started = at(20, 9, 5)
        check("gestartet: tagsüber keine Frage", ritual.due(now: at(20, 14), journal: started, idle: 5, notBefore: nil) == nil)
        check("ab Feierabend: Tag beenden?", ritual.due(now: at(20, 17, 40), journal: started, idle: 5, notBefore: nil) == .end)
        check("nach Feierabend wird nicht mehr nach dem Start gefragt",
              ritual.due(now: at(20, 18), journal: empty, idle: 5, notBefore: nil) == nil)
        var ended = started
        ended.ended = at(20, 17, 45)
        check("beendet: an dem Tag nichts mehr", ritual.due(now: at(20, 19), journal: ended, idle: 5, notBefore: nil) == nil)
        check("am Wochenende keine Frage (nur werktags)", ritual.due(now: at(24, 10), journal: empty, idle: 5, notBefore: nil) == nil)
        var weekendStart = DayJournal()
        weekendStart.started = at(24, 10)
        check("am Wochenende von Hand gestartet: abends trotzdem „Tag beenden?“",
              ritual.due(now: at(24, 18), journal: weekendStart, idle: 5, notBefore: nil) == .end)
        var lateStart = DayJournal()
        lateStart.started = at(21, 18)
        check("erst abends gestartet: nicht gleich „Tag beenden?“",
              ritual.due(now: at(21, 18, 5), journal: lateStart, idle: 5, notBefore: nil) == nil
              && ritual.due(now: at(21, 19, 5), journal: lateStart, idle: 5, notBefore: nil) == .end)
        check("nach Mitternacht: den gestrigen, offenen Tag beenden?",
              ritual.due(now: at(21, 0, 30), journal: empty, yesterday: started, idle: 5, notBefore: nil) == .end)
        check("ab Arbeitsbeginn: der neue Tag (gestern bleibt offen)",
              ritual.due(now: at(21, 9, 5), journal: empty, yesterday: started, idle: 5, notBefore: nil) == .start)
        let openStore = StatsStore(url: nil)
        openStore.calendar = berlin
        openStore.updateJournal(for: at(20, 9)) { $0.started = at(20, 9) }
        check("offener Tag nach Mitternacht ist gestern", openStore.openDay(now: at(21, 1), workdayStart: 9 * 60)
              .map { berlin.isDate($0, inSameDayAs: at(20, 12)) } == true)
        check("ab dem neuen Arbeitsbeginn ist kein Tag mehr offen", openStore.openDay(now: at(21, 9, 30), workdayStart: 9 * 60) == nil)
        openStore.updateJournal(for: at(21, 9)) { $0.started = at(21, 9) }
        check("heute gestartet: heute ist offen", openStore.openDay(now: at(21, 12), workdayStart: 9 * 60)
              .map { berlin.isDate($0, inSameDayAs: at(21, 12)) } == true)
        var other = GoalItem(text: "x", achieved: false, reason: .other)
        other.note = "  Server war down "
        check("eigener Grund bei „Andere“", other.reasonText == L10n.s("Andere: Server war down", "Other: Server war down"))
        ritual.enabled = false
        check("ausgeschaltet: nie", ritual.due(now: at(20, 9, 5), journal: empty, idle: 5, notBefore: nil) == nil)

        // Auswertung
        func day(_ start: Int?, _ end: Int?, todos: [Bool], goals: [(Bool, GoalReason?)], potential: Int?) -> DayJournal {
            var journal = DayJournal()
            journal.started = at(20, 9)
            journal.ended = end == nil ? nil : at(20, 18)
            journal.moodStart = start
            journal.moodEnd = end
            journal.todos = todos.map { TodoItem(text: "x", done: $0) }
            journal.goals = goals.map { GoalItem(text: "g", achieved: $0.0, reason: $0.1) }
            journal.potential = potential
            return journal
        }
        let summary = JournalSummary([
            day(5, 7, todos: [true, true, false, false], goals: [(true, nil), (false, .time)], potential: 7),
            day(6, 6, todos: [true, true], goals: [(false, .time), (false, .energy)], potential: 5),
            day(4, nil, todos: [false], goals: [], potential: nil), // nur gestartet
            DayJournal(), // nicht benutzt
        ])
        check("Tage mit Tagebuch", summary.days == 3, "\(summary.days)")
        check("Stimmung im Schnitt morgens und abends", summary.moodStart == 5 && summary.moodEnd == 6.5)
        check("Veränderung nur aus Tagen mit beiden Werten", summary.moodChange == 1, "\(summary.moodChange ?? -99)")
        check("To-dos pro geplantem Tag", summary.todosPerDay.map { abs($0 - 7.0 / 3) < 0.001 } == true)
        check("erledigt: nur beendete Tage zählen", summary.todosDone == 4 && summary.todosTotal == 6)
        check("Ziele erreicht", summary.goalsAchieved == 1 && summary.goalsRated == 4)
        check("häufigster Grund zuerst", summary.reasons.first?.reason == .time && summary.reasons.first?.count == 2
              && summary.reasons.count == 2)
        check("ausgeschöpft im Schnitt", summary.potential == 6)

        // Speichern und wieder lesen
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/test-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Statistics.json")
        let store = StatsStore(url: url)
        store.updateJournal(for: at(20, 9)) { $0 = day(5, 7, todos: [true], goals: [(false, .blocked)], potential: 8) }
        let reloaded = StatsStore(url: url)
        check("Tagebuch übersteht Speichern und Laden", reloaded.journal(for: at(20, 12)) == store.journal(for: at(20, 12))
              && reloaded.journal(for: at(20, 12)).goals.first?.reason == .blocked)
        // Vorsatz: kommt beim nächsten Tagesstart (nach einem Freitag also am Montag)
        store.updateJournal(for: at(23, 17)) { $0.improvement = "  Früher Pausen machen  " } // Freitag
        store.updateJournal(for: at(22, 17)) { $0.improvement = "Handy weglegen" }          // Donnerstag
        check("der Vorsatz vom letzten Tagesende, ohne Leerzeichen am Rand",
              store.lastImprovement(before: at(26, 9)) == "Früher Pausen machen")
        check("am selben Tag zählt der eigene Vorsatz noch nicht", store.lastImprovement(before: at(23, 9)) == "Handy weglegen")
        check("Vorsatz übersteht Speichern und Laden",
              StatsStore(url: url).lastImprovement(before: at(26, 9)) == "Früher Pausen machen")
        try? FileManager.default.removeItem(at: folder)
    }

    print("\nTimeboxing")
    do {
        check("auf die Viertelstunde", DayPlan.snap(52) == 45 && DayPlan.snap(53) == 60 && DayPlan.snap(-3) == 0)
        let day = DayPlan.range(workdayStart: 9 * 60, workdayEnd: 17 * 60 + 30, blocks: [DayPlan.defaultLunch])
        check("der Tag im Kalender: volle Stunden um die Arbeitszeit", day == (9 * 60)...(18 * 60), "\(day)")
        check("Feierabend vor Beginn: 9 bis 18 Uhr", DayPlan.range(workdayStart: 18 * 60, workdayEnd: 8 * 60, blocks: [])
              == (9 * 60)...(18 * 60))
        check("früher Termin erweitert den Tag",
              DayPlan.range(workdayStart: 9 * 60, workdayEnd: 17 * 60, blocks: [TimeBlock(start: 7 * 60 + 30, minutes: 30)])
                  .lowerBound == 7 * 60)
        check("Block bleibt im Tag", DayPlan.clamp(TimeBlock(start: 17 * 60 + 30, minutes: 60), to: day)
              == TimeBlock(start: 17 * 60, minutes: 60)
              && DayPlan.clamp(TimeBlock(start: 8 * 60, minutes: 5), to: day) == TimeBlock(start: 9 * 60, minutes: 15))
        let busy = [DayPlan.defaultLunch, TimeBlock(start: 9 * 60, minutes: 60)]
        check("antippen: erste freie Stunde", DayPlan.firstFree(minutes: 60, among: busy, in: day)
              == TimeBlock(start: 10 * 60, minutes: 60))
        let morning = busy + [TimeBlock(start: 10 * 60, minutes: 180)]
        check("um die Mittagspause herum", DayPlan.firstFree(minutes: 60, among: morning, in: day)
              == TimeBlock(start: 14 * 60, minutes: 60))
        let tight = [TimeBlock(start: 9 * 60, minutes: 525)] // bis 17:45
        check("kaum Platz: kürzer", DayPlan.firstFree(minutes: 60, among: tight, in: day) == TimeBlock(start: 17 * 60 + 45, minutes: 15))
        let a = UUID(), b = UUID(), c = UUID()
        let lanes = DayPlan.lanes([(a, TimeBlock(start: 600, minutes: 60)), (b, TimeBlock(start: 630, minutes: 60)),
                                   (c, TimeBlock(start: 720, minutes: 30))])
        check("überlappende Blöcke nebeneinander", lanes[a]! == (0, 2) && lanes[b]! == (1, 2) && lanes[c]! == (0, 1))
        var todos = [TodoItem(text: "Mails", start: 600), TodoItem(text: "Präsentation", start: 540, frog: true),
                     TodoItem(text: "Rechnung")]
        check("nach Uhrzeit, Ungeplantes zum Schluss", todos.byTime.map(\.text) == ["Präsentation", "Mails", "Rechnung"])
        check("der markierte Frosch", todos.frogID == todos[1].id)
        todos[1].frog = false
        check("abgewählter Frosch bleibt abgewählt", todos.frogID == nil)
        check("ältere Tage: der erste ist der Frosch", [TodoItem(text: "x"), TodoItem(text: "y")].frogID != nil)
        let old = Data(#"{"todos":[{"id":"\#(UUID().uuidString)","text":"Alt","done":true}],"moodStart":6}"#.utf8)
        let journal = try? JSONDecoder().decode(DayJournal.self, from: old)
        check("ältere Tagebücher ohne Zeiten bleiben lesbar", journal?.todos.first?.text == "Alt"
              && journal?.todos.first?.start == nil && journal?.lunch == nil)
    }

    print("\nKlick beendet die Erinnerung")
    do {
        // Augenpause: Sie geht zum Fenster, setzt sich davor – ein Klick, und sie hört auf
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        b.lookout = 700
        b.noticeSomething()
        var gazed = false
        for _ in 0..<Int(30 / dt) {
            b.update(dt: dt)
            if "\(b.phase)" == "gazing" { gazed = true; break }
        }
        b.stopErrand()
        check("vor dem Fenster angeklickt: hört auf und reckt sich", gazed && "\(b.phase)" == "stretching" && b.lookout == nil,
              "\(b.phase)")
        for _ in 0..<Int(5 / dt) { b.update(dt: dt) }
        check("und sitzt nicht mehr auf dem Fensterbrett", b.look.hop == 0)
    }

    print("\nGeführte Pause")
    do {
        let five = GuidedBreak(length: 5 * 60)
        check("fünf Minuten: alle Übungen, dann ausruhen", five.steps.count == Exercise.allCases.count + 1
              && five.steps.last?.exercise == nil && five.steps.last?.end == 5 * 60, "\(five.steps.count) Schritte")
        let one = GuidedBreak(length: 60)
        check("eine Minute: nur so viele Übungen, wie hineinpassen", one.steps.count == 4
              && one.steps.allSatisfy { $0.end <= 60 }, "\(one.steps.map(\.end))")
        check("Schritte folgen lückenlos aufeinander", zip(five.steps, five.steps.dropFirst()).allSatisfy { $0.end == $1.start })
        let texts = Exercise.allCases.map(\.text) + [L10n.s("Jetzt einfach ausruhen.", "Now just relax.")]
        let fits = texts.allSatisfy { text in
            let lines = PixelFont.lines(text, maxWidth: BubbleFrames.maxTextWidth, maxLines: BubbleFrames.maxLines)
            return !(lines.last?.hasSuffix("…") ?? true)
        }
        check("jeder Satz passt ganz in die Blase", fits)
        // Die Katze geht in die Mitte und macht vor
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 100
        b.mode = .focusBreak
        b.exercise = .arch
        var exercised = false
        for _ in 0..<Int(30 / dt) {
            b.update(dt: dt)
            if "\(b.phase)" == "exercising" { exercised = true }
        }
        let middle = (b.minX + b.maxX) / 2
        check("Übung in der Bildschirmmitte vorgemacht", exercised && abs(b.x - middle) < 60,
              "x \(Int(b.x)), Mitte \(Int(middle))")
        check("beim Katzenbuckel sieht man den Buckel", b.look.sprite === Frames.exerciseArch || b.look.sprite === Frames.stand)
        b.exercise = nil
        for _ in 0..<Int(2 / dt) { b.update(dt: dt) }
        check("ohne Übung geht es normal weiter", "\(b.phase)" != "exercising")
    }

    print("\nVideocalls")
    do {
        // Pro Situation (Videocall, Bildschirm teilen) und pro Erinnerung: zeigen (still), danach oder nie
        let selectable: [ErrandKind] = [.task, .drink, .lookout, .quittingTime, .motivation]
        var policy = CallPolicy()
        check("Grundeinstellung: erkennen an, im Call und beim Teilen alles danach",
              policy.detect && selectable.allSatisfy {
                  policy.handling(for: $0, in: .call) == .later && policy.handling(for: $0, in: .screenSharing) == .later })
        check("ohne Call kommt alles ganz normal",
              ErrandKind.allCases.allSatisfy { policy.decision(for: $0, in: .none) == .normal })
        check("im Call und beim Teilen wartet alles bis danach (wie bisher)",
              selectable.allSatisfy { policy.decision(for: $0, in: .call) == .later
                  && policy.decision(for: $0, in: .screenSharing) == .later })
        check("der Vogel kommt im Call nie und wird nicht nachgeholt",
              policy.decision(for: .bird, in: .call) == .skip && policy.decision(for: .bird, in: .screenSharing) == .skip)

        policy.set(.show, for: .task, in: .call)
        policy.set(.show, for: .drink, in: .call)
        policy.set(.skip, for: .motivation, in: .call)
        check("„Zeigen“: kommt im Call still",
              policy.decision(for: .task, in: .call) == .quiet && policy.decision(for: .drink, in: .call) == .quiet)
        check("„Danach“: wartet bis nach dem Call", policy.decision(for: .lookout, in: .call) == .later)
        check("„Nie“: fällt weg", policy.decision(for: .motivation, in: .call) == .skip)
        check("Einstellungen im Call ändern nichts am Teilen",
              selectable.allSatisfy { policy.decision(for: $0, in: .screenSharing) == .later })

        policy.set(.show, for: .task, in: .screenSharing)
        policy.set(.skip, for: .drink, in: .screenSharing)
        policy.set(.show, for: .motivation, in: .screenSharing)
        check("beim Teilen eigene Auswahl: Aufgabe zeigen, Trinken nie, Motivation zeigen",
              policy.decision(for: .task, in: .screenSharing) == .quiet
              && policy.decision(for: .drink, in: .screenSharing) == .skip
              && policy.decision(for: .motivation, in: .screenSharing) == .quiet)
        check("… und im Call gilt weiter die Call-Auswahl",
              policy.decision(for: .drink, in: .call) == .quiet && policy.decision(for: .motivation, in: .call) == .skip)

        for kind in selectable { policy.set(.show, for: kind, in: .call); policy.set(.show, for: kind, in: .screenSharing) }
        policy.set(.show, for: .bird, in: .call)
        check("auch wenn alles gezeigt wird, kein Vogel", policy.decision(for: .bird, in: .call) == .skip
              && policy.decision(for: .bird, in: .screenSharing) == .skip)
        policy.detect = false
        check("„Bei Videocalls verstecken“ aus: Im Call ist alles normal",
              ErrandKind.allCases.allSatisfy { policy.decision(for: $0, in: .call) == .normal
                  && policy.decision(for: $0, in: .screenSharing) == .normal })

        // Warteschlange: Was wegfällt, verschwindet, der Rest bleibt in seiner Reihenfolge
        let s = ErrandScheduler()
        s.configureTasks([TaskItem(text: "Mama anrufen", time: 10 * 60)], enabled: true, now: Date())
        s.requestNow(.lookout)
        s.requestNow(.drink)
        s.requestNow(.task)
        s.discard(where: { $0 == .drink })
        check("Wegfallendes verschwindet aus der Schlange", s.queue.map(\.kind) == [.task, .lookout], "\(s.queue.map(\.kind))")

        // Einstellungen: speichern, wieder laden, und ältere Einstellungen übernehmen
        let defaults = UserDefaults.standard
        let keys = ["callHandling", "sharingHandling", "callReminders", "catchUpAfterCalls", "tasksDuringCalls",
                    "remindWhileSharing", "hideDuringCalls"]
        let saved = keys.map { defaults.object(forKey: $0) }
        func clear() { keys.forEach { defaults.removeObject(forKey: $0) } }
        clear()
        defaults.set(true, forKey: "tasksDuringCalls")
        let old = AppSettings()
        check("alte Einstellung „Aufgaben auch in Videocalls“: im Call zeigen, beim Teilen danach",
              old.callHandling[.task] == .show && old.callHandling[.drink] == .later && old.sharingHandling[.task] == .later)
        clear()
        defaults.set(["drink"], forKey: "callReminders")
        defaults.set(false, forKey: "catchUpAfterCalls")
        let between = AppSettings()
        check("Zwischenstand (Auswahl plus „Danach nachholen“ aus) wird übernommen",
              between.callHandling[.drink] == .show && between.callHandling[.lookout] == .skip
              && between.callHandling[.task] == .skip, "\(between.callHandling)")
        check("… beim Teilen wartet „Zeigen“, der Rest bleibt",
              between.sharingHandling[.drink] == .later && between.sharingHandling[.lookout] == .skip,
              "\(between.sharingHandling)")
        clear()
        defaults.set(["task": "show", "drink": "later", "lookout": "skip", "quittingTime": "later", "motivation": "show"],
                     forKey: "callHandling")
        defaults.set(true, forKey: "remindWhileSharing")
        let sharingOn = AppSettings()
        check("„Zeigen auch beim Teilen“ an: Teilen übernimmt die Call-Auswahl",
              sharingOn.sharingHandling == sharingOn.callHandling, "\(sharingOn.sharingHandling)")
        defaults.set(false, forKey: "remindWhileSharing")
        let sharingOff = AppSettings()
        check("„Zeigen auch beim Teilen“ aus: Beim Teilen wird „Zeigen“ zu „Danach“",
              sharingOff.sharingHandling[.task] == .later && sharingOff.sharingHandling[.motivation] == .later
              && sharingOff.sharingHandling[.lookout] == .skip, "\(sharingOff.sharingHandling)")
        clear()
        let fresh = AppSettings()
        check("frisch: im Call und beim Teilen alles danach",
              CallPolicy.selectable.allSatisfy { fresh.callHandling[$0] == .later && fresh.sharingHandling[$0] == .later })
        fresh.callHandling[.drink] = .show
        fresh.callHandling[.motivation] = .skip
        fresh.sharingHandling[.task] = .show
        fresh.sharingHandling[.drink] = .skip
        let reloaded = AppSettings()
        check("beide Auswahlen werden gespeichert und wieder geladen",
              reloaded.callHandling[.drink] == .show && reloaded.callHandling[.motivation] == .skip
              && reloaded.callHandling[.lookout] == .later
              && reloaded.sharingHandling[.task] == .show && reloaded.sharingHandling[.drink] == .skip
              && reloaded.sharingHandling[.motivation] == .later, "\(reloaded.callHandling) \(reloaded.sharingHandling)")
        reloaded.tasksDuringCalls = true
        check("Schalter im Aufgaben-Menü: Aufgaben im Call zeigen", reloaded.callHandling[.task] == .show && reloaded.tasksDuringCalls)
        reloaded.tasksDuringCalls = false
        check("… und wieder aus: Aufgaben danach", reloaded.callHandling[.task] == .later && !reloaded.tasksDuringCalls)
        check("der Schalter im Aufgaben-Menü ändert nichts am Teilen", reloaded.sharingHandling[.task] == .show)
        reloaded.hideDuringCalls = false
        let p = reloaded.callPolicy
        check("aus den Einstellungen wird die passende CallPolicy",
              !p.detect && p.handling(for: .drink, in: .call) == .show && p.handling(for: .drink, in: .screenSharing) == .skip
              && p.handling(for: .task, in: .screenSharing) == .show)
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    print("\nLo-Fi-Musik: Beats")
    do {
        let presets = LofiBeat.presets
        check("mindestens drei fertige Beats", presets.count >= 3)
        check("jeder fertige Beat ist vollständig",
              presets.allSatisfy { beat in
                  LofiBeat.Instrument.allCases.allSatisfy { beat.steps(for: $0).count == LofiBeat.stepsPerBar }
                      && beat.chords.count == LofiBeat.barsPerLoop
                      && LofiBeat.tempoRange.contains(beat.bpm) && !beat.name.isEmpty })
        check("alle Akkorde der Auswahl haben drei oder vier Töne",
              LofiChord.palette.allSatisfy { (3...4).contains($0.notes.count) })
        check("jeder Akkord eines fertigen Beats ist bekannt",
              presets.allSatisfy { $0.chords.allSatisfy { chord in LofiChord.palette.contains(chord) } })

        var beat = LofiBeat.empty(name: "Test")
        beat.bpm = 80
        beat.swing = 0
        beat.set(.kick, step: 0, on: true)
        beat.set(.kick, step: 8, on: true)
        beat.set(.hat, step: 1, on: true)
        let bar = 60.0 / 80 * 4
        let kicks = beat.events(bar: 0).filter { $0.instrument == .kick }.map(\.time)
        check("Kick auf Schritt 1 und 9: am Taktanfang und in der Mitte",
              kicks.count == 2 && abs(kicks[0]) < 1e-9 && abs(kicks[1] - bar / 2) < 1e-9, "\(kicks)")
        let straight = beat.events(bar: 0).first { $0.instrument == .hat }!.time
        beat.swing = 0.5
        let swung = beat.events(bar: 0).first { $0.instrument == .hat }!.time
        check("Swing schiebt die Zwischenschläge nach hinten", swung > straight + 0.01, "\(straight) → \(swung)")
        check("Swing lässt die Hauptschläge, wo sie sind",
              abs(beat.events(bar: 0).filter { $0.instrument == .kick }[1].time - bar / 2) < 1e-9)
        let chordEvents = beat.events(bar: 2).filter { $0.instrument == .chord }
        check("jeder Takt hat seinen Akkord", chordEvents.count == 1 && chordEvents[0].chord == beat.chords[2])

        let sampleRate = 22_050.0
        let audio = LofiRenderer.render(presets[0], sampleRate: sampleRate)
        let loop = presets[0].loopSeconds
        check("der Loop ist genau vier Takte lang", abs(Double(audio.count) / sampleRate - loop) < 0.01,
              "\(Double(audio.count) / sampleRate) s statt \(loop) s")
        let peak = audio.map(abs).max() ?? 0
        check("der Loop ist hörbar und übersteuert nicht", peak > 0.05 && peak <= 1.0, "Spitze \(peak)")
        check("keine kaputten Werte im Klang", !audio.contains { $0.isNaN || $0.isInfinite })
        var silent = LofiBeat.empty(name: "Still")
        silent.crackle = 0
        silent.chordVolume = 0
        check("ohne Schläge, Akkorde und Knistern ist es still",
              (LofiRenderer.render(silent, sampleRate: sampleRate).map(abs).max() ?? 1) < 0.001)

        let data = try? JSONEncoder().encode(presets[1])
        let decoded = data.flatMap { try? JSONDecoder().decode(LofiBeat.self, from: $0) }
        check("ein Beat lässt sich speichern und wieder laden", decoded == presets[1])
    }

    print("\nLo-Fi-Musik: Spotify und Apple Music")
    do {
        let id = "37i9dQZF1DWWQRwui0ExPn"
        check("geteilter Spotify-Link wird erkannt",
              SpotifyLink.uri(from: "https://open.spotify.com/playlist/\(id)?si=abc123") == "spotify:playlist:\(id)")
        check("Link mit Sprachpfad wird erkannt",
              SpotifyLink.uri(from: "https://open.spotify.com/intl-de/playlist/\(id)") == "spotify:playlist:\(id)")
        check("Spotify-URI bleibt, wie sie ist", SpotifyLink.uri(from: "spotify:playlist:\(id)") == "spotify:playlist:\(id)")
        check("Leerzeichen um den Link stören nicht",
              SpotifyLink.uri(from: "  https://open.spotify.com/playlist/\(id) \n") == "spotify:playlist:\(id)")
        check("Alben gehen auch", SpotifyLink.uri(from: "https://open.spotify.com/album/1A2GTWGtFfWp7KSQTwWOyo") == "spotify:album:1A2GTWGtFfWp7KSQTwWOyo")
        check("anderes wird abgelehnt",
              SpotifyLink.uri(from: "https://example.com/playlist/\(id)") == nil && SpotifyLink.uri(from: "Lo-Fi") == nil
              && SpotifyLink.uri(from: "https://open.spotify.com/playlist/") == nil)
        check("AppleScript: Anführungszeichen im Playlist-Namen werden maskiert",
              ExternalMusic.playScript(.appleMusic(playlist: "Lo-Fi \"Mix\" \\ 2"), shuffle: false)
                .contains("playlist \"Lo-Fi \\\"Mix\\\" \\\\ 2\""))
        let spotify = MusicPlayback.spotify(uri: "spotify:playlist:\(id)")
        let shuffled = ExternalMusic.playScript(spotify, shuffle: true)
        check("Spotify spielt die Playlist", shuffled.contains("play track \"spotify:playlist:\(id)\""))
        check("Spotify mit Zufall: Zufall an, dann einen Titel weiter (sonst käme immer der erste zuerst)",
              shuffled.contains("set shuffling to true") && shuffled.contains("next track")
              && shuffled.range(of: "set shuffling")!.lowerBound < shuffled.range(of: "play track")!.lowerBound
              && shuffled.range(of: "play track")!.lowerBound < shuffled.range(of: "next track")!.lowerBound, shuffled)
        func position(_ text: String) -> String.Index { shuffled.range(of: text)!.lowerBound }
        check("Spotify mit Zufall: stumm weiterschalten, damit man den ersten Titel nicht hört",
              shuffled.contains("set savedVolume to sound volume") && shuffled.contains("set sound volume to 0")
              && position("set sound volume to 0") < position("play track")
              && position("next track") < position("set sound volume to savedVolume"), shuffled)
        check("… und die Lautstärke kommt auch zurück, wenn etwas schiefgeht",
              shuffled.contains("try") && position("end try") < position("set sound volume to savedVolume"), shuffled)
        let ordered = ExternalMusic.playScript(spotify, shuffle: false)
        check("Spotify ohne Zufall: der Reihe nach, von vorn", ordered.contains("set shuffling to false")
              && !ordered.contains("next track"), ordered)
        check("Spotify nach einer Pause: immer die eigene Playlist (nicht, was dort gerade läuft)",
              ExternalMusic.startScript(spotify, afterPause: true, shuffle: true) == shuffled
              && ExternalMusic.startScript(spotify, afterPause: false, shuffle: false) == ordered)
        let safari = "com.apple.Safari", spotifyID = ExternalMusic.App.spotify.bundleID
        check("Spotify drängt sich nach vorn: die vorige App kommt zurück",
              ExternalMusic.shouldRestoreFocus(before: safari, now: spotifyID, app: .spotify))
        check("Spotify war schon vorn: bleibt vorn", !ExternalMusic.shouldRestoreFocus(before: spotifyID, now: spotifyID, app: .spotify))
        check("Spotify blieb im Hintergrund: nichts zu tun", !ExternalMusic.shouldRestoreFocus(before: safari, now: safari, app: .spotify))
        check("ohne vorige App: nichts zu tun", !ExternalMusic.shouldRestoreFocus(before: nil, now: spotifyID, app: .spotify))
        // Läuft noch, was Pixelcat gestartet hat? (sonst geht der Haken im Menü weg)
        check("Spotify spielt: bleibt an", ExternalMusic.isStillOurs(spotify, status: "playing\n"))
        check("in Spotify pausiert oder gestoppt: Haken weg",
              !ExternalMusic.isStillOurs(spotify, status: "paused") && !ExternalMusic.isStillOurs(spotify, status: "stopped"))
        let lofi = MusicPlayback.appleMusic(playlist: "Lo-Fi")
        check("Apple Music spielt die eigene Playlist: bleibt an", ExternalMusic.isStillOurs(lofi, status: "playing|Lo-Fi"))
        check("Apple Music spielt eine andere Playlist: Haken weg", !ExternalMusic.isStillOurs(lofi, status: "playing|Rock"))
        check("Apple Music pausiert: Haken weg", !ExternalMusic.isStillOurs(lofi, status: "paused|Lo-Fi"))
        check("unbekannte Antwort: lieber anlassen", ExternalMusic.isStillOurs(lofi, status: ""))
        check("Status-Abfrage fragt nach dem Zustand (und bei Musik nach der Playlist)",
              ExternalMusic.statusScript(.spotify).contains("player state")
              && ExternalMusic.statusScript(.music).contains("name of current playlist"))
        let music = MusicPlayback.appleMusic(playlist: "Lo-Fi")
        check("Apple Music mit Zufall", ExternalMusic.playScript(music, shuffle: true).contains("set shuffle enabled to true")
              && ExternalMusic.playScript(music, shuffle: false).contains("set shuffle enabled to false"))
        let resume = ExternalMusic.startScript(music, afterPause: true, shuffle: true)
        check("Apple Music nach einer Pause: weiter nur, wenn noch die eigene Playlist läuft",
              resume.contains("name of current playlist is \"Lo-Fi\"") && resume.contains("play playlist \"Lo-Fi\""), resume)
        check("Apple Music beim ersten Start: gleich die Playlist",
              ExternalMusic.startScript(music, afterPause: false, shuffle: true) == ExternalMusic.playScript(music, shuffle: true))
    }

    print("\nLo-Fi-Musik: wann sie läuft")
    do {
        var m = MusicCoordinator()
        check("am Anfang ist es still", !m.shouldPlay)
        m.toggle()
        check("Klick im Menü: Musik an", m.shouldPlay && m.manualOn)
        m.toggle()
        check("noch ein Klick: Musik aus", !m.shouldPlay)

        m.playDuringFocus = true
        m.pomodoroStage = .focus
        check("Pomodoro-Fokus: Musik an", m.shouldPlay)
        m.pomodoroStage = .rest
        check("Pomodoro-Pause: Musik aus", !m.shouldPlay)
        m.pomodoroStage = .focus
        check("nächster Fokus: wieder an", m.shouldPlay)
        m.toggle()
        check("im Fokus ausgeschaltet: bleibt aus", !m.shouldPlay)
        m.pomodoroStage = .rest
        m.pomodoroStage = .focus
        check("… bis zum nächsten Fokus", m.shouldPlay)
        m.pomodoroStage = .rest
        m.toggle()
        check("in der Pause eingeschaltet: läuft", m.shouldPlay)
        m.pomodoroStage = nil
        check("Pomodoro vorbei: wie vorher (aus)", !m.shouldPlay)

        m.toggle()
        m.pomodoroStage = .focus
        m.pomodoroStage = .rest
        check("vorher eingeschaltet: in der Pause trotzdem still", !m.shouldPlay)
        m.pomodoroStage = nil
        check("Pomodoro vorbei: wie vorher (an)", m.shouldPlay)

        m.playDuringFocus = false
        m.manualOn = false
        m.pomodoroStage = .focus
        check("ohne Pomodoro-Musik ändert der Fokus nichts", !m.shouldPlay)
        m.toggle()
        m.pomodoroStage = .rest
        check("… und die Pause auch nicht", m.shouldPlay)
        m.pomodoroStage = nil

        m.inCall = true
        check("im Videocall pausiert die Musik", !m.shouldPlay && m.manualOn)
        m.inCall = false
        check("nach dem Call geht sie weiter", m.shouldPlay)
        m.pauseInCalls = false
        m.inCall = true
        check("„In Videocalls pausieren“ aus: läuft weiter", m.shouldPlay)
        m.toggle()
        check("im Call ausschalten geht immer", !m.shouldPlay)
    }

    print("\nLo-Fi-Musik: Einstellungen")
    do {
        let defaults = UserDefaults.standard
        let keys = ["lofiBeats", "musicSource", "musicBeatID", "spotifyURI", "appleMusicPlaylist", "musicDuringFocus",
                    "musicPauseInCalls", "musicVolume", "musicShuffle"]
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let fresh = AppSettings()
        check("frisch: eigene Beats mit den fertigen Beats, erster ausgewählt",
              fresh.musicSource == .beat && fresh.lofiBeats == LofiBeat.presets && fresh.selectedBeat == LofiBeat.presets[0])
        check("frisch: keine Musik zum Pomodoro, in Calls pausieren, zufällige Reihenfolge",
              !fresh.musicDuringFocus && fresh.musicPauseInCalls && fresh.musicShuffle)
        fresh.musicShuffle = false
        check("Zufall aus wird gespeichert", !AppSettings().musicShuffle)
        var mine = LofiBeat.presets[2]
        mine.id = UUID()
        mine.name = "Mein Beat"
        mine.set(.snare, step: 3, on: true)
        fresh.lofiBeats.append(mine)
        fresh.musicBeatID = mine.id
        fresh.musicSource = .spotify
        fresh.spotifyURI = "spotify:playlist:37i9dQZF1DWWQRwui0ExPn"
        fresh.appleMusicPlaylist = "Lo-Fi"
        fresh.musicDuringFocus = true
        let reloaded = AppSettings()
        check("eigene Beats und Quelle werden gespeichert",
              reloaded.lofiBeats.last == mine && reloaded.selectedBeat == mine && reloaded.musicSource == .spotify
              && reloaded.spotifyURI == fresh.spotifyURI && reloaded.appleMusicPlaylist == "Lo-Fi" && reloaded.musicDuringFocus)
        check("die Quelle zum Abspielen passt", reloaded.musicPlayback == .spotify(uri: "spotify:playlist:37i9dQZF1DWWQRwui0ExPn"))
        reloaded.musicSource = .appleMusic
        reloaded.appleMusicPlaylist = ""
        check("ohne Playlist ist nichts abzuspielen", reloaded.musicPlayback == nil)
        reloaded.lofiBeats.removeAll { $0.id == mine.id }
        reloaded.musicSource = .beat
        check("gelöschter Beat: der erste übernimmt", reloaded.selectedBeat == LofiBeat.presets[0])

        // Baukasten: Speichern unter, Zurücksetzen, fertige Beats wiederherstellen
        let original = LofiBeat.presets[1]
        var changed = original
        changed.bpm = 95
        changed.set(.kick, step: 5, on: true)
        let copy = changed.copy(named: "  Regen remix ")
        check("Speichern unter: neuer Beat mit neuem Namen und gleichem Inhalt",
              copy.id != changed.id && copy.name == "Regen remix" && copy.bpm == 95 && copy.kick == changed.kick)
        check("Speichern unter ohne Namen: bekommt trotzdem einen", !changed.copy(named: "   ").name.isEmpty)
        check("fertiger Beat erkennt sein Original", LofiBeat.original(of: changed) == original)
        check("geänderter fertiger Beat lässt sich zurücksetzen", changed.canReset && !original.canReset)
        check("eigener Beat hat kein Original", LofiBeat.original(of: copy) == nil && !copy.canReset)
        reloaded.lofiBeats = [copy]
        check("fehlende fertige Beats werden erkannt", reloaded.missingPresets.count == LofiBeat.presets.count)
        reloaded.restoreMissingPresets()
        check("fertige Beats wiederherstellen: alle wieder da, eigene bleiben",
              reloaded.missingPresets.isEmpty && reloaded.lofiBeats.first == copy
              && reloaded.lofiBeats.count == LofiBeat.presets.count + 1)
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    print("\nAugenpause")
    do {
        check("das Fenster ist dezenter (kleiner als früher, 30 × 28)",
              LookoutArt.width * LookoutArt.height <= 30 * 28 * 3 / 4, "\(LookoutArt.width) × \(LookoutArt.height)")
        check("die Katze sitzt ganz im Fenster, darüber noch Himmel",
              LookoutArt.height >= LookoutArt.sillTop + Frames.sitBackA.height + 4
              && LookoutArt.width >= Frames.sitBackA.width + 8, "\(LookoutArt.width) × \(LookoutArt.height)")
        check("das Fensterbrett ist gleich hoch geblieben (dort sitzt die Katze)", LookoutArt.sillTop == 5)
        check("alle Bilder der Wolke sind gleich groß",
              LookoutArt.frames.allSatisfy { $0.width == LookoutArt.width && $0.height == LookoutArt.height })
        check("die Katze passt auf das Fensterbrett", Frames.sitBackA.width <= LookoutArt.width)
    }

    print("\nName und Einrichtung")
    do {
        let settings = AppSettings()
        let before = (settings.catName, settings.onboardingDone)
        settings.catName = "  "
        check("ohne Namen heißt sie Pixelcat", settings.displayName == "Pixelcat")
        settings.catName = " Mochi "
        check("Name ohne Leerzeichen am Rand", settings.displayName == "Mochi")
        check("jede Seite hat einen Punkt, nur die Korb-Frage gehört zum Zuhause",
              OnboardingView.Step.dots.count == OnboardingView.Step.allCases.count - 1 && !OnboardingView.Step.dots.contains(.bedAccess))
        let model = PlayfulCatModel()
        for _ in 0..<200 { model.tick(0.05) }
        check("ohne Maus schläft die Begrüßungskatze weiter", model.x == 0 && model.sprite === Frames.sleepA || model.sprite === Frames.sleepB)
        model.hovering = true
        var maxX: CGFloat = 0
        for _ in 0..<2400 { model.tick(0.05); maxX = max(maxX, abs(model.x)) }
        check("mit Maus bleibt sie in ihrem kleinen Bereich", maxX <= model.range, "\(maxX)")
        model.hovering = false
        for _ in 0..<800 { model.tick(0.05) }
        check("ist die Maus weg, schläft sie wieder", model.sprite === Frames.sleepA || model.sprite === Frames.sleepB)
        settings.catName = before.0
        settings.onboardingDone = before.1
    }

    print(failed == 0 ? "\nAlle Szenarien bestanden." : "\n\(failed) Szenario(s) fehlgeschlagen.")
    exit(failed == 0 ? 0 : 1)
}
