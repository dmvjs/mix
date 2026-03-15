import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var clockA = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckA  = DJAudioEngine()
    @StateObject private var clockB = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckB  = DJAudioEngine()

    @State private var songA: Song?
    @State private var songB: Song?

    // Persistent sync locks
    @State private var aLockedToB = false   // A follows B
    @State private var bLockedToA = false   // B follows A

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

    // MARK: - Sync helpers

    /// Snap slave to master's exact file position and start it playing.
    private func lockSlave(master: MasterClock, masterDeck: DJAudioEngine,
                           slave: MasterClock,  slaveDeck:  DJAudioEngine) {
        guard masterDeck.isPlaying else { return }

        let totalBeats = master.beatsPerLoop * 4   // 64

        // IO latency compensation
        #if os(iOS)
        let ioSecs = AVAudioSession.sharedInstance().ioBufferDuration
        #else
        let ioSecs = 512.0 / 44100.0
        #endif
        let latencyBeats = ioSecs * master.bpm / 60.0

        // Copy master's exact beat position into slave (same place in the file)
        let newBeat = master.beatPosition + latencyBeats
        slave.setBeatPosition(newBeat)

        var audioBeats = newBeat.truncatingRemainder(dividingBy: totalBeats)
        if audioBeats < 0 { audioBeats += totalBeats }
        slaveDeck.seekToAbsoluteFraction(audioBeats / totalBeats)

        slave.start()
        slaveDeck.play()
    }

    /// Called every clock tick when a lock is active — keeps slave at master's exact position.
    private func continuousSync(masterBeat: Double,
                                master: MasterClock, masterDeck: DJAudioEngine,
                                slave: MasterClock,  slaveDeck:  DJAudioEngine) {
        guard masterDeck.isPlaying, !slave.isScrubbing else { return }

        let totalBeats = master.beatsPerLoop * 4
        slave.setBeatPosition(masterBeat)
        var frac = masterBeat.truncatingRemainder(dividingBy: totalBeats) / totalBeats
        if frac < 0 { frac += 1 }
        slaveDeck.seekToAbsoluteFraction(frac)
    }

    // MARK: - Toggle actions

    private func toggleSyncA() {
        aLockedToB.toggle()
        bLockedToA = false   // only one direction at a time
        if aLockedToB { lockSlave(master: clockB, masterDeck: deckB, slave: clockA, slaveDeck: deckA) }
    }

    private func toggleSyncB() {
        bLockedToA.toggle()
        aLockedToB = false
        if bLockedToA { lockSlave(master: clockA, masterDeck: deckA, slave: clockB, slaveDeck: deckB) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Color(white: 0.15).frame(height: 0.5)

                HStack(spacing: 0) {
                    DeckView(label: "A",
                             isMaster: deckA.isPlaying && !aLockedToB,
                             syncLocked: aLockedToB,
                             onSync: toggleSyncA,
                             clock: clockA, deck: deckA,
                             currentSong: $songA)

                    Color(white: 0.15).frame(width: 0.5)

                    DeckView(label: "B",
                             isMaster: deckB.isPlaying && !deckA.isPlaying && !bLockedToA,
                             syncLocked: bLockedToA,
                             onSync: toggleSyncB,
                             clock: clockB, deck: deckB,
                             currentSong: $songB)
                }
            }
        }
        // Continuous lock: B follows A
        .onChange(of: clockA.absoluteBeat) { _, beat in
            guard bLockedToA else { return }
            continuousSync(masterBeat: beat,
                           master: clockA, masterDeck: deckA,
                           slave: clockB,  slaveDeck: deckB)
        }
        // Continuous lock: A follows B
        .onChange(of: clockB.absoluteBeat) { _, beat in
            guard aLockedToB else { return }
            continuousSync(masterBeat: beat,
                           master: clockB, masterDeck: deckB,
                           slave: clockA,  slaveDeck: deckA)
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
                deckWheelBadge(clock: clockA, isPlaying: deckA.isPlaying, label: "A")
                    .frame(maxWidth: .infinity)

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
