import SwiftUI
import AVFoundation

@main
struct mixApp: App {
    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .default,
            options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
        )
        try? session.setActive(true)
    }
}
