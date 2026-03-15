import Foundation
import Combine
import QuartzCore

/// The single source of truth for playback position.
/// Position is expressed as a fraction 0.0..<1.0 within one loop.
/// The clock advances at `bpm` beats per minute, where one loop = `beatsPerLoop` beats.
final class MasterClock: ObservableObject {
    let bpm: Double
    let beatsPerLoop: Double   // 16 beats per loop (lead = 1 loop, body = 4 loops)

    @Published private(set) var loopFraction: Double = 0  // 0.0 ..< 1.0
    @Published private(set) var loopIndex: Int = 0        // which loop (0-3 for body, 0 for lead)

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
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTickTime
        lastTickTime = now

        if isPlaying && !isScrubbing {
            let beatsPerSecond = bpm / 60.0
            beatPosition += dt * beatsPerSecond
        }

        let totalLoops = beatPosition / beatsPerLoop
        let frac  = totalLoops.truncatingRemainder(dividingBy: 1.0)
        let index = Int(totalLoops) % 4
        DispatchQueue.main.async { [weak self] in
            self?.loopFraction = frac < 0 ? frac + 1 : frac
            self?.loopIndex    = index < 0 ? index + 4 : index
        }
    }

    /// Scrub by a rotational delta (radians). One full rotation = one loop.
    func scrub(angleDelta: Double) {
        let loopDelta = angleDelta / (2 * .pi)
        beatPosition += loopDelta * beatsPerLoop
    }

    var angle: Double { loopFraction * 2 * .pi }
}
