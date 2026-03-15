import SwiftUI

// MARK: - DeckView

struct DeckView: View {
    let label: String
    var isMaster: Bool = false
    var syncLocked: Bool = false
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
            // ── Scrub zone — waveform + bezier line ───────────────────
            GeometryReader { geo in
                ZStack {
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
                            let delta = -(dy / geo.size.height) * 2 * .pi * 0.1
                            clock.scrub(angleDelta: delta)
                            deck.scrubByAngleDelta(delta)
                            lineOffset = value.translation.height * 0.1
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

            // ── Song title row (fixed height) ─────────────────────────
            songTitleRow
                .frame(height: 36)
                .padding(.horizontal, 12)

            // ── Unified control bar: load | ▐▐ | ▶ | ⇄ ──────────────
            controlBar
                .frame(height: 50)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            // ── Cue strip ─────────────────────────────────────────────
            CueStrip(isLoaded: deck.isLoaded) { quarter in
                cue(quarter)
            }
            .frame(height: 40)
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

    // ── Song title row ─────────────────────────────────────────────────

    @ViewBuilder
    private var songTitleRow: some View {
        if let song = currentSong {
            VStack(spacing: 1) {
                Text(song.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
        }
    }

    // ── Unified control bar ────────────────────────────────────────────

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Load button
            loadBtn
            divider

            // Pause
            transportBtn("pause.fill", enabled: deck.isLoaded) {
                clock.stop(); deck.pause()
            }
            divider

            // Play
            transportBtn("play.fill", enabled: deck.isLoaded) {
                clock.start(); deck.play()
            }

            // Sync — only when provided
            if onSync != nil {
                divider
                syncBtn
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 0.5, height: 22)
    }

    // Load / re-load button — pulsing red ring until a song is loaded
    @ViewBuilder
    private var loadBtn: some View {
        Button { showPicker = true } label: {
            ZStack {
                if currentSong == nil {
                    Circle()
                        .stroke(Color.red.opacity(pulse ? 0.85 : 0.25), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                }
                Image(systemName: currentSong == nil ? "plus" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    private func transportBtn(_ image: String,
                               enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var syncBtn: some View {
        Button { onSync?() } label: {
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(syncLocked ? Color.green : isMaster ? Color.white.opacity(0.2) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(syncLocked ? Color.green.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(isMaster && !syncLocked)
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
                        .frame(maxHeight: .infinity)
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
