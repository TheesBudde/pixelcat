import AppKit

/// Selbsttest auf dem echten Bildschirm (Start mit `--selftest`): spielt Trinken, Augenpause, Aufgabe,
/// Blase anklicken, Feierabend und Trinken im Streifzug/Katzenkorb nacheinander durch, prüft dabei Fenster,
/// Positionen und Abläufe und schreibt ein Protokoll. Die Einstellungen bleiben unverändert; am Ende beendet
/// sich das Programm.
@MainActor
final class SelfTest {
    private let cat: CatController
    private let settings: AppSettings
    private var lines: [String] = []
    private var failures = 0
    private var checks = 0
    private let started = Date()
    private var lastPhase = ""

    /// Protokoll im Projektordner, wenn es ihn gibt – sonst auf dem Schreibtisch
    private let logURL: URL = {
        let project = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Claude Code/Pixelkatze/build")
        let folder = FileManager.default.fileExists(atPath: project.path) ? project
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return folder.appendingPathComponent("selftest.log")
    }()

    init(cat: CatController, settings: AppSettings) {
        self.cat = cat
        self.settings = settings
    }

    /// `calls`: nur den Videocall-Test (Start mit `--selftest calls`)
    func start(calls: Bool = false) {
        Task { @MainActor in
            if calls { await runCalls() } else { await run() }
            finish()
        }
    }

    // MARK: Videocall

    /// Spielt einen Videocall nach (ohne Kamera und Mikrofon): Die Katze versteckt sich, Trinken wartet, die Aufgabe
    /// erscheint nur als Blase am Dock – wenn so eingestellt, und nie beim Teilen des Bildschirms.
    private func runCalls() async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log("Pixelcat \(version) – Videocall-Test am \(Date())")
        cat.breakReminders = false
        cat.drinkMinutes = nil
        cat.eyeBreakMinutes = nil
        cat.tasksEnabled = false
        cat.hideDuringCalls = true
        cat.show()
        let task = TaskItem(text: "Selbsttest: im Call", time: TaskItem.defaultTime)
        cat.selfTestTasks([task])
        cat.roaming = false
        await waitUntil("Katze ist zu sehen", 60) { !$0.isAway && $0.catFrame != nil }

        section("Call mit „Auch während Videocalls“ an")
        cat.tasksDuringCalls = true
        cat.simulatedCall = .camera
        log("   (Kamera an – nachgespielt)")
        await waitUntil("Katze versteckt sich", 60) { $0.isAway }
        cat.showErrandNow(.drink)
        cat.showErrandNow(.task)
        await waitUntil("Aufgaben-Blase erscheint ohne Katze", 15) { $0.bubble?.frame != nil && $0.isAway }
        if let frame = cat.snapshot().bubble?.frame, let screen = NSScreen.screens.first {
            check("Blase steht unten am Dock", frame.minY < screen.visibleFrame.minY + 120, "Unterkante bei \(Int(frame.minY))")
        }
        let drinkWaits = cat.snapshot().queued.contains(.drink) && cat.snapshot().errand == .task
        check("Trinken wartet bis nach dem Call", drinkWaits, "\(cat.snapshot().queued)")
        await waitUntil("Blase verschwindet von selbst", 45) { $0.bubble == nil }
        await pause(2)
        check("Trinken wartet immer noch", cat.snapshot().errand == nil && cat.snapshot().queued.contains(.drink))

        section("Bildschirm wird geteilt")
        cat.simulatedCall = .screenSharing
        log("   (Bildschirmfreigabe – nachgespielt)")
        await pause(16)
        cat.showErrandNow(.task)
        await pause(6)
        check("keine Aufgaben-Blase, solange der Bildschirm geteilt wird", cat.snapshot().bubble == nil)

        section("Call mit „Auch während Videocalls“ aus")
        cat.simulatedCall = .microphone
        cat.tasksDuringCalls = false
        log("   (Mikrofon an – nachgespielt)")
        await pause(16)
        check("keine Aufgaben-Blase im Call", cat.snapshot().bubble == nil)

        section("Call vorbei")
        cat.simulatedCall = nil
        log("   (Call beendet – nachgespielt)")
        await waitUntil("Katze kommt zurück", 60) { !$0.isAway && $0.catFrame != nil }
        await waitUntil("jetzt kommt das Trinken (oder die Aufgabe) dran", 40) { $0.errand != nil }
        await waitUntil("Trinken ist dran", 120) { $0.errand == .drink }
        await waitUntil("erledigt", 120) { $0.errand == nil && $0.bowl == nil }

        cat.selfTestTasks(nil)
        cat.apply(settings)
    }

    // MARK: Ablauf

    private func run() async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log("Pixelcat \(version) – Selbsttest am \(Date())")
        log("Bildschirm: \(NSScreen.screens.first.map { "\($0.frame), sichtbar \($0.visibleFrame)" } ?? "keiner")")
        // Geplante Erinnerungen ruhen lassen, damit nichts dazwischenkommt
        cat.breakReminders = false
        cat.drinkMinutes = nil
        cat.eyeBreakMinutes = nil
        cat.tasksEnabled = false
        cat.show()

        section("Vorbereitung")
        cat.roaming = false
        await waitUntil("Katze ist zu sehen", 60) { !$0.isAway && $0.catFrame != nil }
        await pause(3)

        await drinking(roaming: false)
        await lookout()
        await task()
        await motivation()
        await bubbleClick()
        await quittingTime()

        section("Streifzug bzw. Katzenkorb")
        cat.roaming = true
        await waitUntil("geht weg (Körbchen oder zur Seite hinaus)", 90) { $0.isAway }
        await pause(2)
        await drinking(roaming: true)

        section("Pause nach Aktivität")
        let idle = cat.snapshot().idleSeconds
        check("Leerlaufzeit lässt sich abfragen", idle >= 0 && idle < 24 * 3600, "\(idle) s seit der letzten Eingabe")

        // Alles wie vorher
        cat.apply(settings)
    }

    private func drinking(roaming: Bool) async {
        section(roaming ? "Trinken (Streifzug/Korb)" : "Trinken")
        let meowsBefore = cat.snapshot().meows
        cat.showErrandNow(.drink)
        await waitUntil("Wassernapf steht", 10) { $0.errand == .drink && $0.bowl?.water == true && $0.bowl?.frame != nil }
        checkMeow("miaut zum Trinken", before: meowsBefore, expected: true)
        if let bowl = cat.snapshot().bowl, let frame = bowl.frame {
            check("Napf steht an seiner Stelle", abs(frame.midX - bowl.x) < 2, "Fenster \(frame.midX), Napf \(bowl.x)")
        }
        await waitUntil("Blase über der Katze zu sehen", 90) { self.bubbleAboveCat($0) }
        await waitUntil("trinkt", 90) { $0.phase == "drinking" }
        let snap = cat.snapshot()
        if let bowl = snap.bowl {
            check("steht dabei am Napf", abs(snap.catCenter - bowl.x) < 14 * snap.scale,
                  "Katze \(Int(snap.catCenter)), Napf \(Int(bowl.x))")
        }
        let start = Date()
        await waitUntil("hört auf zu trinken", 40) { $0.phase != "drinking" }
        let drank = Date().timeIntervalSince(start)
        check("trinkt 20–30 Sekunden", drank >= 20 && drank <= 31, String(format: "%.1f s", drank))
        await waitUntil("erledigt: Napf und Blase weg", 40) { $0.errand == nil && $0.bowl == nil && $0.bubble == nil }
        if roaming {
            await waitUntil("ist danach wieder weg", 90) { $0.isAway }
        }
        await pause(3)
    }

    private func lookout() async {
        section("Augenpause")
        let meowsBefore = cat.snapshot().meows
        cat.showErrandNow(.lookout)
        await waitUntil("Fenster ploppt auf", 10) { $0.lookout?.frame != nil }
        checkMeow("miaut zur Augenpause", before: meowsBefore, expected: true)
        await waitUntil("Fenster ganz eingeblendet", 5) { ($0.lookout?.alpha ?? 0) >= 0.99 }
        await waitUntil("setzt sich davor und schaut hinaus", 60) { $0.phase == "gazing" }
        await pause(0.5)
        let snap = cat.snapshot()
        if let window = snap.lookout, let frame = window.frame, let catFrame = snap.catFrame {
            check("sitzt mittig vor dem Fenster", abs(snap.catCenter - window.x) < 2 * snap.scale,
                  "Katze \(Int(snap.catCenter)), Fenster \(Int(window.x))")
            check("Fenster steht auf demselben Boden wie die Katze", abs(frame.minY - catFrame.minY) < 1.5,
                  "Fenster \(frame.minY), Katze \(catFrame.minY)")
            check("Katze ist vor dem Fenster (nicht dahinter)", window.catAbove)
            check("Fenster hat volle Größe", abs(frame.width - CGFloat(LookoutArt.width) * snap.scale) < 1.5,
                  "\(frame.width) statt \(CGFloat(LookoutArt.width) * snap.scale)")
        }
        let start = Date()
        await waitUntil("schaut eine Weile hinaus", 40) { $0.phase != "gazing" }
        let gazed = Date().timeIntervalSince(start) + 0.5
        check("schaut ungefähr 25 Sekunden", gazed >= 23 && gazed <= 27, String(format: "%.1f s", gazed))
        await waitUntil("Fenster blendet aus", 10) { $0.lookout == nil }
        await waitUntil("erledigt", 10) { $0.errand == nil }
        await pause(3)
    }

    private func task() async {
        section("Aufgabe")
        cat.selfTestTasks([TaskItem(text: "Selbsttest: Mama anrufen", time: TaskItem.defaultTime)])
        let meowsBefore = cat.snapshot().meows
        cat.showErrandNow(.task)
        await waitUntil("Blase mit der Aufgabe über der Katze", 10) { self.bubbleAboveCat($0) }
        checkMeow(settings.meowForTasks ? "miaut bei der Aufgabe (eingestellt)" : "miaut nicht bei der Aufgabe (eingestellt)",
                  before: meowsBefore, expected: settings.meowForTasks)
        await waitUntil("Blase verschwindet von selbst", 45) { $0.bubble == nil }
        await waitUntil("erledigt", 5) { $0.errand == nil }
        await pause(3)
    }

    private func motivation() async {
        section("Motivation")
        let meowsBefore = cat.snapshot().meows
        cat.showErrandNow(.motivation)
        await waitUntil("Blase mit einem Spruch über der Katze", 10) { self.bubbleAboveCat($0) }
        checkMeow("miaut zur Motivation", before: meowsBefore, expected: true)
        await waitUntil("Blase verschwindet von selbst", 50) { $0.bubble == nil }
        await waitUntil("erledigt", 5) { $0.errand == nil }
        await pause(3)
    }

    private func bubbleClick() async {
        section("Blase anklicken")
        cat.showErrandNow(.task)
        await waitUntil("Blase erscheint", 10) { self.bubbleAboveCat($0) }
        await pause(1)
        cat.selfTestPopBubble()
        await waitUntil("platzt sofort", 2) { $0.bubble == nil }
        await waitUntil("erledigt", 3) { $0.errand == nil }
        cat.selfTestTasks(nil)
        await pause(3)
    }

    private func quittingTime() async {
        section("Feierabend")
        let hatBefore = cat.snapshot().hat
        cat.showErrandNow(.quittingTime)
        await waitUntil("setzt Zylinder und Fliege auf", 5) { $0.hat == "Zylinder" || $0.hat == "Feiertagshut" }
        await waitUntil("Blase „Feierabend“ über der Katze", 10) { self.bubbleAboveCat($0) }
        await waitUntil("streckt sich in der Mitte", 60) { $0.phase == "stretching" }
        if let screen = NSScreen.screens.first {
            let snap = cat.snapshot()
            check("ist in der Bildschirmmitte", abs(snap.catCenter - screen.frame.midX) < screen.frame.width * 0.25,
                  "Katze \(Int(snap.catCenter)), Mitte \(Int(screen.frame.midX))")
        }
        await waitUntil("erledigt", 75) { $0.errand == nil }
        await pause(3)
        log("   Outfit vorher: \(hatBefore ?? "keins"), jetzt: \(cat.snapshot().hat ?? "keins")")
    }

    // MARK: Werkzeuge

    /// Blase ist zu sehen und steht über der Katze
    private func bubbleAboveCat(_ snap: CatController.Snapshot) -> Bool {
        guard let frame = snap.bubble?.frame, let cat = snap.catFrame else { return false }
        return frame.minY >= cat.minY + 5 && frame.maxX > cat.minX && frame.minX < cat.maxX
    }

    @discardableResult
    private func waitUntil(_ label: String, _ timeout: Double,
                           _ condition: @escaping (CatController.Snapshot) -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let snap = cat.snapshot()
            if snap.phase != lastPhase {
                log(String(format: "      %6.1f s  Phase: %@", Date().timeIntervalSince(started), snap.phase))
                lastPhase = snap.phase
            }
            if condition(snap) {
                check(label, true, String(format: "nach %.1f s", Date().timeIntervalSince(start)))
                return true
            }
            await pause(0.2)
        }
        let snap = cat.snapshot()
        check(label, false, "Zeitüberschreitung nach \(Int(timeout)) s – Phase \(snap.phase), Erinnerung "
              + "\(snap.errand.map { "\($0)" } ?? "keine"), Napf \(snap.bowl != nil), Fenster \(snap.lookout != nil), "
              + "Blase \(snap.bubble != nil), weg \(snap.isAway)")
        return false
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Miauen prüfen – nur wenn es gerade erlaubt ist (Töne an, kein Fokus, kein Call)
    private func checkMeow(_ label: String, before: Int, expected: Bool) {
        guard cat.soundsAllowed else {
            log("   – \(label): übersprungen (Miauen gerade aus, Fokus oder Call)")
            return
        }
        let meowed = cat.snapshot().meows > before
        check(label, meowed == expected, meowed ? "hat miaut" : "still")
    }

    private func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        checks += 1
        if !ok { failures += 1 }
        log("   \(ok ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
    }

    private func section(_ title: String) {
        log("\n▸ \(title)")
    }

    private func log(_ line: String) {
        print(line)
        fflush(stdout)
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func finish() {
        log("\n\(failures == 0 ? "Alles in Ordnung" : "\(failures) von \(checks) Prüfungen fehlgeschlagen") – "
            + "\(checks) Prüfungen in \(Int(Date().timeIntervalSince(started))) s. Protokoll: \(logURL.path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }
}
