import AVFoundation
import Combine

// MARK: - EQ settings (shared with UI)

struct EQSettings: Equatable {
    var high: Float = 0    // gain dB, -24 to +6
    var mid:  Float = 0
    var low:  Float = 0
    var killHigh = false
    var killMid  = false
    var killLow  = false
}

/// One deck with professional-grade scratch DSP.
///
/// Scratch model (from Mixxx/xwax research):
///   - Frame accumulator: gesture pushes delta-frames in, render drains exactly that many per
///     buffer. No timing math, no velocity noise, no drag after release.
///   - Hermite 4-point cubic interpolation: eliminates aliasing at slow/fast speeds.
///   - Asymmetric IIR on rate: instant deceleration (grab), smoothed acceleration (no crackle).
final class DJAudioEngine: ObservableObject {

    @Published var isLoaded:  Bool = false
    @Published var isPlaying: Bool = false
    @Published private(set) var waveform: [Float] = []   // downsampled peaks, main-thread safe

    // Audio data — immutable after load, safe from any thread
    private var leftSamples:  [Float] = []
    private var rightSamples: [Float] = []
    nonisolated(unsafe) private var framesTotal:   Int    = 0
    nonisolated(unsafe) private var framesPerLoop: Int    = 0

    /// Public read of total frame count for waveform display.
    var framesCount: Int { framesTotal }

    // Render-thread owned
    nonisolated(unsafe) private var renderPos:      Double = 0
    nonisolated(unsafe) private var lastRenderRate: Double = 0

    // Transport flags
    nonisolated(unsafe) private var playing:   Bool = false
    nonisolated(unsafe) private var scrubbing: Bool = false

    // Scratch accumulator: main thread adds, render thread drains.
    nonisolated(unsafe) private var scrubAccumulator: Double = 0

    // One-shot seek
    nonisolated(unsafe) private var pendingSeek: Int = -1

    // Read by main (UI only) — render writes
    nonisolated(unsafe) private(set) var currentFrame: Int = 0

    private let engine    = AVAudioEngine()
    private let eqNode    = AVAudioUnitEQ(numberOfBands: 3)
    private var eqReady   = false
    private var sourceNode: AVAudioSourceNode?

    init() {
        setupAudioSession()
        setupEQBands()
    }

    // MARK: - Load

    func load(bodyURL: URL, loopCount: Int) throws {
        let file   = try AVAudioFile(forReading: bodyURL)
        let format = file.processingFormat
        let count  = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
        try file.read(into: buf)

        framesTotal   = Int(count)
        framesPerLoop = max(1, framesTotal / loopCount)

        let data = buf.floatChannelData!
        leftSamples  = Array(UnsafeBufferPointer(start: data[0], count: framesTotal))
        rightSamples = format.channelCount > 1
            ? Array(UnsafeBufferPointer(start: data[1], count: framesTotal))
            : leftSamples

        try buildSourceNode(format: format)
        waveform = makeWaveform()
        isLoaded = true
    }

    private func makeWaveform(buckets: Int = 1400) -> [Float] {
        guard framesTotal > 0 else { return [] }
        let step = max(1, framesTotal / buckets)
        return (0..<buckets).map { i in
            let start = i * step
            let end   = min(start + step, framesTotal)
            var peak: Float = 0
            for j in start..<end { peak = max(peak, abs(leftSamples[j])) }
            return peak
        }
    }

    // MARK: - Transport

    func play()  { playing = true;  isPlaying = true  }
    func pause() { playing = false; isPlaying = false }

    // MARK: - Volume & EQ

    func setVolume(_ v: Float) {
        engine.mainMixerNode.volume = max(0, min(2, v))
    }

    func setEQ(_ s: EQSettings) {
        eqNode.bands[2].gain = s.killHigh ? -96 : max(-24, min(6, s.high))
        eqNode.bands[1].gain = s.killMid  ? -96 : max(-24, min(6, s.mid))
        eqNode.bands[0].gain = s.killLow  ? -96 : max(-24, min(6, s.low))
    }

    // MARK: - Scratch

    func startScrubbing() {
        scrubAccumulator = 0
        lastRenderRate   = 0
        scrubbing        = true
    }

    func stopScrubbing() {
        scrubAccumulator = 0
        lastRenderRate   = 0
        scrubbing        = false
    }

    func scrubByAngleDelta(_ delta: Double) {
        guard framesPerLoop > 0 else { return }
        scrubAccumulator += (delta / (2 * .pi)) * Double(framesPerLoop)
    }

    func syncPosition(to fraction: Double) {
        guard framesPerLoop > 0 else { return }
        pendingSeek = Int(fraction * Double(framesPerLoop))
    }

    func seekToQuarter(_ quarter: Int) {
        guard framesPerLoop > 0 else { return }
        pendingSeek = quarter * framesPerLoop
    }

    func seekToAbsoluteFraction(_ fraction: Double) {
        guard framesTotal > 0 else { return }
        pendingSeek = Int(fraction * Double(framesTotal))
    }

    var loopFraction: Double {
        guard framesPerLoop > 0 else { return 0 }
        return Double(currentFrame % framesPerLoop) / Double(framesPerLoop)
    }

    // MARK: - Private

    private func setupAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func setupEQBands() {
        // Low shelf 200 Hz
        eqNode.bands[0].filterType = .lowShelf
        eqNode.bands[0].frequency  = 200
        eqNode.bands[0].gain       = 0
        eqNode.bands[0].bypass     = false
        // Mid parametric 1 kHz, Q = 1
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency  = 1000
        eqNode.bands[1].bandwidth  = 1.0
        eqNode.bands[1].gain       = 0
        eqNode.bands[1].bypass     = false
        // High shelf 8 kHz
        eqNode.bands[2].filterType = .highShelf
        eqNode.bands[2].frequency  = 8000
        eqNode.bands[2].gain       = 0
        eqNode.bands[2].bypass     = false
    }

    private func buildSourceNode(format: AVAudioFormat) throws {
        engine.stop()
        if let old = sourceNode { engine.detach(old) }

        let node = AVAudioSourceNode(format: format) { [weak self] isSilence, _, frameCount, outputData in
            guard let self, self.framesTotal > 0 else {
                isSilence.pointee = true
                return noErr
            }

            let abl      = UnsafeMutableAudioBufferListPointer(outputData)
            let fc       = Int(frameCount)
            let left     = abl[0].mData!.bindMemory(to: Float.self, capacity: fc)
            let right    = abl.count > 1 ? abl[1].mData!.bindMemory(to: Float.self, capacity: fc) : nil
            let total    = Double(self.framesTotal)
            let totalInt = self.framesTotal

            let seek = self.pendingSeek
            if seek >= 0 {
                self.renderPos   = Double(seek)
                self.pendingSeek = -1
            }

            let rawRate: Double
            if self.scrubbing {
                let acc = self.scrubAccumulator
                self.scrubAccumulator -= acc
                rawRate = acc / Double(fc)
            } else if self.playing {
                rawRate = 1.0
            } else {
                isSilence.pointee = true
                return noErr
            }

            let prev = self.lastRenderRate
            let rate: Double
            if abs(rawRate) < abs(prev) {
                rate = rawRate
            } else {
                rate = prev * 0.35 + rawRate * 0.65
            }
            let finalRate = abs(rate) < 1e-4 ? 0.0 : rate
            self.lastRenderRate = finalRate

            var pos = self.renderPos

            self.leftSamples.withUnsafeBufferPointer  { lp in
            self.rightSamples.withUnsafeBufferPointer { rp in
                for i in 0..<fc {
                    var p = pos.truncatingRemainder(dividingBy: total)
                    if p < 0 { p += total }

                    let i0  = Int(p)
                    let im1 = i0 > 0          ? i0 - 1 : totalInt - 1
                    let i1  = i0 < totalInt-1 ? i0 + 1 : 0
                    let i2  = i1 < totalInt-1 ? i1 + 1 : 0
                    let mu  = Float(p - Double(i0))

                    left[i]   = hermite(mu, lp[im1], lp[i0], lp[i1], lp[i2])
                    right?[i] = hermite(mu, rp[im1], rp[i0], rp[i1], rp[i2])

                    pos += finalRate
                }
            }}

            var finalPos = pos.truncatingRemainder(dividingBy: total)
            if finalPos < 0 { finalPos += total }
            self.renderPos    = finalPos
            self.currentFrame = Int(finalPos)

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        if !eqReady {
            engine.attach(eqNode)
            eqReady = true
        }
        engine.connect(node,   to: eqNode,               format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        try engine.start()
    }
}

// MARK: - Hermite 4-point cubic interpolation
@inline(__always)
private func hermite(_ mu: Float, _ xm1: Float, _ x0: Float, _ x1: Float, _ x2: Float) -> Float {
    let c    = (x1 - xm1) * 0.5
    let v    = x0 - x1
    let w    = c + v
    let a    = w + v + (x2 - x0) * 0.5
    let bNeg = w + a
    return ((((a * mu) - bNeg) * mu + c) * mu + x0)
}
