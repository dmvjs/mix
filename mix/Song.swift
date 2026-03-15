import Foundation

struct Song: Identifiable, Hashable {
    let id: Int
    let artist: String
    let title: String
    let key: Int
    let bpm: Int

    var bodyResource: String { String(format: "%08d-body", id) }
    var leadResource: String { String(format: "%08d-lead", id) }
}
