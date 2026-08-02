import SwiftUI
import RailAngyerCore

/// ミッションの自作（SC-12）。
///
/// **駅ごとに、1メンバー1個まで**（企画仕様 / UQ-05）。
/// 自分が書いたお題だけが見える。他人のぶんは件数しか出さない（当日の驚きを守るため）。
struct MissionEditorView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    /// 予定から開いたときの対象。**まだ始めていない旅のお題も書ける**ようにするためのもの。
    /// 省略すると、いま遊んでいるコース全体を対象にする
    var plan: MissionPlan?
    @Environment(\.dismiss) private var dismiss

    @State private var editing: MissionDraft?
    @State private var summary: [MissionSummaryResponse] = []
    @State private var isLoading = false

    private var course: Course? { plan?.course ?? store.room?.course }

    /// 対象の駅。**必ず区間の中だけに絞る。**
    ///
    /// 予定から開いたときはその予定の区間、
    /// ホームから開いたときは**いま遊んでいる区間**（コースの全駅ではない）。
    /// 区間の外の駅を出すと、絶対に着地しない駅にお題を書けてしまう
    private var stations: [Station] {
        let all = (course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }

        if let plan {
            // 一周はコース全体を通る。区間として絞ると1駅になってしまう
            if plan.isLap { return all }
            let range = min(plan.startOrder, plan.goalOrder)...max(plan.startOrder, plan.goalOrder)
            return all.filter { range.contains($0.orderNo) }
        }
        // 一周では区間＝コース全体になる。`stationsInOrder` がその判断まで持っている
        let inSection = store.stationsInOrder
        return inSection.isEmpty ? all : inSection
    }

    private var missions: [Mission] {
        let orders = Set(stations.map(\.orderNo))
        return store.myMissions(in: course).filter { orders.contains($0.station?.orderNo ?? -1) }
    }

    var body: some View {
        NavigationStack {
            List {
                mapSection
                mineSection
                if sync.isJoined { preparationSection }
            }
            .navigationTitle(plan.map { "\($0.title) のお題" } ?? "お題を書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
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
    }

    // MARK: - コースの地図

    /// **どこを歩くコースなのかを見ながらお題を書けるようにする。**
    /// 駅名だけでは、その駅がどんな場所か（川沿いか、商店街か）を思い出せない。
    /// お題を書き終えた駅にはチェックを付け、書き残しを地図の上で分かるようにする
    @ViewBuilder
    private var mapSection: some View {
        if stations.count >= 2 {
            Section {
                CourseSectionSummaryView(stations: stations,
                                         isLoop: isLap,
                                         markedOrders: writtenOrders,
                                         caption: sectionCaption)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
            } footer: {
                Text("チェックの付いた駅には、あなたのお題があります。")
            }
        }
    }

    private var writtenOrders: Set<Int> {
        Set(missions.compactMap { $0.station?.orderNo })
    }

    /// 一周の対象か。予定から開いたときは予定に従い、
    /// ホームから開いたときはいま遊んでいる設定に従う
    private var isLap: Bool {
        plan.map(\.isLap) ?? (store.room?.isLap == true)
    }

    private var sectionCaption: String {
        let name = course?.name ?? ""
        guard let start = stations.first, let goal = stations.last else { return name }
        return isLap ? "\(name)　\(start.name) から一周" : "\(name)　\(start.name) → \(goal.name)"
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
                    LabeledContent(station.name) {
                        HStack(spacing: 8) {
                            Text("\(row.count) 個")
                        }
                    }
                }
            }
        } header: {
            Text("みんなの準備状況")
        } footer: {
            Text("お題の中身は当日まで見えません。件数だけが共有されます。")
        }
    }

    private func refresh() async {
        guard sync.isJoined else { return }
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        await sync.pullMyMissions()
        summary = await sync.missionSummary()
    }
}

/// 予定から渡す対象。どのコースの、どの区間に書くか
struct MissionPlan: Identifiable {
    let id = UUID()
    let course: Course
    let startOrder: Int
    let goalOrder: Int
    let title: String
    /// 一周する予定か。**スタートとゴールが同じ駅**になるので、
    /// 区間として扱うと1駅しか取れない
    var isLap: Bool = false
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
                Section {
                    Picker("駅", selection: $stationOrder) {
                        ForEach(selectableStations) { Text($0.name).tag($0.orderNo) }
                    }
                    if stations.count >= 2 {
                        // 選んだ駅が区間のどこにあるかを地図で示す。
                        // 端どうしの駅は歩く距離が変わるため、書くお題の重さも変わる
                        CourseSectionMapView(stations: stations,
                                             highlightedOrder: stationOrder)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16,
                                                      bottom: 10, trailing: 16))
                    }
                } header: {
                    Text("駅")
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
