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

    /// 端末に残っている写真をぜんぶ、撮った順に。
    ///
    /// **いまの旅のぶんだけでは足りない。** 旅を保存すると訪問の行は消え、
    /// 残るのは写真のファイルと `JourneyArchive.photoFileNames` だけになる。
    /// いまの旅しか見ないギャラリーは、旅を保存した瞬間に空になってしまう
    /// （ホームの「写真をまとめて見る」が何も出なかったのはこれ）。
    ///
    /// 保存した旅の写真は `JourneyArchive.photos` から駅名を引く。
    /// 駅名を残していない古い記録では、代わりに旅の名前を添える
    @MainActor
    static func allItems(in store: GameSessionStore) -> [Item] {
        let current = store.photoItems
        var seen = Set(current.map(\.fileName))
        var archived: [Item] = []

        for archive in store.archives {
            let label = archive.roomName.isEmpty ? archive.courseName : archive.roomName
            let journeyName = label.isEmpty ? "過去の旅" : label
            for photo in archive.photos
            where !seen.contains(photo.fileName) && PhotoStore.exists(photo.fileName) {
                seen.insert(photo.fileName)
                archived.append(Item(fileName: photo.fileName,
                                     stationName: photo.stationName ?? journeyName,
                                     takenAt: archive.endedAt))
            }
        }
        return (current + archived).sorted { $0.takenAt < $1.takenAt }
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
                // **端末の写真アプリへ持ち出せるようにする。**
                // アプリの中だけに置いておくと、消したときに一緒に消えてしまう。
                // 共有シートなら「画像を保存」も送信も同じ口で済み、追加の許可も要らない
                ToolbarItem(placement: .topBarLeading) {
                    if PhotoStore.exists(current.fileName) {
                        ShareLink(item: PhotoStore.url(of: current.fileName)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("写真を保存・共有")
                        .accessibilityIdentifier("sharePhoto")
                    }
                }
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
