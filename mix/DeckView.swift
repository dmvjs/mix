import SwiftUI

// MARK: - DeckView

struct DeckView: View {
    let label: String
    @ObservedObject var clock: MasterClock
    @ObservedObject var deck:  DJAudioEngine
    let currentSong: Song?

    @State private var volume: Float = 1.0

    // Mirror the waveform's current section hue for the volume column
    private var currentHue: Double {
        WaveformStrip.loopHues[clock.loopIndex % 4]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Waveform fills everything ────────────────────────────────────
            WaveformStrip(waveform: deck.waveform,
                          currentFrame: deck.currentFrame,
                          framesTotal: deck.framesCount,
                          framesPerLoop: deck.framesPerLoopCount)

            // ── Song info: fades up from black at the bottom ─────────────────
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, Color.black.opacity(0.93)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)

                if let song = currentSong {
                    VStack(spacing: 2) {
                        MarqueeText(text: song.title,
                                    font: .system(size: 11, weight: .semibold),
                                    color: .white)
                        MarqueeText(text: song.artist,
                                    font: .system(size: 9),
                                    color: Color.white.opacity(0.38))
                        Text("\(song.bpm) bpm  ·  key \(song.key)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.22))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 14)
                    .background(Color.black.opacity(0.93))
                }
            }

            // ── Volume column — outer edge ────────────────────────────────────
            HStack(spacing: 0) {
                if label == "A" {
                    VolumeColumn(volume: volume, hue: currentHue) { v in
                        volume = v
                        deck.setVolume(v)
                    }
                    Spacer()
                } else {
                    Spacer()
                    VolumeColumn(volume: volume, hue: currentHue) { v in
                        volume = v
                        deck.setVolume(v)
                    }
                }
            }
        }
    }
}

// MARK: - Scrolling marquee text

private struct MarqueeText: View {
    let text:  String
    let font:  Font
    let color: Color

    @State private var offset: CGFloat = 0
    @State private var textW:  CGFloat = 0
    @State private var boxW:   CGFloat = 0

    // px/s scroll speed; pause at start/end in seconds
    private static let speed: CGFloat = 28
    private static let pause: Double  = 1.8

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textW > geo.size.width

            ZStack(alignment: .leading) {
                // Invisible size probe
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { tp in
                            Color.clear.onAppear { textW = tp.size.width }
                                       .onChange(of: tp.size.width) { textW = $0 }
                        }
                    )

                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .offset(x: needsScroll ? offset : 0)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: needsScroll ? 0.82 : 1),
                        .init(color: .clear,  location: needsScroll ? 1.0  : 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .onAppear { boxW = geo.size.width }
            .onChange(of: geo.size.width) { boxW = $0 }
        }
        .frame(height: 16)
        .task(id: text) {
            offset = 0
            guard textW > boxW else { return }
            // brief pause at the start
            try? await Task.sleep(for: .seconds(Self.pause))
            while !Task.isCancelled {
                let travel   = textW - boxW + 14   // +14 for fade clearance
                let duration = Double(travel / Self.speed)
                withAnimation(.linear(duration: duration)) { offset = -travel }
                try? await Task.sleep(for: .seconds(duration + Self.pause))
                withAnimation(.linear(duration: 0.18)) { offset = 0 }
                try? await Task.sleep(for: .seconds(0.18 + Self.pause))
            }
        }
    }
}

// MARK: - Vertical volume bar

private struct VolumeColumn: View {
    let volume:   Float
    let hue:      Double
    let onChange: (Float) -> Void

    private let touchW: CGFloat = 44
    private let barW:   CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height * 0.58
            let topY   = (geo.size.height - trackH) / 2
            let fillH  = max(barW, CGFloat(volume) * trackH)
            let accent = Color(hue: hue, saturation: 0.72, brightness: 1.0)

            ZStack {
                // Inner ZStack: fills from bottom up, centered by outer ZStack
                ZStack(alignment: .bottom) {
                    // Ghost track
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: barW, height: trackH)
                    // Glow
                    Capsule()
                        .fill(accent.opacity(0.42))
                        .frame(width: 12, height: fillH)
                        .blur(radius: 6)
                    // Fill
                    Capsule()
                        .fill(accent)
                        .frame(width: barW, height: fillH)
                }
                .frame(width: touchW, height: trackH)
                // outer ZStack default-centers the inner one
            }
            .frame(width: touchW, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let t = 1.0 - (drag.location.y - topY) / trackH
                        onChange(Float(max(0, min(1, t))))
                    }
            )
        }
        .frame(width: touchW)
    }
}

// MARK: - Waveform strip (vertical — scrolls with playback)

struct WaveformStrip: View {
    let waveform:      [Float]
    let currentFrame:  Int
    let framesTotal:   Int
    let framesPerLoop: Int

    /// Shared with VolumeColumn so slider color always echoes the waveform
    static let loopHues: [Double] = [0.60, 0.52, 0.33, 0.08]  // blue, teal, green, amber

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            Canvas { ctx, size in
                guard !waveform.isEmpty, framesTotal > 0 else { return }

                let buckets     = waveform.count
                let perLoop     = max(1, framesPerLoop)
                let numLoops    = max(1, framesTotal / perLoop)
                let loopIdx     = (currentFrame / perLoop) % numLoops
                let loopProg    = Double(currentFrame % perLoop) / Double(perLoop)
                let bktsPerLoop = buckets / numLoops
                let centerBucket = loopIdx * bktsPerLoop + Int(loopProg * Double(bktsPerLoop))

                let rowH:     CGFloat = 3
                let gap:      CGFloat = 1
                let stride    = rowH + gap
                let halfRows  = Int(size.height / stride / 2) + 2
                let cy        = size.height / 2

                for offset in -halfRows ... halfRows {
                    let raw    = centerBucket + offset
                    let bucket = ((raw % buckets) + buckets) % buckets
                    let amp    = CGFloat(waveform[bucket])

                    let barW = max(3, amp * size.width * 0.88)
                    let x    = (size.width - barW) / 2
                    let y    = cy + CGFloat(offset) * stride

                    let colorLoop = Int(Double(bucket) / Double(buckets) * 4) % 4
                    let hue       = Self.loopHues[colorLoop]
                    let isPast    = offset < 0
                    let color     = Color(hue: hue,
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
