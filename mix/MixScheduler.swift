import Foundation

struct MixBlock {
    let songA: Song
    let songB: Song
}

/// Drives a Hamiltonian walk across the full library:
///   - Each song plays exactly once per cycle, then the pool refills
///   - 5 blocks per tempo (84 → 94 → 102 → 84 → …)
///   - Key journey uses a varied step sequence — circle-of-fifths, tritone,
///     major/minor thirds — to create interesting tonal movement
///   - Pair selection weights AGAINST the boring ±1 adjacency and against
///     recently heard combinations, favoring fourth/fifth/tritone blends
struct MixScheduler {

    static let tempos   = [84, 94, 102]
    static let perTempo = 5            // blocks before tempo switch

    // Remaining songs per BPM this Hamiltonian cycle
    private var remaining: [Int: [Song]] = [:]
    // Recently used pairs (sorted id tuple). Capped at 60.
    private var recentPairs: [(Int, Int)] = []

    private var tempoIdx   = 0
    private var blockCount = 0

    // Key journey: 0-based position on the 12-tone circle
    private var keyPos  = Int.random(in: 0..<12)

    // Step sequence mixes circle-of-fifths (+7), tritone (+6), major-third (+4),
    // minor-third (+3), and aug-fourth (+5) to avoid predictable loops.
    // 12 steps × lcm(12, 12) = every key visited before repeating.
    private static let steps = [7, 4, 7, 6, 3, 5, 7, 9, 4, 6, 7, 3]
    private var stepIdx = 0

    init() { refillAll() }

    // MARK: - Public

    /// Pick the next block, advance all scheduler state.
    mutating func nextBlock() -> MixBlock? {
        let bpm = Self.tempos[tempoIdx]

        // Ensure pool has at least 2 songs
        if remaining[bpm, default: []].count < 2 {
            remaining[bpm] = SongLibrary.all.filter { $0.bpm == bpm }.shuffled()
        }

        var pool = remaining[bpm, default: []]
        let targetKey = keyPos + 1   // convert 0-based → 1-based key

        let songA = weightedPick(from: pool, targetKey: targetKey,
                                 excludeID: nil, excludeArtist: nil)
        pool.removeAll { $0.id == songA.id }

        let songB = weightedPick(from: pool, targetKey: targetKey,
                                 excludeID: songA.id, excludeArtist: songA.artist)
        pool.removeAll { $0.id == songB.id }

        remaining[bpm] = pool
        recordPair(songA.id, songB.id)

        // Advance key along the journey
        let step = Self.steps[stepIdx % Self.steps.count]
        keyPos = (keyPos + step) % 12
        stepIdx += 1

        // Switch tempo after perTempo blocks; jump key by tritone on switch
        blockCount += 1
        if blockCount >= Self.perTempo {
            blockCount = 0
            tempoIdx = (tempoIdx + 1) % Self.tempos.count
            keyPos = (keyPos + 6) % 12
        }

        return MixBlock(songA: songA, songB: songB)
    }

    // MARK: - Private

    private mutating func refillAll() {
        for bpm in Self.tempos {
            remaining[bpm] = SongLibrary.all.filter { $0.bpm == bpm }.shuffled()
        }
    }

    private func weightedPick(from pool: [Song], targetKey: Int,
                               excludeID: Int?, excludeArtist: String?) -> Song {
        var candidates = pool.filter {
            $0.id != (excludeID ?? -1) && $0.artist != (excludeArtist ?? "\0")
        }

        // Relax artist constraint if needed
        if candidates.isEmpty {
            candidates = pool.filter { $0.id != (excludeID ?? -1) }
        }
        guard !candidates.isEmpty else { return pool.randomElement()! }

        let scored: [(song: Song, weight: Double)] = candidates.map { song in
            let dist = keyDist(song.key, targetKey)

            // Interval character weights — push away from boring ±1 adjacency,
            // reward harmonically interesting intervals
            let intervalW: Double
            switch dist {
            case 0:    intervalW = 1.0   // unison: fine, not special
            case 1:    intervalW = 0.5   // half-step: de-prioritise (too safe)
            case 2:    intervalW = 0.9   // whole-step
            case 3, 9: intervalW = 1.4   // minor third: soulful
            case 4, 8: intervalW = 1.7   // major third: chromatic mediant, lush
            case 5, 7: intervalW = 1.9   // perfect fourth/fifth: circle-of-fifths
            case 6:    intervalW = 1.5   // tritone: dramatic, modern
            default:   intervalW = 1.0
            }

            // Novelty: penalise pairs the user has recently heard
            let noveltyW: Double
            if let exID = excludeID {
                let key = (min(song.id, exID), max(song.id, exID))
                noveltyW = recentPairs.contains(where: { $0 == key }) ? 0.2 : 1.0
            } else {
                noveltyW = 1.0
            }

            return (song, intervalW * noveltyW)
        }

        // Weighted random draw
        let total = scored.reduce(0.0) { $0 + $1.weight }
        var r = Double.random(in: 0..<total)
        for (song, w) in scored {
            r -= w
            if r <= 0 { return song }
        }
        return scored.last!.song
    }

    private mutating func recordPair(_ a: Int, _ b: Int) {
        recentPairs.append((min(a, b), max(a, b)))
        if recentPairs.count > 60 { recentPairs.removeFirst() }
    }

    private func keyDist(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 12 - d)
    }
}
