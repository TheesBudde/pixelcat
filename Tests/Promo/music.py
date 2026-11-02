# Eigene Chiptune-Musik für den Werbeclip (30 s, 120 BPM, C-Dur), dazu die Katzenlaute der App (CC0).
# Reines Python, ohne Zusatzpakete. Aufruf: python3 music.py <ausgabe.wav> <sounds-ordner>
import array
import math
import random
import sys
import wave

RATE = 44100
LENGTH = 30.0
BEAT = 0.5          # 120 BPM
BAR = 4 * BEAT
out = array.array("f", [0.0]) * int(RATE * LENGTH)
random.seed(7)


def freq(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def add(start, duration, note, wave_form, volume, attack=0.005, release=0.04, duty=0.5):
    """Einen Ton hinzufügen (Rechteck, Dreieck)"""
    f = freq(note)
    begin = int(start * RATE)
    count = int(duration * RATE)
    for i in range(count):
        index = begin + i
        if index >= len(out):
            break
        t = i / RATE
        phase = (t * f) % 1.0
        if wave_form == "square":
            value = 1.0 if phase < duty else -1.0
        else:  # Dreieck
            value = 4 * abs(phase - 0.5) - 1
        envelope = min(1.0, t / attack) * min(1.0, (duration - t) / release) if duration > release else 1.0
        envelope *= 0.75 + 0.25 * math.exp(-t * 6)  # kurzer Anschlag, dann etwas leiser
        out[index] += value * volume * max(0.0, envelope)


def kick(start, volume=0.5):
    begin = int(start * RATE)
    for i in range(int(0.18 * RATE)):
        t = i / RATE
        f = 150 * math.exp(-t * 22) + 45
        out[begin + i] += math.sin(2 * math.pi * f * t) * volume * math.exp(-t * 16)


def noise(start, duration, volume, decay):
    begin = int(start * RATE)
    for i in range(int(duration * RATE)):
        t = i / RATE
        if begin + i < len(out):
            out[begin + i] += (random.random() * 2 - 1) * volume * math.exp(-t * decay)


def sample(path, start, volume):
    """Eine WAV-Datei (mono, 16 Bit, 44,1 kHz) einmischen"""
    with wave.open(path) as file:
        frames = file.readframes(file.getnframes())
    data = array.array("h", frames)
    begin = int(start * RATE)
    for i, value in enumerate(data):
        if begin + i < len(out):
            out[begin + i] += value / 32768 * volume


# Akkorde je Takt (C, G, Am, F), als Grundton der Basslinie und Arpeggio-Töne
CHORDS = {"C": (48, [60, 64, 67, 72]), "G": (43, [59, 62, 67, 71]), "Am": (45, [57, 60, 64, 69]), "F": (41, [57, 60, 65, 69])}
PROGRESSION = ["C", "G", "Am", "F"] * 4

# Melodie in Achteln (None = Pause), Teil A und Teil B
A = [[76, 79, 84, 79, 76, 74, 72, None], [74, 79, 83, 79, 74, 72, 71, None],
     [72, 76, 81, 76, 72, 71, 69, None], [69, 72, 77, 76, 74, 72, 74, None]]
B = [[79, None, 76, 79, 84, None, 83, 84], [83, None, 79, 83, 86, None, 84, 83],
     [81, None, 76, 81, 84, None, 83, 81], [77, 79, 81, 84, 83, 81, 79, None]]
MELODY = {2: A, 6: B, 10: A}

for bar in range(15):
    start = bar * BAR
    if bar == 14:
        # Schlussakkord, lang ausklingend
        add(start, 2.0, 36, "triangle", 0.22, release=1.2)
        for n in [60, 64, 67, 72]:
            add(start, 2.0, n + 12, "square", 0.045, release=1.4, duty=0.25)
        add(start, 2.0, 84, "square", 0.12, release=1.5)
        kick(start, 0.45)
        continue
    chord = CHORDS[PROGRESSION[bar]]
    # Bass: Grundton und Oktave in Achteln
    for step in range(8):
        add(start + step * BEAT / 2, BEAT / 2 * 0.9, chord[0] + (12 if step % 2 else 0), "triangle", 0.20)
    # Arpeggio in Sechzehnteln, leise
    for step in range(16):
        add(start + step * BEAT / 4, BEAT / 4 * 0.8, chord[1][step % 4] + 12, "square", 0.035, duty=0.25)
    # Schlagzeug ab Takt 2
    if bar >= 2:
        for beat in range(4):
            t = start + beat * BEAT
            if beat in (0, 2):
                kick(t)
            else:
                noise(t, 0.12, 0.16, 28)       # Snare
            noise(t + BEAT / 2, 0.04, 0.05, 90)  # Hi-Hat
    else:
        kick(start, 0.35)
    # Melodie
    for first, part in MELODY.items():
        if first <= bar < first + 4:
            for step, note in enumerate(part[bar - first]):
                if note is not None:
                    add(start + step * BEAT / 2, BEAT / 2 * 0.92, note, "square", 0.11)

# Katzenlaute: Miau zum Titel, Schnurren beim Streicheln, Miau im Abspann
sounds = sys.argv[2]
sample(sounds + "/miau-erinnerung.wav", 0.35, 0.9)
sample(sounds + "/schnurren.wav", 6.0, 0.55)
sample(sounds + "/miau-pause.wav", 26.2, 0.9)

# Ein- und Ausblenden, normalisieren
fade_in, fade_out = int(0.15 * RATE), int(1.6 * RATE)
for i in range(fade_in):
    out[i] *= i / fade_in
for i in range(fade_out):
    out[len(out) - 1 - i] *= i / fade_out
peak = max(abs(v) for v in out) or 1
scale = 0.85 / peak
pcm = array.array("h", (int(max(-1, min(1, v * scale)) * 32767) for v in out))
with wave.open(sys.argv[1], "w") as file:
    file.setnchannels(1)
    file.setsampwidth(2)
    file.setframerate(RATE)
    file.writeframes(pcm.tobytes())
print("✓ Musik:", sys.argv[1])
