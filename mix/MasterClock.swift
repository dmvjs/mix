import Foundation
import Combine
import QuartzCore

/// The single source of truth for playback position.
/// Position is expressed as a fraction 0.0..<1.0 within one loop.
/// The clock advances at `bpm` beats per minute, where one loop = `beatsPerLoop` beats.
final class MasterClock: ObservableObject {
    var bpm: Double
    let beatsPerLoop: Double   // 16 beats per loop (lead = 1 loop, body = 4 loops)

    @Published private(set) var loopFraction: Double = 0  // 0.0 ..< 1.0
    @Published private(set) var loopIndex: Int = 0        // which loop (0-3 for body, 0 for lead)
    @Published private(set) var absoluteBeat: Double = 0  // raw unbounded beat, for sync lock

    // Raw position in beats (unbounded, wraps for display)
    nonisolated(unsafe) private(set) var beatPosition: Double = 0

    nonisolated(unsafe) var isPlaying: Bool = false
    nonisolated(unsafe) var isScrubbing: Bool = false

    private var displayTimer: Timer?
    private var lastTickTime: CFTimeInterval = 0

    init(bpm: Double = 94, beatsPerLoop: Double = 16) {
        self.bpm = bpm
        self.beatsPerLoop = beatsPerLoop
    }

    func start() {
        isPlaying = true
        lastTickTime = CACurrentMediaTime()
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        isPlaying = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTickTime
        lastTickTime = now

        if isPlaying && !isScrubbing {
            let beatsPerSecond = bpm / 60.0
            beatPosition += dt * beatsPerSecond
        }

        let beat  = beatPosition
        let totalLoops = beat / beatsPerLoop
        let frac  = totalLoops.truncatingRemainder(dividingBy: 1.0)
        let index = Int(totalLoops) % 4
        DispatchQueue.main.async { [weak self] in
            self?.loopFraction = frac < 0 ? frac + 1 : frac
            self?.loopIndex    = index < 0 ? index + 4 : index
            self?.absoluteBeat = beat
        }
    }

    /// Scrub by a rotational delta (radians). One full rotation = one loop.
    func scrub(angleDelta: Double) {
        let loopDelta = angleDelta / (2 * .pi)
        beatPosition += loopDelta * beatsPerLoop
    }

    var angle: Double { loopFraction * 2 * .pi }

    /// Jump to a quarter position (0–3) in the 4-loop body.
    func jumpToQuarter(_ quarter: Int) {
        beatPosition = Double(quarter) * beatsPerLoop
    }

    /// Set beat position directly (used for sync).
    func setBeatPosition(_ pos: Double) {
        beatPosition = pos
    }

    /// Snap this clock to the same absolute position as another clock.
    func syncTo(_ other: MasterClock) {
        beatPosition = other.beatPosition
    }
}
