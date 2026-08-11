import SwiftUI

/// 撮った写真をまとめて見る（SC-27）。
///
/// **これまで写真は、その駅の詳細を開かないと見られなかった。**
/// 何十駅も歩いたあとで「あの写真」を探すのに、駅を1つずつ開くのは現実的ではない。
/// 撮った順に並べて、押せば大きく見られるようにする。
struct PhotoGalleryView: View {

    /// 見せる写真。駅名と時刻を添えて渡す
    struct Item: Identifiable, Hashable {
        /// いまの旅の写真は `Photo.id`。畳んだ旅の写真は行が残っていないので nil
        var photoId: UUID?
        /// 端末にある実体。**仲間の写真は落ちてくるまで空**。
        /// 空を「実体なし」とみなすのは `PhotoStore.load` / `exists` と同じ約束
        let fileName: String
        let stationName: String
        let takenAt: Date
        /// 撮った人。**自分の写真では nil**（自分の名前をいちいち出しても情報が増えない）
        var photographer: String?
        /// 自分が撮ったか。畳んだ旅の写真は撮った人が残っていないので自分扱い
        var isMine: Bool = true

        /// 実体が届く前後で入れ替わらない値にする。
        /// ファイル名だけを id にすると、落ちてきた瞬間に別の写真として扱われる
        var id: String {
            if let photoId { return photoId.uuidString }
            return fileName.isEmpty ? "\(stationName)-\(takenAt.timeIntervalSince1970)" : fileName
        }

        /// 一覧には出ているが、実体がまだ落ちてきていない
        var isPending: Bool { fileName.isEmpty }

        /// 消せるのは、自分が撮った・いまの旅の写真だけ
        var isDeletable: Bool { isMine && photoId != nil }

        /// サムネイルに添える短い説明。仲間の写真なら誰が撮ったのかまで出す
        var caption: String {
            guard let photographer else { return stationName }
            return "\(stationName)・\(photographer)"
        }

        init(photoId: UUID? = nil, fileName: String, stationName: String, takenAt: Date,
             photographer: String? = nil, isMine: Bool = true) {
            self.photoId = photoId
            self.fileName = fileName
            self.stationName = stationName
            self.takenAt = takenAt
            self.photographer = photographer
            self.isMine = isMine
        }

        /// 実体がまだ無い写真も受ける口（`GameSessionStore.photoItems` / `galleryPhotos` 用）。
        /// **nil は「まだ落ちてきていない」**の意味で、空文字として持つ
        init(photoId: UUID? = nil, fileName: String?, stationName: String, takenAt: Date,
             photographer: String? = nil, isMine: Bool = true) {
            self.init(photoId: photoId, fileName: fileName ?? "", stationName: stationName,
                      takenAt: takenAt, photographer: photographer, isMine: isMine)
        }
    }

    let items: [Item]
    var title: String = "写真"
    /// 開いたときと、引っ張ったときに走らせる取り込み
    var onRefresh: (() async -> Void)?
    /// 自分の写真を消す。渡されなければ削除の導線を出さない
    var onDelete: ((Item) -> Void)?
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
                    // 仲間が撮った直後に見に来ることがある。引っ張れば取りに行く
                    .refreshable { await onRefresh?() }
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
                PhotoViewerView(items: items, current: item, onDelete: onDelete)
            }
            // 開いた時点でいちど取りに行く。**待たせない**（届いたぶんから増えていく）
            .task { await onRefresh?() }
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
        // いまの旅のぶんは store から。仲間が撮ったものもここに混ざっている
        let current = store.galleryPhotos.map { photo in
            Item(photoId: photo.photoId,
                 fileName: photo.localFileName ?? "",
                 stationName: photo.stationName ?? "-",
                 takenAt: photo.takenAt,
                 photographer: photo.isMine ? nil : photo.authorName,
                 isMine: photo.isMine)
        }
        var seen = Set(current.map(\.fileName))
        var archived: [Item] = []

        for archive in store.archives {
            let label = archive.roomName.isEmpty ? archive.courseName : archive.roomName
            let journeyName = label.isEmpty ? "過去の旅" : label
            for photo in archive.photos
            where !seen.contains(photo.fileName) && PhotoStore.exists(photo.fileName) {
                seen.insert(photo.fileName)
                // 畳んだ旅は撮った人を残していない。消す口も無いので photoId は付けない
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
                // 一覧（軽い）と実体（重い）は別に降りてくる。
                // **「あるはずなのに出ない」に見せない** ため、受け取り中だと分かる枠を置く
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: item.isPending ? "arrow.down.circle" : "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            // どこで撮ったかが分からないと、探しているものにたどり着けない。
            // 仲間の写真は誰が撮ったのかも添える（自分のぶんには出さない）
            Text(item.caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
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
    /// 最初に開く1枚
    let current: PhotoGalleryView.Item
    /// 自分の写真を消す。渡されなければ削除の導線を出さない
    var onDelete: ((PhotoGalleryView.Item) -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// めくっている写真。**実体そのものではなく id で持つ。**
    /// 写真は1枚ずつ落ちてくるので、めくっている最中に中身（ファイル名）が変わる。
    /// 値のまま持つと、落ちてきた瞬間に選択が迷子になって真っ黒な頁が出る
    @State private var currentId = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            TabView(selection: $currentId) {
                ForEach(items) { item in
                    page(item).tag(item.id)
                }
            }
            .tabViewStyle(.page)
            .background(Color.black.ignoresSafeArea())
            .onAppear { if currentId.isEmpty { currentId = current.id } }
            .navigationTitle(shown?.stationName ?? "写真")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **端末の写真アプリへ持ち出せるようにする。**
                // アプリの中だけに置いておくと、消したときに一緒に消えてしまう。
                // 共有シートなら「画像を保存」も送信も同じ口で済み、追加の許可も要らない
                ToolbarItem(placement: .topBarLeading) {
                    if let fileName = shown?.fileName, PhotoStore.exists(fileName) {
                        ShareLink(item: PhotoStore.url(of: fileName)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("写真を保存・共有")
                        .accessibilityIdentifier("sharePhoto")
                    }
                }
                // **消せるのは自分が撮った写真だけ。**
                // 仲間の写真は端末に降りてきていても、その人のもの
                ToolbarItem(placement: .topBarLeading) {
                    if canDelete {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("この写真を消す")
                        .accessibilityIdentifier("deletePhoto")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    if let photographer = shown?.photographer {
                        Label("\(photographer) が撮影", systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let shown {
                        Text(shown.takenAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
            }
            .confirmationDialog("この写真を消しますか",
                                isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("消す", role: .destructive) { delete() }
            } message: {
                Text("端末からも仲間の画面からも消えます。元には戻せません。")
            }
        }
    }

    /// いま見ている1枚。落ちてきた写真で並びが変わっても迷子にならないよう、
    /// 見つからなければ開いたときの1枚、それも無ければ先頭に寄せる
    private var shown: PhotoGalleryView.Item? {
        items.first { $0.id == currentId } ?? items.first { $0.id == current.id } ?? items.first
    }

    private var canDelete: Bool { onDelete != nil && (shown?.isDeletable ?? false) }

    @ViewBuilder
    private func page(_ item: PhotoGalleryView.Item) -> some View {
        if let image = PhotoStore.load(item.fileName) {
            Image(uiImage: image)
                .resizable().scaledToFit()
        } else if item.isPending {
            // 一覧だけ先に届いている状態。**「無い」ではなく「これから届く」**と伝える
            ContentUnavailableView("受け取り中です", systemImage: "arrow.down.circle",
                                   description: Text("画面を下に引っ張ると取りに行きます"))
        } else {
            ContentUnavailableView("写真が見つかりません", systemImage: "photo")
        }
    }

    /// 消したら閉じる。**開いたままにしない** —
    /// 見ている写真が消えると、めくっている最中の並びと食い違う
    private func delete() {
        guard let shown else { return }
        onDelete?(shown)
        dismiss()
    }
}
