import SwiftUI

// MARK: - DeckView

struct DeckView: View {
    let label: String

    @ObservedObject var clock: MasterClock
    @ObservedObject var deck:  DJAudioEngine
    @Binding var currentSong: Song?

    @State private var selectedBPM = 94
    @State private var showPicker  = false
    @State private var scrubActive = false
    @State private var prevY: CGFloat  = 0
    @State private var lineOffset: CGFloat = 0
    @State private var pulse = false   // drives the red ring animation

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrub zone ─────────────────────────────────────────────
            GeometryReader { geo in
                ZStack {
                    DeckScrubLine(offset: lineOffset)
                        .allowsHitTesting(false)

                    // Deck label – top leading
                    VStack {
                        HStack {
                            Text(label)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.3))
                                .padding(.leading, 12)
                                .padding(.top, 10)
                            Spacer()
                        }
                        Spacer()
                    }

                    // Controls – centered
                    VStack(spacing: 10) {
                        MasterWheelView(angle: clock.angle,
                                        loopIndex: clock.loopIndex,
                                        size: 48)

                        loadButton

                        DeckTransportBar(
                            isLoaded: deck.isLoaded,
                            onPause: { clock.stop();  deck.pause() },
                            onPlay:  { clock.start(); deck.play()  }
                        )
                    }
                    .fixedSize()
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .onChanged { value in
                            let y = value.translation.height
                            if !scrubActive {
                                scrubActive = true
                                prevY = y
                                clock.isScrubbing = true
                                deck.startScrubbing()
                                return
                            }
                            let dy = y - prevY
                            prevY = y
                            let delta = -(dy / geo.size.height) * 2 * .pi * 0.25
                            clock.scrub(angleDelta: delta)
                            deck.scrubByAngleDelta(delta)
                            lineOffset = value.translation.height * 0.25
                        }
                        .onEnded { _ in
                            scrubActive = false
                            prevY = 0
                            clock.isScrubbing = false
                            deck.stopScrubbing()
                            deck.syncPosition(to: clock.loopFraction)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                lineOffset = 0
                            }
                        }
                )
            }

            // ── Cue strip ──────────────────────────────────────────────
            CueStrip(isLoaded: deck.isLoaded) { quarter in
                cue(quarter)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showPicker) {
            SongPickerView(selectedBPM: $selectedBPM) { song in
                showPicker = false
                load(song: song)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // ── Load button (pulsing red ring until song loaded) ───────────────

    @ViewBuilder
    private var loadButton: some View {
        Button { showPicker = true } label: {
            if let song = currentSong {
                VStack(spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(song.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            } else {
                ZStack {
                    // Pulsing red ring
                    Circle()
                        .stroke(Color.red.opacity(pulse ? 0.85 : 0.25), lineWidth: 1.5)
                        .frame(width: 46, height: 46)

                    // Glass circle button
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )

                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func cue(_ quarter: Int) {
        clock.jumpToQuarter(quarter)
        deck.seekToQuarter(quarter)
        clock.start()
        deck.play()
    }

    private func load(song: Song) {
        guard let url = Bundle.main.url(forResource: song.bodyResource, withExtension: "mp3") else {
            print("⚠️  Missing \(song.bodyResource).mp3")
            return
        }
        clock.stop()
        deck.pause()
        try? deck.load(bodyURL: url, loopCount: 4)
        currentSong = song
    }
}

// MARK: - Cue strip

struct CueStrip: View {
    let isLoaded: Bool
    let onCue: (Int) -> Void

    private let labels = ["0", "¼", "½", "¾"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                Button { onCue(i) } label: {
                    Text(labels[i])
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)

                if i < 3 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 0.5, height: 22)
                }
            }
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .opacity(isLoaded ? 1 : 0.4)
        .disabled(!isLoaded)
    }
}

// MARK: - Scrub line

struct DeckScrubLine: View {
    let offset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let cy    = size.height / 2
            let left  = size.width * 0.1
            let right = size.width * 0.9
            let mid   = size.width / 2

            var path = Path()
            path.move(to: CGPoint(x: left, y: cy))
            path.addCurve(
                to: CGPoint(x: right, y: cy),
                control1: CGPoint(x: mid - size.width * 0.15, y: cy + offset),
                control2: CGPoint(x: mid + size.width * 0.15, y: cy + offset)
            )
            ctx.stroke(path, with: .color(.white), lineWidth: 1)
        }
    }
}

// MARK: - Transport bar

struct DeckTransportBar: View {
    let isLoaded: Bool
    let onPause: () -> Void
    let onPlay:  () -> Void

    var body: some View {
        HStack(spacing: 0) {
            btn("pause.fill", action: onPause)
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 0.5, height: 20)
            btn("play.fill", action: onPlay)
        }
        .fixedSize()
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .opacity(isLoaded ? 1 : 0.35)
        .disabled(!isLoaded)
    }

    private func btn(_ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 52, height: 36)
        }
        .buttonStyle(.plain)
    }
}
