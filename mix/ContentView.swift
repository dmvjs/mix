import SwiftUI

struct ContentView: View {
    // Both decks live here so they survive orientation changes
    @StateObject private var clockA = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckA  = DJAudioEngine()
    @StateObject private var clockB = MasterClock(bpm: 94, beatsPerLoop: 16)
    @StateObject private var deckB  = DJAudioEngine()

    @State private var songA: Song?
    @State private var songB: Song?

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape {
                    HStack(spacing: 0) {
                        DeckView(label: "A", clock: clockA, deck: deckA, currentSong: $songA)
                        Color(white: 0.15).frame(width: 0.5)
                        DeckView(label: "B", clock: clockB, deck: deckB, currentSong: $songB)
                    }
                } else {
                    VStack(spacing: 0) {
                        DeckView(label: "A", clock: clockA, deck: deckA, currentSong: $songA)
                        Color(white: 0.15).frame(height: 0.5)
                        DeckView(label: "B", clock: clockB, deck: deckB, currentSong: $songB)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
