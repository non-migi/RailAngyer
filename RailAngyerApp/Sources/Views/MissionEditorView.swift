import SwiftUI
import RailAngyerCore

/// ミッションの自作（SC-12）。
///
/// **駅ごとに、1メンバー1個まで**（企画仕様 / UQ-05）。
/// お題は**既定でみんなに見える**。当日まで伏せたい予定だけ、件数だけの表示に切り替わる。
struct MissionEditorView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    /// 予定から開いたときの対象。**まだ始めていない旅のお題も書ける**ようにするためのもの。
    /// 省略すると、いま遊んでいるコース全体を対象にする
    var plan: MissionPlan?
    /// お題の中身をみんなに見せるか。**既定は見せる。**
    /// 予定から開いたときは、その予定の設定（`MissionPlan.sharesMissions`）が優先される
    var sharesMissions = true
    /// 予定一覧から押し進んで開くとき。呼び出し側の `NavigationStack` にそのまま載せる。
    /// 自前で包むと戻る手段が二重になり、予定へ戻るのに2回たたむことになる
    var isPushed = false
    @Environment(\.dismiss) private var dismiss

    @State private var editing: MissionDraft?
    @State private var summary: [MissionSummaryResponse] = []
    @State private var isLoading = false

    private var course: Course? { plan?.course ?? store.room?.course }

    /// いま開いている対象で、お題の中身を見せてよいか
    private var missionsAreShared: Bool { plan?.sharesMissions ?? sharesMissions }

    /// 対象の駅。予定から開いたときは、その予定の区間だけに絞る
    private var stations: [Station] {
        let all = (course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
        guard let plan else { return all }
        let range = min(plan.startOrder, plan.goalOrder)...max(plan.startOrder, plan.goalOrder)
        return all.filter { range.contains($0.orderNo) }
    }

    private var missions: [Mission] {
        let orders = Set(stations.map(\.orderNo))
        return store.myMissions(in: course).filter { orders.contains($0.station?.orderNo ?? -1) }
    }

    var body: some View {
        if isPushed {
            list
        } else {
            NavigationStack { list }
        }
    }

    private var list: some View {
        List {
            mineSection
            if sync.isJoined { preparationSection }
        }
        .navigationTitle(plan.map { "\($0.title) のお題" } ?? "お題を書く")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let free = firstFreeStation else { return }
                    editing = MissionDraft(existing: nil, stationOrder: free)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(firstFreeStation == nil)   // 全駅に書き終えたら追加できない
            }
        }
        .sheet(item: $editing) { draft in
            MissionDraftView(store: store, draft: draft,
                             course: course, stations: stations)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: - 自分のお題

    @ViewBuilder
    private var mineSection: some View {
        Section {
            if missions.isEmpty {
                Text("まだ書いていません。右上の＋から追加してください。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(missions) { mission in
                Button {
                    editing = MissionDraft(existing: mission,
                                           stationOrder: mission.station?.orderNo ?? 1)
                } label: {
                    row(mission)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for mission in offsets.map({ missions[$0] }) {
                    store.deleteMission(mission)
                }
            }
        } header: {
            Text("あなたのお題　\(missions.count) / \(stations.count) 駅")
        } footer: {
            Text("1つの駅に書けるお題は1人1個までです。着地した駅で、誰かのお題が1つ引かれます。")
        }
    }

    private func row(_ mission: Mission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mission.station?.name ?? "-")
                    .font(.subheadline.bold())
                Spacer()
            }
            Text(mission.content)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    /// まだ自分のお題が無い駅のうち、いちばん手前
    private var firstFreeStation: Int? {
        stations.first { store.myMission(at: $0.orderNo, in: course) == nil }?.orderNo
    }

    // MARK: - みんなの準備状況

    @ViewBuilder
    private var preparationSection: some View {
        Section {
            if isLoading && summary.isEmpty {
                ProgressView()
            } else if summary.isEmpty {
                Text("まだ誰もお題を書いていません。").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(stations) { station in
                if let row = summary.first(where: { $0.stationId == station.serverId }) {
                    preparationRow(station, row)
                }
            }
        } header: {
            Text("みんなの準備状況")
        } footer: {
            Text(missionsAreShared
                 ? "お題はみんなに見えます。当日まで伏せたいときは、予定の設定で切り替えてください。"
                 : "お題の中身は当日まで見えません。件数だけが共有されます。")
        }
    }

    /// 1駅ぶんの準備状況。
    /// 見せる設定なら中身と書いた人まで、伏せる設定なら件数だけを出す
    @ViewBuilder
    private func preparationRow(_ station: Station, _ row: MissionSummaryResponse) -> some View {
        let shared = missionsAreShared ? (row.missions ?? []) : []
        if shared.isEmpty {
            LabeledContent(station.name) {
                Text("\(row.count) 個")
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(station.name).font(.subheadline.bold())
                    Spacer()
                    Text("\(row.count) 個").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(shared) { mission in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mission.content)
                        Text(mission.createdByName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func refresh() async {
        guard sync.isJoined else { return }
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        // 見せる設定なら、みんなのお題を端末にも取り込む（着地した駅で引く候補になる）
        await sync.pullMissions(includeOthers: missionsAreShared)
        summary = await sync.missionSummary(includeContent: missionsAreShared)
    }
}

/// 予定から渡す対象。どのコースの、どの区間に書くか
struct MissionPlan: Identifiable {
    let id = UUID()
    let course: Course
    let startOrder: Int
    let goalOrder: Int
    let title: String
    /// お題の中身をみんなに見せるか。**既定は見せる**（予定側の設定で伏せられる）
    var sharesMissions = true
}

/// 編集中のお題。新規と書き換えを同じ画面で扱う
struct MissionDraft: Identifiable {
    let id = UUID()
    let existing: Mission?
    var stationOrder: Int
}

/// お題1件の入力（SC-13）
private struct MissionDraftView: View {

    @Bindable var store: GameSessionStore
    let draft: MissionDraft
    /// 書き込む先のコース。予定から開いたときは、まだ始めていないコースになる
    let course: Course?
    let stations: [Station]
    @Environment(\.dismiss) private var dismiss

    @State private var stationOrder: Int
    @State private var content: String
    @State private var errorMessage: String?

    init(store: GameSessionStore, draft: MissionDraft, course: Course?, stations: [Station]) {
        self.store = store
        self.draft = draft
        self.course = course
        self.stations = stations
        let mission = draft.existing
        _stationOrder = State(initialValue: mission?.station?.orderNo ?? draft.stationOrder)
        _content = State(initialValue: mission?.content ?? "")
    }

    /// 自分のお題が既にある駅は選べない（差し替えるならその駅のお題を編集する）
    private var selectableStations: [Station] {
        stations.filter { station in
            store.myMission(at: station.orderNo, in: course) == nil
                || station.orderNo == draft.existing?.station?.orderNo
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("駅") {
                    Picker("駅", selection: $stationOrder) {
                        ForEach(selectableStations) { Text($0.name).tag($0.orderNo) }
                    }
                }

                Section {
                    TextField("その駅でやること", text: $content, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("お題")
                } footer: {
                    Text("\(content.count) / 300 文字")
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(draft.existing == nil ? "お題を追加" : "お題を書き換える")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || content.count > 300)
                }
            }
        }
    }

    private func save() {
        errorMessage = store.saveMission(draft.existing,
                                         station: stationOrder,
                                         content: content,
                                         effect: .none,
                                         value: nil,
                                         jumpTo: nil,
                                         in: course)
        if errorMessage == nil { dismiss() }
    }
}
