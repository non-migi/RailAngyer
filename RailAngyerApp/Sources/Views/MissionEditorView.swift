import SwiftUI
import RailAngyerCore

/// ミッションの自作（SC-12）。
///
/// **駅ごとに、1メンバー1個まで**（企画仕様 / UQ-05）。
/// 自分が書いたお題だけが見える。他人のぶんは件数しか出さない（当日の驚きを守るため）。
struct MissionEditorView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var editing: MissionDraft?
    @State private var summary: [MissionSummaryResponse] = []
    @State private var isLoading = false

    private var stations: [Station] {
        (store.room?.course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }

    var body: some View {
        NavigationStack {
            List {
                mineSection
                if sync.isJoined { preparationSection }
            }
            .navigationTitle("お題を書く")
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
                MissionDraftView(store: store, draft: draft)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    // MARK: - 自分のお題

    @ViewBuilder
    private var mineSection: some View {
        Section {
            if store.myMissions.isEmpty {
                Text("まだ書いていません。右上の＋から追加してください。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.myMissions) { mission in
                Button {
                    editing = MissionDraft(existing: mission,
                                           stationOrder: mission.station?.orderNo ?? 1)
                } label: {
                    row(mission)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for mission in offsets.map({ store.myMissions[$0] }) {
                    store.deleteMission(mission)
                }
            }
        } header: {
            Text("あなたのお題　\(store.myMissions.count) / \(stations.count) 駅")
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
                if mission.effectType != .none {
                    Text(effectLabel(mission))
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            Text(mission.content)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    private func effectLabel(_ mission: Mission) -> String {
        switch mission.effectType {
        case .none:      return ""
        case .forward:   return "\(mission.effectValue ?? 0)駅進む"
        case .back:      return "\(mission.effectValue ?? 0)駅戻る"
        case .rollAgain: return "もう一度振る"
        case .jump:      return "\(mission.effectStation?.name ?? "?")へ"
        }
    }

    /// まだ自分のお題が無い駅のうち、いちばん手前
    private var firstFreeStation: Int? {
        stations.first { store.myMission(at: $0.orderNo) == nil }?.orderNo
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
                            if row.effectCount > 0 {
                                Text("効果 \(row.effectCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("みんなの準備状況")
        } footer: {
            // 戻る効果ばかりだと前に進まなくなる（E-08）
            Text("お題の中身は当日まで見えません。件数だけが共有されます。"
                 + (backHeavy ? "\n戻る効果が多めです。進まなくなる恐れがあります。" : ""))
        }
    }

    private var backHeavy: Bool {
        let total = summary.reduce(0) { $0 + $1.count }
        let back = summary.reduce(0) { $0 + $1.backEffectCount }
        return total >= 4 && back * 3 >= total
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
    @Environment(\.dismiss) private var dismiss

    @State private var stationOrder: Int
    @State private var content: String
    @State private var effect: EffectType
    @State private var value: Int
    @State private var jumpTo: Int
    @State private var errorMessage: String?

    init(store: GameSessionStore, draft: MissionDraft) {
        self.store = store
        self.draft = draft
        let mission = draft.existing
        _stationOrder = State(initialValue: mission?.station?.orderNo ?? draft.stationOrder)
        _content = State(initialValue: mission?.content ?? "")
        _effect = State(initialValue: mission?.effectType ?? .none)
        _value = State(initialValue: mission?.effectValue ?? 1)
        _jumpTo = State(initialValue: mission?.effectStation?.orderNo
                        ?? store.room?.startStation?.orderNo ?? 1)
    }

    private var stations: [Station] {
        (store.room?.course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }

    /// 自分のお題が既にある駅は選べない（差し替えるならその駅のお題を編集する）
    private var selectableStations: [Station] {
        stations.filter { station in
            store.myMission(at: station.orderNo) == nil
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

                Section {
                    Picker("効果", selection: $effect) {
                        ForEach(EffectType.allCases, id: \.self) { Text(name(of: $0)).tag($0) }
                    }
                    if effect.needsValue {
                        Stepper("駅数　\(value)", value: $value, in: 1...9)
                    }
                    if effect.needsStation {
                        Picker("移動先", selection: $jumpTo) {
                            ForEach(stations) { Text($0.name).tag($0.orderNo) }
                        }
                    }
                } header: {
                    Text("効果")
                } footer: {
                    Text(explanation)
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

    private func name(of effect: EffectType) -> String {
        switch effect {
        case .none:      return "なし"
        case .forward:   return "進む"
        case .back:      return "戻る"
        case .rollAgain: return "もう一度振る"
        case .jump:      return "指定の駅へ移動"
        }
    }

    private var explanation: String {
        switch effect {
        case .none:      return "お題をこなすだけ。コマは動きません。"
        case .forward:   return "達成の可否にかかわらず、ゴール方向へ\(value)駅ぶん歩いて移動します。"
        case .back:      return "スタート方向へ\(value)駅ぶん歩いて戻ります。区間の外へは出ません。"
        case .rollAgain: return "位置はそのままで、続けてもう一度サイコロを振ります。"
        case .jump:      return "指定した駅まで歩いて移動します。移動先ではお題を引きません。"
        }
    }

    private func save() {
        errorMessage = store.saveMission(draft.existing,
                                         station: stationOrder,
                                         content: content,
                                         effect: effect,
                                         value: effect.needsValue ? value : nil,
                                         jumpTo: effect.needsStation ? jumpTo : nil)
        if errorMessage == nil { dismiss() }
    }
}
