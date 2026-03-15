#if os(iOS)
import Foundation
import MediaPlayer
import UIKit
import Combine

/// Keeps the Now Playing info centre up to date, registers remote-control
/// commands (lock screen, Control Centre, headphones, CarPlay, AirPlay),
/// and holds the screen wake lock while audio is playing.
final class NowPlayingController {

    private let mix: MixEngine
    private var cancellables = Set<AnyCancellable>()

    /// App icon loaded once and reused for every Now Playing update
    private static let artwork: MPMediaItemArtwork? = {
        guard let image = UIImage(named: "AppIcon") ?? bundleIcon() else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { size in
            UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }()

    init(mix: MixEngine) {
        self.mix = mix
        setupRemoteCommands()
        observeMixEngine()
    }

    // MARK: - Remote commands (lock screen, headphones, CarPlay)

    private func setupRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()

        rc.playCommand.addTarget { [weak self] _ in
            guard let self, !mix.isGloballyPlaying else { return .commandFailed }
            mix.togglePlayPause(); return .success
        }
        rc.pauseCommand.addTarget { [weak self] _ in
            guard let self, mix.isGloballyPlaying else { return .commandFailed }
            mix.togglePlayPause(); return .success
        }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.mix.togglePlayPause(); return .success
        }

        rc.nextTrackCommand.isEnabled          = false
        rc.previousTrackCommand.isEnabled      = false
        rc.seekForwardCommand.isEnabled        = false
        rc.seekBackwardCommand.isEnabled       = false
        rc.changePlaybackRateCommand.isEnabled = false
    }

    // MARK: - Observe mix engine

    private func observeMixEngine() {
        mix.$songA
            .combineLatest(mix.$songB, mix.$isGloballyPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sA, sB, playing in
                self?.updateNowPlaying(songA: sA, songB: sB, isPlaying: playing)
                UIApplication.shared.isIdleTimerDisabled = playing
            }
            .store(in: &cancellables)
    }

    // MARK: - Now Playing metadata

    private func updateNowPlaying(songA: Song?, songB: Song?, isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyAlbumTitle:         "cuts the music",
            MPNowPlayingInfoPropertyMediaType:     MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream:  true,
            MPNowPlayingInfoPropertyPlaybackRate:  isPlaying ? 1.0 : 0.0,
        ]

        if let art = Self.artwork {
            info[MPMediaItemPropertyArtwork] = art
        }

        // Long combined strings trigger the system's own marquee on lock screen / CarPlay
        if let a = songA, let b = songB {
            info[MPMediaItemPropertyTitle]  = "\(a.title)  ·  \(b.title)"
            info[MPMediaItemPropertyArtist] = "\(a.artist)  /  \(b.artist)"
        } else if let a = songA {
            info[MPMediaItemPropertyTitle]  = a.title
            info[MPMediaItemPropertyArtist] = a.artist
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState  = isPlaying ? .playing : .paused
    }

    // MARK: - Helpers

    private static func bundleIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }
}

// MARK: - AirPlay / output route picker (UIViewRepresentable wrapper)

import SwiftUI
import AVKit

struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.35)
        v.activeTintColor = UIColor.white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
