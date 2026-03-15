import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var clockA = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckA  = DJAudioEngine()
    @StateObject private var clockB = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckB  = DJAudioEngine()

    @State private var songA: Song?
    @State private var songB: Song?

    @State private var aLockedToB = false
    @State private var bLockedToA = false

    @State private var volumeA: Double = 1.0
    @State private var volumeB: Double = 1.0

    /// Tracks which deck currently holds master status.
    /// Transfers automatically when the master stops or changes track.
    @State private var masterIsA: Bool = true

    private var aMaster: Bool { masterIsA  && deckA.isPlaying && !aLockedToB }
    private var bMaster: Bool { !masterIsA && deckB.isPlaying && !bLockedToA }

    // MARK: - Master source

    private var masterAngle: Double {
        aMaster ? clockA.angle : bMaster ? clockB.angle :
        deckA.isPlaying ? clockA.angle : deckB.isPlaying ? clockB.angle : clockA.angle
    }
    private var masterLoopIndex: Int {
        aMaster ? clockA.loopIndex : bMaster ? clockB.loopIndex :
        deckA.isPlaying ? clockA.loopIndex : deckB.isPlaying ? clockB.loopIndex : clockA.loopIndex
    }
    private var masterLabel: String {
        aMaster ? "A" : bMaster ? "B" : "·"
    }
    private var isAnythingPlaying: Bool { deckA.isPlaying || deckB.isPlaying }

    // MARK: - Sync

    private func lockSlave(master: MasterClock, masterDeck: DJAudioEngine,
                           slave: MasterClock,  slaveDeck:  DJAudioEngine) {
        guard masterDeck.isPlaying else { return }
        let totalBeats = master.beatsPerLoop * 4
        #if os(iOS)
        let ioSecs = AVAudioSession.sharedInstance().ioBufferDuration
        #else
        let ioSecs = 512.0 / 44100.0
        #endif
        let latencyBeats = ioSecs * master.bpm / 60.0
        let newBeat = master.beatPosition + latencyBeats

        slave.setBeatPosition(newBeat)
        var audioBeats = newBeat.truncatingRemainder(dividingBy: totalBeats)
        if audioBeats < 0 { audioBeats += totalBeats }
        slaveDeck.seekToAbsoluteFraction(audioBeats / totalBeats)
        slave.start()
        slaveDeck.play()
    }

    private func continuousSync(masterBeat: Double, master: MasterClock, slave: MasterClock) {
        // Don't sync while either deck is being manipulated
        guard !master.isScrubbing, !slave.isScrubbing else { return }
        slave.setBeatPosition(masterBeat)
    }

    private func toggleSyncA() {
        aLockedToB.toggle(); bLockedToA = false
        if aLockedToB {
            masterIsA = false  // B is master if A is following it
            lockSlave(master: clockB, masterDeck: deckB, slave: clockA, slaveDeck: deckA)
        }
    }
    private func toggleSyncB() {
        bLockedToA.toggle(); aLockedToB = false
        if bLockedToA {
            masterIsA = true   // A is master if B is following it
            lockSlave(master: clockA, masterDeck: deckA, slave: clockB, slaveDeck: deckB)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Color(white: 0.15).frame(height: 0.5)

                HStack(spacing: 0) {
                    // Volume fader A — left edge
                    VerticalFader(value: $volumeA)
                        .frame(width: 28)

                    Color(white: 0.12).frame(width: 0.5)

                    DeckView(label: "A",
                             isMaster: aMaster,
                             syncLocked: aLockedToB,
                             onSync: toggleSyncA,
                             clock: clockA, deck: deckA,
                             currentSong: $songA)

                    Color(white: 0.15).frame(width: 0.5)

                    DeckView(label: "B",
                             isMaster: bMaster,
                             syncLocked: bLockedToA,
                             onSync: toggleSyncB,
                             clock: clockB, deck: deckB,
                             currentSong: $songB)

                    Color(white: 0.12).frame(width: 0.5)

                    // Volume fader B — right edge
                    VerticalFader(value: $volumeB)
                        .frame(width: 28)
                }
            }
        }
        .onChange(of: clockA.absoluteBeat) { _, beat in
            guard bLockedToA else { return }
            continuousSync(masterBeat: beat, master: clockA, slave: clockB)
        }
        .onChange(of: clockB.absoluteBeat) { _, beat in
            guard aLockedToB else { return }
            continuousSync(masterBeat: beat, master: clockB, slave: clockA)
        }
        .onChange(of: deckA.isPlaying) { _, playing in
            if playing {
                // A starts: claim master only if B isn't already playing as master
                if !deckB.isPlaying { masterIsA = true }
            } else {
                // A stops: release lock on B, hand master to B if it's playing
                if bLockedToA { bLockedToA = false }
                if deckB.isPlaying { masterIsA = false }
            }
        }
        .onChange(of: deckB.isPlaying) { _, playing in
            if playing {
                if !deckA.isPlaying { masterIsA = false }
            } else {
                if aLockedToB { aLockedToB = false }
                if deckA.isPlaying { masterIsA = true }
            }
        }
        .onChange(of: volumeA) { _, v in deckA.setVolume(Float(v)) }
        .onChange(of: volumeB) { _, v in deckB.setVolume(Float(v)) }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            VStack {
                Text("cuts the music")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 10)

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

// MARK: - Vertical fader

struct VerticalFader: View {
    @Binding var value: Double   // 0..1, 1 = top (full volume)

    var body: some View {
        GeometryReader { geo in
            let h      = geo.size.height
            let knobH: CGFloat = 36
            let travel = h - knobH
            let knobY  = travel * (1.0 - CGFloat(value))

            ZStack(alignment: .top) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Fill (active portion below knob)
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: knobY + knobH)
                    Capsule()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 3)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Knob
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: 22, height: knobH)
                    .frame(maxWidth: .infinity)
                    .padding(.top, knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { g in
                        value = max(0, min(1, 1.0 - Double(g.location.y / h)))
                    }
            )
        }
    }
}

#Preview {
    ContentView()
}
