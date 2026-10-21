# Pixelkatze 🐈

Eine kleine Pixel-Art-Katze (orange getigert, schwarz oder grau getigert), die auf der Oberkante deines Docks hin und her
läuft, sich irgendwann hinlegt und schläft. Im Liegen bewegt sie ab und zu ruhig die
Schwanzspitze.

- **Streicheln:** Fährst du mit der Maus über sie, ohne zu klicken, wacht sie auf,
  kneift zufrieden die Augen zu und schmiegt sich an. Danach kuschelt sie sich wieder ein.
- **Aufscheuchen:** Ein Klick lässt sie kurz zusammenzucken und ein Stück weglaufen.
- **Füttern:** Ein Napf erscheint, die Katze läuft hin, frisst ihn leer und putzt sich danach.
- **Wollknäuel:** Ein Knäuel fällt herein, die Katze jagt es und schlägt mit der Tatze danach.
  Du kannst es mit der Maus greifen, hochheben und werfen.
- **Pomodoro:** 25 Minuten Fokus, in denen die Katze tief schläft und sich nicht aufscheuchen
  lässt. Danach wacht sie auf, streckt sich und läuft 5 Minuten herum. Dann beginnt die
  nächste Runde. Die Restzeit steht neben dem Symbol in der Menüleiste.
- **Klettern:** Im Kletter-Modus zieht es sie nach oben: Sobald ein passendes Fenster offen ist,
  klettert sie an der Seite hoch oder springt hinauf, balanciert oben entlang, springt von Fenster
  zu Fenster und hält dort auch ihre Nickerchen. Nur selten kommt sie freiwillig herunter. Verschiebst du ein Fenster, fährt sie mit;
  schließt du es, fällt sie aufs Dock. Bei Vollbild oder Split View bleibt sie auf dem Dock.
  Über dem Fenster muss etwas Platz bis zur Menüleiste sein, sonst passt sie nicht hin.
- **Streifzug:** Die Katze geht nach draußen und ist nicht mehr zu sehen. Nur wenn Pause ist
  (Pomodoro-Pause, Pausen-Erinnerung oder abgelaufener Timer), kommt sie herein, läuft in die Bildschirmmitte, streckt
  sich, miaut und bummelt dort 5 Minuten herum. Danach geht sie wieder. Ohne Streifzug ist sie
  wie gewohnt die ganze Zeit da.
- **Miauen:** Leise, echte Katzenlaute zu Beginn der Pomodoro-Pause, zurück an die Arbeit und
  bei der Pausen-Erinnerung. Im Menü unter „Miauen“ ganz abschaltbar.
- **Timer:** Eine eigene Zeit stellen (Schnellwahl 5–60 Minuten oder „Eigene Zeit …“, z. B. `25`
  oder `1:30`). Solange er läuft, schläft die Katze; läuft er ab, wacht sie auf, geht in die
  Bildschirmmitte, streckt sich, miaut und sucht dort dezent Aufmerksamkeit – strecken, dich
  mit langsamem Blinzeln anschauen, auf dem Rücken rekeln –, bis du sie streichelst oder anklickst.
  Erst dann ist der Timer vorbei (im Streifzug geht sie danach wieder hinaus). Pausen-Erinnerungen gibt es trotzdem – der Timer zählt
  währenddessen weiter. Timer und Pomodoro schließen sich gegenseitig aus.
- **Gedankenblase:** Erinnert sie an eine Pause (Pausen-Erinnerung, Pomodoro-Pause), schwebt über ihrem Kopf
  eine Wolke mit „PAUSE“ bzw. „BREAK“. Ein Klick lässt sie platzen, sonst platzt sie am Ende der Pause.
- **Pausen-Erinnerung:** Alle 45–55 Minuten läuft sie in die Bildschirmmitte und streckt sich.
- **Eigenheiten:** Zwischendurch putzt sie Pfote und Kopf, gähnt, streckt sich nach dem
  Aufwachen (vorne absenken, tief strecken und wippen, Hinterbein nach hinten) und rollt sich
  manchmal auf den Rücken.
- **Rücksichtsvoll:** Bei Videocalls (Kamera oder Mikrofon an) und Bildschirmfreigabe geht sie automatisch
  auf Streifzug und kommt danach zurück. Ist ein macOS-Fokus aktiv, ist sie still und schläft mehr.
- **Schnurren:** beim Streicheln, sanft ein- und ausgeblendet.
- **Mauszeiger jagen:** Ruht die Maus knapp über dem Dock, schleicht sie sich an, wackelt mit dem Hinterteil
  und springt (nicht im Streifzug).
- **Feiertage:** Kürbis an Halloween, Weihnachtsmütze am 24./25. Dezember, Partyhut an Silvester und Neujahr
  (immer an).
- **Mehrere Bildschirme:** Ist ein Bildschirm daneben angeschlossen, läuft sie ab und zu hinüber.
- **Zweisprachig:** Deutsch und Englisch.
- **Tageszeit:** Tagsüber (9–19 Uhr) ist sie unternehmungslustig und macht nur kurze
  Nickerchen. Morgens und abends ist sie gemütlich. Nachts (23–6 Uhr) schläft sie lange und
  legt sich nach dem Aufscheuchen sofort wieder hin.

## Starten

```bash
./build.sh
open build/Pixelkatze.app
```

Die App hat **kein Dock-Symbol**. Sie lebt in der **Menüleiste** oben rechts (Katzenkopf-Symbol).
Das Menü enthält nur, was man oft braucht:

| Menüpunkt | Wirkung |
|---|---|
| Katze ausblenden / einblenden (⌘K) | An- und Ausschalten |
| Pomodoro | Fokus und Pause im Wechsel (Haken = läuft) |
| Timer ▸ 5 … 60 Min. / Eigene Zeit … | Timer stellen (Haken = läuft, nochmal klicken beendet) |
| Pausen-Erinnerung | regelmäßige Pausen (an/aus) |
| Streifzug | Katze geht nach draußen und kommt nur zu Pausen vorbei (an/aus) |
| Füttern · Mit Wollknäuel spielen · Aufscheuchen · Schlafen legen | Aktionen |
| Einstellungen … (⌘,) | Fenster mit allem Weiteren |
| Pixelkatze beenden (⌘Q) | App beenden |

**Einstellungsfenster** – eine Seite zum Durchscrollen, nur Schalter, Segmente und Schieberegler:
- **Aussehen:** Fellfarbe, Größe
- **Verhalten:** Klettern, Mauszeiger jagen, auf andere Bildschirme wechseln, Streifzug
- **Pomodoro & Pausen:** Fokus- und Pausenlänge, Pausen-Erinnerung mit frühestens/spätestens, Länge einer Pause
- **Töne & Rücksicht:** Miauen, Schnurren, bei Videocall/Bildschirmfreigabe verstecken, Fokus berücksichtigen
- **Sprache:** wie macOS, Deutsch, English

Startest du die App erneut, während sie ausgeblendet ist, kommt die Katze zurück.
Wenn du sie dauerhaft haben willst, zieh `build/Pixelkatze.app` in den Ordner *Programme*
und füge sie unter *Systemeinstellungen → Allgemein → Anmeldeobjekte* hinzu.

## Technische Skizze

Eine einseitige Übersicht der Architektur gibt es als PDF:
[docs/architektur/pixelkatze-architektur.pdf](docs/architektur/pixelkatze-architektur.pdf)
(LaTeX-Quelltext daneben, kompilierbar mit XeLaTeX, z. B. `tectonic pixelkatze-architektur.tex`).

```
┌──────────── Menüleiste ─────────────────────────── [🐱] ◄── NSStatusItem (AppDelegate)
│                                                       │     Menü: an/aus, Größe, Beenden
│                                                       │
│                     ┌────────┐                        │
│                     │ /\_/\  │ ◄── randloses, durchsichtiges NSPanel (CatController)
│                     │ (o.o)  │     • schwebt über allen Fenstern, auf allen Spaces
│  ═══════════════════╧════════╧═══  ◄── Oberkante Dock = NSScreen.visibleFrame.minY
│  [ Dock  ⬜ ⬜ ⬜ ⬜ ⬜ ⬜ ⬜ ]
└──────────────────────────────────────────────────────
```

- **Sprache:** Swift mit AppKit, ohne Xcode-Projekt. `build.sh` ruft `swiftc` auf und
  baut daraus ein `.app`-Paket (mit `LSUIElement`, also ohne Dock-Symbol).
- **Fenster (`Controller.swift` → `CatController`):** Ein kleines, randloses `NSPanel` mit
  durchsichtigem Hintergrund. Es wird 30-mal pro Sekunde auf die Position der Katze
  verschoben. Die Unterkante liegt auf `visibleFrame.minY`, also genau auf dem Dock.
  `.nonactivatingPanel` sorgt dafür, dass ein Klick auf die Katze dem gerade aktiven
  Programm nicht den Fokus wegnimmt.
- **Grafik (`Sprites.swift`):** Jede Pose ist ein Textraster mit einem Buchstaben pro Pixel
  (`K` Umriss, `O` Fell, `h` Glanz, `s` Streifen, `W` Brust/Pfoten, `E` Augen, `P` Nase/Ohren,
  `w` Schnurrhaare). Welche Farbe ein Buchstabe bekommt, legt die Fellfarbe (`Coat`) fest.
  Bei der schwarzen Katze sind Streifen und Brust einfach auch schwarz. Gezeichnet
  wird Pixel für Pixel als Quadrat, also bewusst „blockig“. Nach links wird gespiegelt.
  Die Varianten mit geschlossenen und zufriedenen Augen werden automatisch erzeugt.
- **Verhalten (`Cat.swift` → `CatBrain`):** ein Zustandsautomat:

  ```
  stehen ⇄ laufen (⇄ putzen) → hinsetzen → hinlegen (→ Rücken) → schlafen → aufwachen → strecken/gähnen …
     Napf ──► hinlaufen → fressen → putzen
     Knäuel ──► jagen → mit der Tatze schlagen → (zuschauen / putzen) → jagen …
     Pomodoro ──► Fokus: schlafen (lässt sich nicht stören) ⇄ Pause: aufwachen, strecken, laufen
     Klettern ──► Wand hoch / hinaufspringen → oben laufen ⇄ zum Nachbarfenster springen → runter
     Klick ──► zusammenzucken → weglaufen → verschnaufen → (laufen) → hinlegen …
     Maus streicht drüber ──► genießen & anschmiegen → wieder einkuscheln / weiterlaufen
  ```
  Wie viele Runden sie läuft, wie lange sie schläft und wie weit sie wegrennt, hängt
  von der Uhrzeit ab (`Temperament`). Dazu blinzelt sie zwischendurch und atmet im Schlaf.
- **Streicheln:** 30-mal pro Sekunde wird die Mausposition abgefragt. Bewegt sich die
  Maus über den Katzenpixeln, ohne dass eine Taste gedrückt ist, zählt das als Streicheln.
  Dafür braucht die App keine besonderen Rechte.
- **Menüleisten-Symbol:** als Vektorgrafik gezeichnet, damit es auf jedem Bildschirm scharf ist.
- **Fenster zum Klettern:** `CGWindowListCopyWindowInfo` liefert fünfmal pro Sekunde die Positionen
  aller Fenster – ohne Sonderrechte, da keine Fenstertitel gelesen werden. Von jeder Oberkante wird
  abgezogen, was Fenster weiter vorne verdecken (`CatController.perches`). Ein Fenster in voller
  Bildschirmhöhe heißt Vollbild oder Split View – dann wird nicht geklettert.
- **Töne (`Resources/Sounds`):** echte Katzenaufnahmen (Miauen und Schnurren) aus „Cat Purr & Meow“ von Kerzoven
  (https://opengameart.org/content/cat-purr-meow, CC0 / gemeinfrei), zugeschnitten und angeglichen.
- **Napf und Knäuel:** eigene kleine Fenster. Das Knäuel hat eine einfache Physik
  (Schwerkraft, Abprallen, Rollreibung) und lässt sich ziehen und werfen.
- **Sensoren (`Sensors.swift`):** Ob Kamera oder Mikrofon benutzt werden, fragt die App über CoreMediaIO
  und CoreAudio ab – ohne Berechtigung. Bildschirmfreigabe erkennt sie an den Prozessen der macOS-Freigabe
  und von Zoom. Den Fokus-Status gibt macOS nur nach einmaliger Zustimmung heraus (`INFocusStatusCenter`).
- **Energie sparen:** Der Takt läuft nur bei Bewegung mit 30 Bildern pro Sekunde, in Ruhe mit 8 und
  ist die Katze weg, nur zweimal pro Sekunde.
- **Einstellungen (`Settings.swift`):** ein Modell (`AppSettings`) für alles, gespeichert in UserDefaults;
  das Fenster ist in SwiftUI gebaut. Texte stehen zweisprachig direkt im Code (`L10n.s("Deutsch", "English")`).
- **Klicks:** Nur sichtbare Katzenpixel reagieren (`hitTest`). Die durchsichtige Fläche
  drumherum lässt Klicks durch.
- **Vorschau der Sprites:** `build/Pixelkatze.app/Contents/MacOS/Pixelkatze --export-preview vorschau.png`

## Vorführen

```bash
open build/Pixelkatze.app --args --demo
```

Im Demo-Modus ist für die Katze immer Nachmittag (sie ist aktiv) und sie klettert deutlich öfter.
Mit `--outfit pumpkin`, `--outfit santa` oder `--outfit party` lassen sich die Feiertags-Verkleidungen vorführen.

## Eigene Posen malen

In `Sources/Sprites.swift` einfach die Textraster ändern und `./build.sh` erneut ausführen.

## Neue Version veröffentlichen

```bash
./release.sh v4.1
```

Das baut die App für Apple Silicon und Intel und legt `build/Pixelkatze-v4.1.zip` an.
Die Datei dann auf GitHub unter *Releases → Draft a new release* hochladen.
