import AVFoundation
import Combine

// MARK: - EQ settings (shared with UI)

struct EQSettings: Equatable {
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
///   - Per-sample gain envelope: ramps to 0 before pause/seek → zero clicks.
final class DJAudioEngine: ObservableObject {

    @Published var isLoaded:  Bool = false
    @Published var isPlaying: Bool = false
    @Published private(set) var waveform: [Float] = []

    // Audio data — immutable after load, safe from any thread
    private var leftSamples:  [Float] = []
    private var rightSamples: [Float] = []
    nonisolated(unsafe) private var framesTotal:   Int = 0
    nonisolated(unsafe) private var framesPerLoop: Int = 0

    var framesCount: Int { framesTotal }

    // Render-thread state
    nonisolated(unsafe) private var renderPos:      Double = 0
    nonisolated(unsafe) private var lastRenderRate: Double = 0

    // Transport intent (set from main thread, read on render thread)
    nonisolated(unsafe) private var playing:   Bool = false
    nonisolated(unsafe) private var scrubbing: Bool = false

    // Scratch accumulator
    nonisolated(unsafe) private var scrubAccumulator: Double = 0

    // Gain envelope — ramps per-sample so there are no click discontinuities.
    // Render drives renderGain toward gainTarget at gainStep per sample.
    // Seeks are deferred until renderGain < silence threshold.
    nonisolated(unsafe) private var renderGain: Float = 0.0
    nonisolated(unsafe) private var gainTarget: Float = 0.0
    // ~5 ms fade at 44100 Hz (1/220 per sample → 220 samples to full ramp)
    private static let gainStep: Float = 1.0 / 220.0

    // Pending seek — applied only when renderGain is near zero to avoid position-jump clicks
    nonisolated(unsafe) private var pendingSeek: Int = -1

    nonisolated(unsafe) private(set) var currentFrame: Int = 0

    private let engine  = AVAudioEngine()
    private let eqNode  = AVAudioUnitEQ(numberOfBands: 3)
    private var eqReady = false
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
        let wf = makeWaveform()
        DispatchQueue.main.async { [weak self] in
            self?.waveform = wf
            self?.isLoaded = true
        }
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

    func play() {
        playing    = true
        gainTarget = 1.0   // render will ramp up smoothly
        isPlaying  = true
    }

    func pause() {
        playing    = false
        gainTarget = 0.0   // render ramps to silence, then stays silent
        isPlaying  = false
    }

    // MARK: - Volume & EQ

    func setVolume(_ v: Float) {
        engine.mainMixerNode.volume = max(0, min(2, v))
    }

    func setEQ(_ s: EQSettings) {
        eqNode.bands[2].gain = s.killHigh ? -96 : 0
        eqNode.bands[1].gain = s.killMid  ? -96 : 0
        eqNode.bands[0].gain = s.killLow  ? -96 : 0
    }

    // MARK: - Scratch

    func startScrubbing() {
        scrubAccumulator = 0
        lastRenderRate   = 0
        scrubbing        = true
        gainTarget       = 1.0
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
        eqNode.bands[0].filterType = .lowShelf;   eqNode.bands[0].frequency = 200;  eqNode.bands[0].gain = 0; eqNode.bands[0].bypass = false
        eqNode.bands[1].filterType = .parametric; eqNode.bands[1].frequency = 1000; eqNode.bands[1].gain = 0; eqNode.bands[1].bandwidth = 1.0; eqNode.bands[1].bypass = false
        eqNode.bands[2].filterType = .highShelf;  eqNode.bands[2].frequency = 8000; eqNode.bands[2].gain = 0; eqNode.bands[2].bypass = false
    }

    private func buildSourceNode(format: AVAudioFormat) throws {
        if let old = sourceNode { engine.detach(old) }   // live swap — no engine.stop()

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
            let step     = Self.gainStep

            // ── Gain target this buffer ───────────────────────────────────
            // A pending seek must wait until the gain has ramped to zero so the
            // position jump is inaudible.  Once silent, apply seek then let gain
            // ramp back to whatever playing/scrubbing dictates.
            let seekPending = self.pendingSeek >= 0
            let gainTarget: Float
            if self.scrubbing {
                gainTarget = 1.0
            } else if seekPending {
                if self.renderGain < 0.005 {
                    // Gain is silent — safe to jump position now
                    self.renderPos   = Double(self.pendingSeek)
                    self.pendingSeek = -1
                    gainTarget = self.playing ? 1.0 : 0.0
                } else {
                    gainTarget = 0.0   // drive to silence first
                }
            } else {
                gainTarget = self.playing ? 1.0 : 0.0
            }

            // Decide if we need to render anything at all
            let needsRender = self.scrubbing || self.renderGain > 0.0 || gainTarget > 0.0
            guard needsRender else {
                isSilence.pointee = true
                return noErr
            }

            // ── Playback rate ─────────────────────────────────────────────
            let rawRate: Double
            if self.scrubbing {
                let acc = self.scrubAccumulator
                self.scrubAccumulator -= acc
                rawRate = acc / Double(fc)
            } else {
                rawRate = self.playing ? 1.0 : 0.0
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

            // ── Fill output with Hermite interpolation + gain envelope ────
            var pos  = self.renderPos
            var gain = self.renderGain

            self.leftSamples.withUnsafeBufferPointer  { lp in
            self.rightSamples.withUnsafeBufferPointer { rp in
                for i in 0..<fc {
                    // Ramp gain toward target each sample
                    if gain < gainTarget        { gain = min(gainTarget, gain + step) }
                    else if gain > gainTarget   { gain = max(gainTarget, gain - step) }

                    var p = pos.truncatingRemainder(dividingBy: total)
                    if p < 0 { p += total }

                    let i0  = Int(p)
                    let im1 = i0 > 0          ? i0 - 1 : totalInt - 1
                    let i1  = i0 < totalInt-1 ? i0 + 1 : 0
                    let i2  = i1 < totalInt-1 ? i1 + 1 : 0
                    let mu  = Float(p - Double(i0))

                    left[i]   = hermite(mu, lp[im1], lp[i0], lp[i1], lp[i2]) * gain
                    right?[i] = hermite(mu, rp[im1], rp[i0], rp[i1], rp[i2]) * gain

                    pos += finalRate
                }
            }}

            self.renderGain   = gain
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
        if !engine.isRunning { try engine.start() }
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
