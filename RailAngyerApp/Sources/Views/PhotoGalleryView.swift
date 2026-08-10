import SwiftUI

/// 撮った写真をまとめて見る（SC-27）。
///
/// **これまで写真は、その駅の詳細を開かないと見られなかった。**
/// 何十駅も歩いたあとで「あの写真」を探すのに、駅を1つずつ開くのは現実的ではない。
/// 撮った順に並べて、押せば大きく見られるようにする。
struct PhotoGalleryView: View {

    /// 見せる写真。駅名と時刻を添えて渡す
    struct Item: Identifiable, Hashable {
        let fileName: String
        let stationName: String
        let takenAt: Date

        var id: String { fileName }
    }

    let items: [Item]
    var title: String = "写真"
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Item?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("まだ写真がありません",
                                           systemImage: "camera",
                                           description: Text("駅に着いたら写真を撮れます"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(items) { item in
                                Button { selected = item } label: { thumbnail(item) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("\(title)　\(items.count)枚")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fullScreenCover(item: $selected) { item in
                PhotoViewerView(items: items, current: item)
            }
        }
    }

    private func thumbnail(_ item: Item) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = PhotoStore.load(item.fileName) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
            // どこで撮ったかが分からないと、探しているものにたどり着けない
            Text(item.stationName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(5)
        }
        .frame(height: 104)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 1枚を大きく見る。左右に送れる
struct PhotoViewerView: View {

    let items: [PhotoGalleryView.Item]
    @State var current: PhotoGalleryView.Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(items) { item in
                    Group {
                        if let image = PhotoStore.load(item.fileName) {
                            Image(uiImage: image)
                                .resizable().scaledToFit()
                        } else {
                            ContentUnavailableView("写真が見つかりません", systemImage: "photo")
                        }
                    }
                    .tag(item)
                }
            }
            .tabViewStyle(.page)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(current.stationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(current.takenAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }
}
