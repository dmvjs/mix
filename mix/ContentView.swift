import SwiftUI

struct ContentView: View {
    @StateObject private var clockA = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckA  = DJAudioEngine()
    @StateObject private var clockB = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckB  = DJAudioEngine()

    @State private var songA: Song?
    @State private var songB: Song?

    // MARK: - Master wheel source

    private var masterAngle: Double {
        if deckA.isPlaying { return clockA.angle }
        if deckB.isPlaying { return clockB.angle }
        return clockA.angle
    }

    private var masterLoopIndex: Int {
        if deckA.isPlaying { return clockA.loopIndex }
        if deckB.isPlaying { return clockB.loopIndex }
        return clockA.loopIndex
    }

    private var masterSourceLabel: String {
        if deckA.isPlaying { return "A" }
        if deckB.isPlaying { return "B" }
        return "·"
    }

    private var isAnythingPlaying: Bool { deckA.isPlaying || deckB.isPlaying }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Master wheel ──────────────────────────────────────
                masterSection

                Color(white: 0.15).frame(height: 0.5)

                // ── Two decks side-by-side ────────────────────────────
                HStack(spacing: 0) {
                    DeckView(label: "A",
                             clock: clockA, deck: deckA,
                             currentSong: $songA)

                    Color(white: 0.15).frame(width: 0.5)

                    DeckView(label: "B",
                             clock: clockB, deck: deckB,
                             currentSong: $songB)
                }
            }
        }
    }

    // MARK: - Master section

    private var masterSection: some View {
        VStack(spacing: 6) {
            Text("MASTER")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.25))
                .tracking(3)

            ZStack {
                MasterWheelView(angle: masterAngle,
                                loopIndex: masterLoopIndex,
                                size: 88)
                    .opacity(isAnythingPlaying ? 1 : 0.3)

                // Source label inside wheel
                Text(masterSourceLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .offset(y: 0)
            }

            // Active deck pill
            Text(masterSourceLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 20)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .opacity(isAnythingPlaying ? 1 : 0.25)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
