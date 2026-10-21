import AppKit

/// Katzenlaute, synthetisch erzeugt (keine Tondateien nötig).
/// Ein Grundton mit Obertönen, dessen Tonhöhe auf- und absteigt, gefiltert durch
/// wandernde Vokal-Formanten – so wird aus einem Piepen ein „Mi-a-u“.
@MainActor
enum Meow {
    /// Langes, freundliches Miau – zum Beginn der Pause
    static func playMeow() { play(meow) }
    /// Kurzes, gurrendes „Mrrp“ – zurück an die Arbeit
    static func playTrill() { play(trill) }

    private static var current: NSSound?

    private static func play(_ data: Data) {
        guard let sound = NSSound(data: data) else { return }
        sound.volume = 0.35
        current = sound
        sound.play()
    }

    static let meow = render(Voice(
        duration: 0.75,
        pitch: [(0, 470), (0.35, 720), (0.7, 560), (1, 400)],
        vowels: [(0, .i), (0.3, .i), (0.55, .a), (1, .u)],
        purr: 0))

    static let trill = render(Voice(
        duration: 0.4,
        pitch: [(0, 380), (0.6, 540), (1, 470)],
        vowels: [(0, .u), (0.5, .a), (1, .u)],
        purr: 0.45))

    // MARK: Synthese

    private struct Formants {
        let f: (Double, Double, Double)
        static let i = Formants(f: (350, 2200, 3000))
        static let a = Formants(f: (850, 1350, 2700))
        static let u = Formants(f: (400, 900, 2400))
    }

    private struct Voice {
        let duration: Double
        /// Tonhöhe über die Zeit (Anteil 0…1, Hertz)
        let pitch: [(Double, Double)]
        let vowels: [(Double, Formants)]
        /// Stärke des „rrr“ (schnelles Flattern der Lautstärke)
        let purr: Double
    }

    private static func interpolate(_ points: [(Double, Double)], at t: Double) -> Double {
        guard let upper = points.firstIndex(where: { $0.0 >= t }), upper > 0 else {
            return t <= points[0].0 ? points[0].1 : points[points.count - 1].1
        }
        let (t0, v0) = points[upper - 1], (t1, v1) = points[upper]
        let u = (t - t0) / max(t1 - t0, 0.0001)
        return v0 + (v1 - v0) * (u * u * (3 - 2 * u))
    }

    private static func render(_ voice: Voice) -> Data {
        let rate = 44_100.0
        let count = Int(voice.duration * rate)
        var samples = [Double](repeating: 0, count: count)
        var phase = 0.0
        var noise: UInt32 = 12345

        for n in 0..<count {
            let time = Double(n) / rate
            let t = time / voice.duration
            let vibrato = 1 + 0.015 * sin(2 * .pi * 6 * time)
            let f0 = interpolate(voice.pitch, at: t) * vibrato
            phase += 2 * .pi * f0 / rate

            let formants = (0..<3).map { k -> Double in
                interpolate(voice.vowels.map { ($0.0, [$0.1.f.0, $0.1.f.1, $0.1.f.2][k]) }, at: t)
            }
            var value = 0.0
            var harmonic = 1.0
            while harmonic * f0 < 5000 {
                let frequency = harmonic * f0
                var gain = 0.12 / harmonic
                for (k, formant) in formants.enumerated() {
                    let width = 160.0 + Double(k) * 60
                    let strength = [1.0, 0.7, 0.3][k]
                    gain += strength * exp(-pow((frequency - formant) / width, 2))
                }
                value += gain * sin(harmonic * phase)
                harmonic += 1
            }
            // etwas Hauch
            noise = noise &* 1_664_525 &+ 1_013_904_223
            value += (Double(noise >> 8) / Double(1 << 24) - 0.5) * 0.04

            let attack = min(1, time / 0.04)
            let release = min(1, (voice.duration - time) / 0.18)
            let roll = 1 - voice.purr * (0.5 + 0.5 * sin(2 * .pi * 28 * time)) * max(0, 1 - t * 1.4)
            samples[n] = value * attack * release * roll
        }

        let peak = samples.map(abs).max() ?? 1
        let pcm = samples.map { Int16(max(-1, min(1, $0 / peak * 0.8)) * Double(Int16.max)) }
        return wav(pcm, rate: Int(rate))
    }

    private static func wav(_ pcm: [Int16], rate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = pcm.count * 2
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + bytes))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(bytes))
        for sample in pcm { append(sample) }
        return data
    }
}
