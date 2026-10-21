# Pixelkatze 🐈

Eine kleine Pixel-Art-Katze, die auf der Oberkante deines Docks hin und her läuft,
sich irgendwann hinlegt und schläft. Klickst du sie an, erschrickt sie, springt hoch
und rennt davon. Danach beruhigt sie sich und legt sich wieder hin.

## Starten

```bash
./build.sh
open build/Pixelkatze.app
```

Die App hat **kein Dock-Symbol**. Sie lebt in der **Menüleiste** oben rechts (Katzenkopf-Symbol):

| Menüpunkt | Wirkung |
|---|---|
| Katze ausblenden / einblenden (⌘K) | An- und Ausschalten |
| Aufscheuchen | Wie ein Klick auf die Katze |
| Schlafen legen | Sie legt sich sofort hin |
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
- **Fenster (`Cat.swift` → `CatController`):** Ein kleines, randloses `NSPanel` mit
  durchsichtigem Hintergrund. Es wird 30-mal pro Sekunde auf die Position der Katze
  verschoben. Die Unterkante liegt auf `visibleFrame.minY`, also genau auf dem Dock.
  `.nonactivatingPanel` sorgt dafür, dass ein Klick auf die Katze dem gerade aktiven
  Programm nicht den Fokus wegnimmt.
- **Grafik (`Sprites.swift`):** Jede Pose ist ein Textraster, ein Buchstabe pro Pixel und
  Farbe (`K` Umriss, `O` Fell, `o` Streifen, `W` weiß, `P` rosa, `E` Augen). Gezeichnet
  wird Pixel für Pixel als Quadrat, also bewusst „blockig“. Nach links wird gespiegelt.
  Augen-zu-Varianten und die Umrisse von „Z“ und „!“ werden automatisch erzeugt.
- **Verhalten (`Cat.swift` → `CatBrain`):** ein Zustandsautomat:

  ```
  stehen ⇄ laufen (1–3×) → hinsetzen → hinlegen → schlafen (Zzz, 45–150 s) → aufwachen → stehen …
            Klick ──► erschrecken (Sprung + „!“) → wegrennen → verschnaufen → laufen → hinlegen …
  ```
  Dazu blinzelt sie zwischendurch und atmet im Schlaf.
- **Klicks:** Nur sichtbare Katzenpixel reagieren (`hitTest`). Die durchsichtige Fläche
  drumherum lässt Klicks durch.
- **Vorschau der Sprites:** `build/Pixelkatze.app/Contents/MacOS/Pixelkatze --export-preview vorschau.png`

## Eigene Posen malen

In `Sources/Sprites.swift` einfach die Textraster ändern und `./build.sh` erneut ausführen.
