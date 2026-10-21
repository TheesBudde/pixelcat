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
- **Pausen-Erinnerung:** Alle 45–55 Minuten läuft sie in die Bildschirmmitte und streckt sich.
- **Eigenheiten:** Zwischendurch putzt sie Pfote und Kopf, gähnt, streckt sich nach dem
  Aufwachen und rollt sich manchmal auf den Rücken.
- **Tageszeit:** Tagsüber (9–19 Uhr) ist sie unternehmungslustig und macht nur kurze
  Nickerchen. Morgens und abends ist sie gemütlich. Nachts (23–6 Uhr) schläft sie lange und
  legt sich nach dem Aufscheuchen sofort wieder hin.

## Starten

```bash
./build.sh
open build/Pixelkatze.app
```

Die App hat **kein Dock-Symbol**. Sie lebt in der **Menüleiste** oben rechts (Katzenkopf-Symbol):

| Menüpunkt | Wirkung |
|---|---|
| Katze ausblenden / einblenden (⌘K) | An- und Ausschalten |
| Pomodoro starten / beenden | Fokus-Modus mit 25/5-Minuten-Rhythmus |
| Pausen-Erinnerung | Alle 45–55 Minuten Strecken in der Bildschirmmitte (an/aus) |
| Füttern | Napf hinstellen |
| Mit Wollknäuel spielen | Knäuel an/aus – mit der Maus greifen und werfen |
| Aufscheuchen | Wie ein Klick auf die Katze |
| Schlafen legen | Sie legt sich sofort hin |
| Farbe → Orange getigert / Schwarz / Grau getigert | Fellfarbe (wird gemerkt) |
| Größe → Klein / Mittel / Groß | Pixelgröße 2, 3 oder 4 Punkte (wird gemerkt) |
| Pixelkatze beenden (⌘Q) | App beenden |

Startest du die App erneut, während sie ausgeblendet ist, kommt die Katze zurück.
Wenn du sie dauerhaft haben willst, zieh `build/Pixelkatze.app` in den Ordner *Programme*
und füge sie unter *Systemeinstellungen → Allgemein → Anmeldeobjekte* hinzu.

## Technische Skizze

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
     Klick ──► zusammenzucken → weglaufen → verschnaufen → (laufen) → hinlegen …
     Maus streicht drüber ──► genießen & anschmiegen → wieder einkuscheln / weiterlaufen
  ```
  Wie viele Runden sie läuft, wie lange sie schläft und wie weit sie wegrennt, hängt
  von der Uhrzeit ab (`Temperament`). Dazu blinzelt sie zwischendurch und atmet im Schlaf.
- **Streicheln:** 30-mal pro Sekunde wird die Mausposition abgefragt. Bewegt sich die
  Maus über den Katzenpixeln, ohne dass eine Taste gedrückt ist, zählt das als Streicheln.
  Dafür braucht die App keine besonderen Rechte.
- **Menüleisten-Symbol:** als Vektorgrafik gezeichnet, damit es auf jedem Bildschirm scharf ist.
- **Napf und Knäuel:** eigene kleine Fenster. Das Knäuel hat eine einfache Physik
  (Schwerkraft, Abprallen, Rollreibung) und lässt sich ziehen und werfen.
- **Klicks:** Nur sichtbare Katzenpixel reagieren (`hitTest`). Die durchsichtige Fläche
  drumherum lässt Klicks durch.
- **Vorschau der Sprites:** `build/Pixelkatze.app/Contents/MacOS/Pixelkatze --export-preview vorschau.png`

## Eigene Posen malen

In `Sources/Sprites.swift` einfach die Textraster ändern und `./build.sh` erneut ausführen.
