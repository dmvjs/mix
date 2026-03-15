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
    @State private var aLockedToB = false
    @State private var bLockedToA = false

    // Channel controls
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

    // Clock-only sync — no audio seek, avoids render-position discontinuities / clicks.
    // Both engines play at rate 1.0 from the same hardware clock so they stay phase-locked.
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
                    // Channel strip A (left edge)
                    ChannelStrip(volume: $volumeA, eq: $eqA)

                    Color(white: 0.12).frame(width: 0.5)

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

                    Color(white: 0.12).frame(width: 0.5)

                    // Channel strip B (right edge)
                    ChannelStrip(volume: $volumeB, eq: $eqB)
                }
            }
        }
        .onChange(of: clockA.absoluteBeat) { _, beat in
            guard bLockedToA else { return }
            continuousSync(masterBeat: beat, slave: clockB)
        }
        .onChange(of: clockB.absoluteBeat) { _, beat in
            guard aLockedToB else { return }
            continuousSync(masterBeat: beat, slave: clockA)
        }
        .onChange(of: volumeA) { _, v in deckA.setVolume(Float(v)) }
        .onChange(of: volumeB) { _, v in deckB.setVolume(Float(v)) }
        .onChange(of: eqA)     { _, eq in deckA.setEQ(eq) }
        .onChange(of: eqB)     { _, eq in deckB.setEQ(eq) }
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

// MARK: - Channel strip (EQ + volume)

struct ChannelStrip: View {
    @Binding var volume: Double     // 0..1
    @Binding var eq: EQSettings

    var body: some View {
        VStack(spacing: 0) {
            // EQ bands — top section
            VStack(spacing: 6) {
                EQBandColumn(label: "H",
                             gain: Binding(get: { eq.high }, set: { eq.high = $0 }),
                             kill: Binding(get: { eq.killHigh }, set: { eq.killHigh = $0 }))
                EQBandColumn(label: "M",
                             gain: Binding(get: { eq.mid  }, set: { eq.mid  = $0 }),
                             kill: Binding(get: { eq.killMid  }, set: { eq.killMid  = $0 }))
                EQBandColumn(label: "L",
                             gain: Binding(get: { eq.low  }, set: { eq.low  = $0 }),
                             kill: Binding(get: { eq.killLow  }, set: { eq.killLow  = $0 }))
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .frame(height: 162)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // Volume fader — remaining height
            VerticalFader(value: $volume)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 44)
    }
}

// MARK: - EQ band column (kill button + mini vertical fader)

struct EQBandColumn: View {
    let label: String
    @Binding var gain: Float   // -24 to +6 dB
    @Binding var kill: Bool

    private var faderValue: Double {
        Double((gain + 24) / 30)   // 0 = -24dB, 0.8 = 0dB, 1 = +6dB
    }

    var body: some View {
        HStack(spacing: 5) {
            // Kill button
            Button { kill.toggle() } label: {
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(kill ? Color.black : Color.white.opacity(0.55))
                    .frame(width: 14, height: 14)
                    .background(
                        kill ? Color.white : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
            .buttonStyle(.plain)

            // Mini fader
            VerticalFader(
                value: Binding(
                    get:  { faderValue },
                    set:  { gain = Float($0) * 30 - 24 }
                ),
                knobH: 8,
                dimmed: kill
            )
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vertical fader

struct VerticalFader: View {
    @Binding var value: Double   // 0..1
    var knobH: CGFloat = 24
    var dimmed: Bool = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let knobY = h * (1 - CGFloat(value)) - knobH / 2

            ZStack(alignment: .topLeading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(dimmed ? 0.04 : 0.10))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)

                // Fill below knob
                VStack(spacing: 0) {
                    Spacer()
                    Capsule()
                        .fill(Color.white.opacity(dimmed ? 0.08 : 0.35))
                        .frame(width: 3)
                        .frame(height: h * CGFloat(value))
                }
                .frame(maxWidth: .infinity)

                // Knob
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(dimmed ? 0.1 : 0.28), lineWidth: 0.5)
                    )
                    .frame(width: 22, height: knobH)
                    .frame(maxWidth: .infinity)
                    .offset(y: max(0, min(h - knobH, knobY)))
                    .opacity(dimmed ? 0.4 : 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        let v = 1.0 - Double(drag.location.y / h)
                        value = max(0, min(1, v))
                    }
            )
        }
    }
}

#Preview {
    ContentView()
}
