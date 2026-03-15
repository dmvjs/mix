import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var mix = MixEngine()
    #if os(iOS)
    @State private var nowPlaying: NowPlayingController? = nil
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(isPlaying: mix.isGloballyPlaying,
                       onToggle: mix.togglePlayPause)
                Color(white: 0.12).frame(height: 0.5)

                HStack(spacing: 0) {
                    DeckView(label: "A", clock: mix.clockA, deck: mix.deckA,
                             currentSong: mix.songA)
                    Color(white: 0.12).frame(width: 0.5)
                    DeckView(label: "B", clock: mix.clockB, deck: mix.deckB,
                             currentSong: mix.songB)
                }
            }

            if !mix.isGloballyPlaying && !mix.hasEverPlayed {
                PlayOverlay(onTap: mix.togglePlayPause)
            }
        }
        .onAppear {
            mix.start()
            #if os(iOS)
            nowPlaying = NowPlayingController(mix: mix)
            #endif
        }
    }
}

// MARK: - Play overlay

private struct PlayOverlay: View {
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.70).ignoresSafeArea()
            Button(action: onTap) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 82))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 24)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: true)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let isPlaying: Bool
    let onToggle:  () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Text("cuts the music")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.18))
                .tracking(2.5)

            HStack(spacing: 16) {
                Button(action: onToggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(width: 20, height: 16)
                }
                .buttonStyle(.plain)

                #if os(iOS)
                RoutePickerButton()
                    .frame(width: 20, height: 16)
                #endif
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
