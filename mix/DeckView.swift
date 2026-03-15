import SwiftUI

// MARK: - DeckView

struct DeckView: View {
    let label: String

    @ObservedObject var clock: MasterClock
    @ObservedObject var deck:  DJAudioEngine
    @Binding var currentSong: Song?

    @State private var selectedBPM  = 94
    @State private var showPicker   = false
    @State private var scrubActive  = false
    @State private var prevY: CGFloat = 0
    @State private var lineOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // ── Scrub line ─────────────────────────────────────────
                DeckScrubLine(offset: lineOffset)
                    .allowsHitTesting(false)

                // ── Deck label (top-leading corner) ────────────────────
                VStack {
                    HStack {
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.leading, 14)
                            .padding(.top, 10)
                        Spacer()
                    }
                    Spacer()
                }

                // ── Controls ───────────────────────────────────────────
                VStack(spacing: 12) {
                    MasterWheelView(angle: clock.angle, loopIndex: clock.loopIndex)

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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                        } else {
                            Label("Select Track", systemImage: "music.note")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    DeckTransportBar(
                        isLoaded: deck.isLoaded,
                        onPause: { clock.stop();  deck.pause() },
                        onPlay:  { clock.start(); deck.play()  }
                    )
                }
                .fixedSize()
                .padding(.bottom, 28)
            }
            // Full-zone scrub gesture
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
        .sheet(isPresented: $showPicker) {
            SongPickerView(selectedBPM: $selectedBPM) { song in
                showPicker = false
                load(song: song)
            }
        }
        .onAppear { showPicker = true }
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
