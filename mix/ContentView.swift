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
    @State private var eqA = EQSettings()
    @State private var eqB = EQSettings()

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

    private func continuousSync(masterBeat: Double, slave: MasterClock) {
        guard !slave.isScrubbing else { return }
        slave.setBeatPosition(masterBeat)
    }

    private func toggleSyncA() {
        aLockedToB.toggle(); bLockedToA = false
        if aLockedToB { lockSlave(master: clockB, masterDeck: deckB, slave: clockA, slaveDeck: deckA) }
    }
    private func toggleSyncB() {
        bLockedToA.toggle(); aLockedToB = false
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
        // Clock sync
        .onChange(of: clockA.absoluteBeat) { _, beat in
            guard bLockedToA else { return }
            continuousSync(masterBeat: beat, slave: clockB)
        }
        .onChange(of: clockB.absoluteBeat) { _, beat in
            guard aLockedToB else { return }
            continuousSync(masterBeat: beat, slave: clockA)
        }
        // Auto-release lock when master stops — slave becomes independent master
        .onChange(of: deckA.isPlaying) { _, playing in
            if !playing && bLockedToA { bLockedToA = false }
        }
        .onChange(of: deckB.isPlaying) { _, playing in
            if !playing && aLockedToB { aLockedToB = false }
        }
        // Channel controls
        .onChange(of: volumeA) { _, v in deckA.setVolume(Float(v)) }
        .onChange(of: volumeB) { _, v in deckB.setVolume(Float(v)) }
        .onChange(of: eqA)     { _, eq in deckA.setEQ(eq) }
        .onChange(of: eqB)     { _, eq in deckB.setEQ(eq) }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            // App name — centred at top
            VStack {
                Text("cuts the music")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 8)

            HStack(spacing: 0) {
                // ── Deck A channel ──────────────────────────────────────
                HStack(spacing: 8) {
                    VerticalFader(value: $volumeA)
                        .frame(width: 20)

                    VStack(spacing: 5) {
                        MasterWheelView(angle: clockA.angle, loopIndex: clockA.loopIndex, size: 40)
                            .opacity(deckA.isPlaying ? 1 : 0.28)
                        Text("A")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.35))
                        eqKills(eq: $eqA)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)

                // ── Master wheel ────────────────────────────────────────
                VStack(spacing: 4) {
                    Text("MASTER")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .tracking(2)
                    MasterWheelView(angle: masterAngle, loopIndex: masterLoopIndex, size: 72)
                        .opacity(isAnythingPlaying ? 1 : 0.22)
                    Text(masterLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                // ── Deck B channel ──────────────────────────────────────
                HStack(spacing: 8) {
                    VStack(spacing: 5) {
                        MasterWheelView(angle: clockB.angle, loopIndex: clockB.loopIndex, size: 40)
                            .opacity(deckB.isPlaying ? 1 : 0.28)
                        Text("B")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.35))
                        eqKills(eq: $eqB)
                    }

                    VerticalFader(value: $volumeB)
                        .frame(width: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
            .padding(.top, 20)   // clear the app name label
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // H / M / L kill buttons — lit white when active
    @ViewBuilder
    private func eqKills(eq: Binding<EQSettings>) -> some View {
        HStack(spacing: 3) {
            killBtn("H", on: eq.killHigh)
            killBtn("M", on: eq.killMid)
            killBtn("L", on: eq.killLow)
        }
    }

    private func killBtn(_ label: String, on binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(binding.wrappedValue ? Color.black : Color.white.opacity(0.45))
                .frame(width: 20, height: 16)
                .background(
                    binding.wrappedValue ? Color.white : Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vertical fader

struct VerticalFader: View {
    @Binding var value: Double   // 0..1, 1 = top (full)

    var body: some View {
        GeometryReader { geo in
            let h      = geo.size.height
            let knobH: CGFloat = 26
            let travel = h - knobH
            // knob y-offset from centre of the GeometryReader frame
            let offset = travel * (0.5 - CGFloat(value))

            ZStack {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 3)

                // Knob
                RoundedRectangle(cornerRadius: 5)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                    )
                    .frame(width: 20, height: knobH)
                    .offset(y: offset)
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
