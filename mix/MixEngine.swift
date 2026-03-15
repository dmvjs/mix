import Foundation
import Combine

private enum MixPhase { case idle, lead, body }

/// Owns both decks + clocks and drives the lead→body→next-block state machine.
///
/// Staging model: each phase pre-decodes the *next* phase in background Tasks.
/// Tasks are individually cancelled before new ones start, so a slow decode from
/// a previous phase can never land wrong-tempo audio on a deck.
final class MixEngine: ObservableObject {

    @Published private(set) var songA: Song?
    @Published private(set) var songB: Song?
    @Published private(set) var isGloballyPlaying = false
    @Published private(set) var hasEverPlayed     = false

    let clockA = MasterClock(bpm: 84, beatsPerLoop: 16)
    let deckA  = DJAudioEngine()
    let clockB = MasterClock(bpm: 84, beatsPerLoop: 16)
    let deckB  = DJAudioEngine()

    private var phase: MixPhase = .idle
    private var scheduler = MixScheduler()
    private var cancellables = Set<AnyCancellable>()
    private var pendingBlock: MixBlock? = nil

    // Staging tasks — cancelled whenever new staging starts so stale
    // background decodes cannot overwrite in-progress staging.
    private var stagingTaskA: Task<Void, Never>? = nil
    private var stagingTaskB: Task<Void, Never>? = nil

    private let beatsForLead: Double = 16   // 1 loop
    private let beatsForBody: Double = 64   // 4 loops

    /// Called on appear — subscribes to beats and pre-loads the first block,
    /// but does NOT start playback until the user taps play.
    func start() {
        clockA.$absoluteBeat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] beat in self?.onBeat(beat) }
            .store(in: &cancellables)
        startBlock()
    }

    func togglePlayPause() {
        if isGloballyPlaying { pause() } else { resume() }
    }

    private func pause() {
        isGloballyPlaying = false
        deckA.pause(); deckB.pause()
        clockA.stop(); clockB.stop()
    }

    private func resume() {
        isGloballyPlaying = true
        hasEverPlayed     = true
        clockA.start(); clockB.start()
        deckA.play(); deckB.play()
    }

    // MARK: - Beat handler

    private func onBeat(_ beat: Double) {
        switch phase {
        case .lead where beat >= beatsForLead:
            phase = .idle
            startBodyPhase()
        case .body where beat >= beatsForBody:
            phase = .idle
            startBlock()
        default:
            break
        }
    }

    // MARK: - Phase transitions

    private func startBlock() {
        let block: MixBlock
        if let pending = pendingBlock {
            block = pending
            pendingBlock = nil
        } else {
            guard let b = scheduler.nextBlock() else { return }
            block = b
        }
        songA = block.songA
        songB = block.songB
        commitAndPlay(sA: block.songA, sB: block.songB, isLead: true)
    }

    private func startBodyPhase() {
        guard let sA = songA, let sB = songB else { return }
        commitAndPlay(sA: sA, sB: sB, isLead: false)
    }

    // MARK: - Core playback

    private func commitAndPlay(sA: Song, sB: Song, isLead: Bool) {
        deckA.pause(); deckB.pause()
        clockA.stop(); clockB.stop()

        let resA   = isLead ? sA.leadResource : sA.bodyResource
        let resB   = isLead ? sB.leadResource : sB.bodyResource
        let loops  = isLead ? 1 : 4
        let target: MixPhase = isLead ? .lead : .body
        let bpm    = Double(sA.bpm)   // both songs guaranteed same BPM

        let dA = deckA, dB = deckB, cA = clockA, cB = clockB

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            if dA.hasStaged && dB.hasStaged {
                try? dA.commitStaged()
                try? dB.commitStaged()
            } else {
                let urlA = Bundle.main.url(forResource: resA, withExtension: "mp3")
                        ?? Bundle.main.url(forResource: sA.bodyResource, withExtension: "mp3")
                let urlB = Bundle.main.url(forResource: resB, withExtension: "mp3")
                        ?? Bundle.main.url(forResource: sB.bodyResource, withExtension: "mp3")
                if let u = urlA { try? dA.load(bodyURL: u, loopCount: loops) }
                if let u = urlB { try? dB.load(bodyURL: u, loopCount: loops) }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                cA.bpm = bpm;  cB.bpm = bpm      // sync clock speed to actual song tempo
                cA.setBeatPosition(0); cB.setBeatPosition(0)
                phase = target
                guard isGloballyPlaying else { return }
                cA.start(); cB.start()
                dA.play(); dB.play()
            }

            self.stageNextPhase(currentSA: sA, currentSB: sB, justStartedLead: isLead)
        }
    }

    // MARK: - Staging

    private func stageNextPhase(currentSA: Song, currentSB: Song, justStartedLead: Bool) {
        if justStartedLead {
            // Lead just started → pre-stage the bodies (same songs, 4 loops)
            Task { @MainActor [weak self] in
                self?.startStaging(
                    primaryA: currentSA.bodyResource, fallbackA: nil,
                    primaryB: currentSB.bodyResource, fallbackB: nil,
                    loopCount: 4
                )
            }
        } else {
            // Body just started → pick next block on main actor (serialised with startBlock),
            // then pre-stage its leads.
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let b = scheduler.nextBlock() else { return }
                pendingBlock = b
                startStaging(
                    primaryA: b.songA.leadResource, fallbackA: b.songA.bodyResource,
                    primaryB: b.songB.leadResource, fallbackB: b.songB.bodyResource,
                    loopCount: 1
                )
            }
        }
    }

    /// Cancel any in-flight staging and launch fresh background tasks.
    /// Called on the main actor so stagingTaskA/B are safely accessed.
    @MainActor
    private func startStaging(primaryA: String, fallbackA: String?,
                               primaryB: String, fallbackB: String?,
                               loopCount: Int) {
        stagingTaskA?.cancel()
        stagingTaskB?.cancel()
        // Wipe any stale staging that completed before the cancel reached it
        deckA.clearStaging()
        deckB.clearStaging()
        let dA = deckA, dB = deckB

        stagingTaskA = Task.detached(priority: .userInitiated) {
            let u = Bundle.main.url(forResource: primaryA, withExtension: "mp3")
                 ?? fallbackA.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp3") }
            if let u { try? dA.stage(url: u, loopCount: loopCount) }
        }
        stagingTaskB = Task.detached(priority: .userInitiated) {
            let u = Bundle.main.url(forResource: primaryB, withExtension: "mp3")
                 ?? fallbackB.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp3") }
            if let u { try? dB.stage(url: u, loopCount: loopCount) }
        }
    }
}
