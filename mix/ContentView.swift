import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var clockA = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckA  = DJAudioEngine()
    @StateObject private var clockB = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckB  = DJAudioEngine()

    @State private var songA: Song?
    @State private var songB: Song?

    // MARK: - Master source

    private var masterAngle: Double {
        deckA.isPlaying ? clockA.angle : deckB.isPlaying ? clockB.angle : clockA.angle
    }
    private var masterLoopIndex: Int {
        deckA.isPlaying ? clockA.loopIndex : deckB.isPlaying ? clockB.loopIndex : clockA.loopIndex
    }
    private var masterLabel: String {
        deckA.isPlaying ? "A" : deckB.isPlaying ? "B" : "·"
    }
    private var isAnythingPlaying: Bool { deckA.isPlaying || deckB.isPlaying }

    // MARK: - Sync

    /// Beat-phase sync with IO-latency compensation.
    /// Snaps slave to nearest beat + master's sub-beat phase,
    /// then pre-advances by one IO buffer so clock and audio land together.
    private func syncDeck(master: MasterClock, masterDeck: DJAudioEngine,
                          slave: MasterClock,  slaveDeck:  DJAudioEngine) {
        guard masterDeck.isPlaying else { return }

        let bpm          = master.bpm
        let totalBeats   = master.beatsPerLoop * 4          // 64

        // Master's fractional phase within one beat (0 ..< 1)
        let masterPhase  = master.beatPosition.truncatingRemainder(dividingBy: 1.0)

        // Slave: snap to nearest beat, then transplant master's sub-beat phase
        let slaveSnapped = slave.beatPosition.rounded()

        // Compensate for render latency so audio & clock arrive in phase
        #if os(iOS)
        let ioSecs = AVAudioSession.sharedInstance().ioBufferDuration
        #else
        let ioSecs = 512.0 / 44100.0
        #endif
        let latencyBeats = ioSecs * bpm / 60.0

        let newBeatPos   = slaveSnapped + masterPhase + latencyBeats
        slave.setBeatPosition(newBeatPos)

        var audioBeats = newBeatPos.truncatingRemainder(dividingBy: totalBeats)
        if audioBeats < 0 { audioBeats += totalBeats }
        slaveDeck.seekToAbsoluteFraction(audioBeats / totalBeats)

        // Bring the slave in immediately
        slave.start()
        slaveDeck.play()
    }

    private func syncA() { syncDeck(master: clockB, masterDeck: deckB, slave: clockA, slaveDeck: deckA) }
    private func syncB() { syncDeck(master: clockA, masterDeck: deckA, slave: clockB, slaveDeck: deckB) }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Color(white: 0.15).frame(height: 0.5)

                HStack(spacing: 0) {
                    DeckView(label: "A",
                             isMaster: deckA.isPlaying,
                             onSync: syncA,
                             clock: clockA, deck: deckA,
                             currentSong: $songA)

                    Color(white: 0.15).frame(width: 0.5)

                    DeckView(label: "B",
                             isMaster: deckB.isPlaying && !deckA.isPlaying,
                             onSync: syncB,
                             clock: clockB, deck: deckB,
                             currentSong: $songB)
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            // App name
            VStack {
                Text("cuts the music")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 10)

            // Three wheels
            HStack(spacing: 0) {
                // Deck A wheel
                deckWheelBadge(clock: clockA, isPlaying: deckA.isPlaying, label: "A")
                    .frame(maxWidth: .infinity)

                // Master wheel (centre, larger)
                VStack(spacing: 4) {
                    Text("MASTER")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .tracking(2)
                    MasterWheelView(angle: masterAngle,
                                    loopIndex: masterLoopIndex,
                                    size: 72)
                        .opacity(isAnythingPlaying ? 1 : 0.22)
                    Text(masterLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                // Deck B wheel
                deckWheelBadge(clock: clockB, isPlaying: deckB.isPlaying, label: "B")
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func deckWheelBadge(clock: MasterClock, isPlaying: Bool, label: String) -> some View {
        VStack(spacing: 4) {
            MasterWheelView(angle: clock.angle, loopIndex: clock.loopIndex, size: 40)
                .opacity(isPlaying ? 1 : 0.28)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

#Preview {
    ContentView()
}
