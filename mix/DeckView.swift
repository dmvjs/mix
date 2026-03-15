import SwiftUI

// MARK: - DeckView

struct DeckView: View {
    let label: String
    var isMaster: Bool = false
    var onSync: (() -> Void)? = nil

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
            // ── Scrub zone — waveform lives here, bezier floats on top ──
            GeometryReader { geo in
                ZStack {
                    // Waveform scrolls vertically with playback / scrub
                    WaveformStrip(waveform: deck.waveform,
                                  currentFrame: deck.currentFrame,
                                  framesTotal: deck.framesCount)
                        .allowsHitTesting(false)

                    // Deck label – top leading corner
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

                    // Bezier scrub line on top
                    DeckScrubLine(offset: lineOffset)
                        .allowsHitTesting(false)
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

            // ── Info row: wheel + song + sync ─────────────────────────
            HStack(spacing: 10) {
                MasterWheelView(angle: clock.angle,
                                loopIndex: clock.loopIndex,
                                size: 36)
                    .opacity(deck.isLoaded ? 1 : 0.3)

                loadButton

                Spacer()

                // Sync button — disabled when this deck is the master
                if onSync != nil {
                    Button {
                        onSync?()
                    } label: {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isMaster ? Color.white.opacity(0.2) : .white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(isMaster ? 0.06 : 0.14),
                                            lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isMaster)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // ── Transport — just above cue strip ──────────────────────
            DeckTransportBar(
                isLoaded: deck.isLoaded,
                onPause: { clock.stop();  deck.pause() },
                onPlay:  { clock.start(); deck.play()  }
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            // ── Cue strip ─────────────────────────────────────────────
            CueStrip(isLoaded: deck.isLoaded) { quarter in
                cue(quarter)
            }
            .padding(.horizontal, 10)
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

// MARK: - Waveform strip  (vertical — scrolls in the scrub direction)
//
// Each row = one time bucket. Bar WIDTH = amplitude. Time flows top→bottom
// as playback advances: past content scrolls off the top, future rises from below.
// The scrub gesture directly controls scroll speed and direction.

struct WaveformStrip: View {
    let waveform: [Float]
    let currentFrame: Int
    let framesTotal: Int

    // Each of the 4 body loops has its own hue identity
    private static let loopHues: [Double] = [0.60, 0.52, 0.33, 0.08]  // blue, teal, green, amber

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            Canvas { ctx, size in
                guard !waveform.isEmpty, framesTotal > 0 else { return }

                let buckets    = waveform.count
                let rowH: CGFloat = 3
                let gap: CGFloat  = 1
                let stride        = rowH + gap
                let halfRows      = Int(size.height / stride / 2) + 2
                let progress      = Double(currentFrame) / Double(framesTotal)
                let centerBucket  = Int(progress * Double(buckets))
                let cy            = size.height / 2

                for offset in -halfRows ... halfRows {
                    let raw    = centerBucket + offset
                    let bucket = ((raw % buckets) + buckets) % buckets
                    let amp    = CGFloat(waveform[bucket])

                    // Horizontal bar, centered, width = amplitude
                    let barW   = max(3, amp * size.width * 0.88)
                    let x      = (size.width - barW) / 2
                    let y      = cy + CGFloat(offset) * stride

                    let loopIdx = Int(Double(bucket) / Double(buckets) * 4) % 4
                    let hue     = Self.loopHues[loopIdx]
                    let isPast  = offset < 0   // above center = already played
                    let color   = Color(hue: hue,
                                        saturation: isPast ? 0.25 : 0.55,
                                        brightness: isPast ? 0.4  : 0.95)
                                  .opacity(isPast ? 0.28 : 0.72)

                    var bar = Path()
                    bar.addRoundedRect(in: CGRect(x: x, y: y - rowH / 2,
                                                  width: barW, height: rowH),
                                       cornerSize: CGSize(width: 1, height: 1))
                    ctx.fill(bar, with: .color(color))
                }
            }
        }
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
