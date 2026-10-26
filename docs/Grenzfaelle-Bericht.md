# Grenzfälle: Durchsicht vom 26. Oktober 2026

Ich habe Pausen, Erinnerungen, Videocalls, Ruhemodus, Pomodoro, Timer und das Tagesritual darauf geprüft, wie sie
zusammenspielen. Alles unten Genannte ist behoben und mit Tests abgesichert, sofern es sich ohne Bildschirm testen
lässt.

## Deine Fragen

**Tag gestartet, aber nicht beendet?**
Ab Feierabend fragt sie „Tag beenden?“ und nach Daumen runter in deinem Abstand erneut, bis zum Ende des Kalendertags.
Bisher war der Tag nach Mitternacht verloren und ließ sich nicht mehr beenden. Jetzt gilt:
- Bis zum nächsten Arbeitsbeginn kannst du den gestrigen Tag noch beenden. Im Menü steht dann „Tag beenden …“, und
  arbeitest du nach Mitternacht weiter, fragt sie auch.
- Ab dem neuen Arbeitsbeginn bleibt der gestrige Tag offen. In der Statistik zählen dann nur Stimmung, To-dos und
  Ziele vom Morgen. Erledigt-Quoten zählen nur bei beendeten Tagen, das verzerrt also nichts.

**Tag nicht gestartet?**
Zwischen Beginn und Feierabend fragt sie „Tag starten?“, nach Daumen runter in deinem Abstand erneut. Nach Feierabend
fragt sie nicht mehr nach dem Start. Der Tag erscheint dann einfach nicht im Tagebuch. Die Feierabend-Blase kommt in
dem Fall wie gewohnt, wenn sie eingeschaltet ist. Bisher fiel sie bei eingeschaltetem Ritual ganz weg.

**Wie verhalten sich die Pausen zueinander?**
- Pausenfrage und Tagesfrage kommen nie gleichzeitig. Die Pausenfrage wartet, solange eine Tagesfrage, eine
  Erinnerung oder das Tagesfenster offen ist, und kommt eine Minute danach.
- „Pause machen“ im Menü räumt eine offene Tagesfrage weg, sie kommt später wieder.
- Pomodoro, Timer und Ruhemodus räumen offene Fragen ohne Wertung weg. In der Statistik zählt das also nicht als
  „weggedrückt“.
- Bist du seit 5 Minuten nicht am Rechner, wenn die Pausenerinnerung fällig ist, gilt das als Pause. Es kommt keine
  Frage, und die Zeit beginnt neu.

## Gefundene und behobene Fehler

1. **Übungsblase verschwand.** Beim Antworten auf eine Frage wurde *irgendeine* Blase weggeräumt. Kam zum Beispiel
   eine Frage ins Leere, während die geführte Pause lief, platzte die Übungsblase. Jetzt räumt jede Frage nur ihre
   eigene Blase weg.
2. **Pausenfrage im Videocall.** Die Pausenfrage kam auch während Calls, und da Calls bis zu 3 Minuten dauern, wurde
   sie dann als „weggedrückt“ gezählt. Jetzt wartet sie bis nach dem Call.
3. **Napf im Call auf dem geteilten Bildschirm.** Begann ein Call, während Napf, Augenpausen-Fenster oder Vogel zu
   sehen waren, blieben die stehen, beim Bildschirmteilen für alle sichtbar. Jetzt verschwinden sie, und die
   Erinnerung kommt nach dem Call noch einmal. Trinken kommt nur dann erneut, wenn es noch nicht beantwortet war.
   Das prüft ein neuer Selbsttest.
4. **Offene Fragen bei Call, Pomodoro, Timer und Ruhemodus.** Sie blieben stehen oder wurden später als
   „weggedrückt“ gezählt. Jetzt werden sie ohne Wertung weggeräumt und kommen später wieder.
5. **Aufgaben gingen im Pomodoro verloren.** Aufgaben haben jetzt eine feste Uhrzeit, kamen aber während
   Pomodoro-Fokus und Timer nie, und nach 3 Stunden waren sie weg. Jetzt kommen sie auch im Fokus als Blase über der
   schlafenden Katze bzw. am Dock. Sie wird dafür nicht geweckt.
6. **Feierabend nach dem Aufklappen am Morgen.** War der Mac über Nacht im Ruhezustand, kam beim Aufklappen am
   Morgen die Blase „Feierabend“ vom Vorabend. Jetzt kommt sie nur, wenn der Feierabend höchstens eine Stunde her ist.
7. **Pausenfrage gleich nach dem Aufklappen.** Nach dem Ruhezustand war die Pausenerinnerung überfällig und kam
   sofort. Jetzt zählt der Ruhezustand als Pause, und die Zeit beginnt neu.
8. **„Tag beenden?“ gleich nach spätem Start.** Wer erst um 18 Uhr startete, wurde sofort gefragt, ob er den Tag
   beenden will. Jetzt kommt die Frage frühestens eine Stunde nach dem Start.
9. **Am Wochenende von Hand gestartet.** Bei „Nur Montag bis Freitag“ kam abends nie „Tag beenden?“. Jetzt doch.
   Ungefragt startet sie am Wochenende weiterhin nicht.
10. **Tagesfenster über Mitternacht.** Wer das Fenster vor Mitternacht öffnete und danach auf Fertig klickte,
    speicherte in den falschen Tag. Jetzt gehört das Fenster fest zu seinem Tag.
11. **Tagesfenster doppelt geöffnet.** Ein zweiter Klick im Menü setzte alles Eingetragene zurück. Jetzt holt er
    das offene Fenster nur nach vorn.
12. **Statistik beim Installieren verloren.** Der Installationsbefehl beendet die App mit `pkill`. Dabei gingen bis
    zu eine Minute Statistik verloren, weil nur im normalen Beenden gespeichert wurde. Jetzt speichert sie auch dann.
13. **Motivation am Abend ohne Feierabend-Erinnerung.** Der Abendspruch richtete sich nur nach der
    Feierabend-Erinnerung. Jetzt richtet er sich nach dem Feierabend deines Arbeitstags.
14. **Feierabend vor Beginn.** Stellt man das ein, fragt sie nie. Jetzt erscheint ein orangefarbener Hinweis in den
    Einstellungen. Ein Arbeitstag über Mitternacht wird nicht unterstützt.

## Bewusst so gelassen (sag Bescheid, wenn du es anders willst)

- **„Tag beendet“ ist endgültig.** Wer sich verklickt, kann den Tag nicht wieder öffnen. Eine Rückgängig-Möglichkeit
  wäre ein kleiner Zusatz.
- **Ruhemodus und Ritual.** Im Ruhemodus fragt sie auch nicht nach dem Tag. Das Menü funktioniert trotzdem.
- **Mehrere Bildschirme und „mit Musik“.** Musik zählt Ton über das Standard-Ausgabegerät. Ton über ein anderes
  Gerät, etwa ein zweites Headset, zählt nicht.
- **„Pause machen“ während einer Pausenfrage** beantwortet die Frage mit Daumen hoch. Das wirkt natürlich, zählt
  aber nur als *eine* Pause.

## Nicht live prüfbar

Alles mit Fenstern, Klicks, Tönen und dem echten Dock habe ich in Tests nachgespielt, nicht auf dem Bildschirm
gesehen. Der Selbsttest deckt das ab:

```bash
/Applications/Pixelcat.app/Contents/MacOS/Pixelcat --selftest
/Applications/Pixelcat.app/Contents/MacOS/Pixelcat --selftest calls
```
