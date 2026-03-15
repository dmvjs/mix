import SwiftUI

struct SongPickerView: View {
    @Binding var selectedBPM: Int
    let onSelect: (Song) -> Void

    @State private var searchText = ""

    private let bpmOptions = [84, 94, 102]

    private var songs: [Song] {
        let list = SongLibrary.songs(bpm: selectedBPM)
        if searchText.isEmpty { return list }
        let q = searchText.lowercased()
        return list.filter {
            $0.artist.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // BPM selector
                Section {
                    BPMPicker(options: bpmOptions, selected: $selectedBPM)
                } header: {
                    Text("Tempo")
                }

                // Song list
                Section {
                    ForEach(songs) { song in
                        Button {
                            onSelect(song)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(song.artist)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(songs.count) tracks")
                }
            }
            .searchable(text: $searchText, prompt: "Artist or title")
            .navigationTitle("Select Track")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - BPM Picker

private struct BPMPicker: View {
    let options: [Int]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { bpm in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        selected = bpm
                    }
                } label: {
                    let active = selected == bpm
                    Text("\(bpm)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear))
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
