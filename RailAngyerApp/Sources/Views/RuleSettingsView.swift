import SwiftUI
import RailAngyerCore

/// 区間と最大出目の設定（SC-02 のローカル版）。
/// プレイ開始後（ターンが1件でもある間）は変更できない（T-06）。
struct RuleSettingsView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var startOrder = 1
    @State private var goalOrder = 16
    @State private var diceMax = 6
    @State private var showResetConfirm = false
    @State private var showingRoom = false
    @AppStorage("arrivalRadius") private var arrivalRadius: Double = ArrivalRule.default.radius

    private var allStations: [Station] {
        (store.room?.course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }
    private var locked: Bool { !(store.room?.turns.isEmpty ?? true) }
    private var sectionCount: Int { abs(goalOrder - startOrder) + 1 }
    private var direction: String { goalOrder > startOrder ? "順方向" : "逆方向" }

    var body: some View {
        NavigationStack {
            Form {
                if locked {
                    Section {
                        Label("プレイ中は変更できません。記録をリセットすると変更できます。",
                              systemImage: "lock")
                            .font(.footnote)
                    }
                }

                Section("区間") {
                    Picker("スタート", selection: $startOrder) {
                        ForEach(allStations) { Text($0.name).tag($0.orderNo) }
                    }
                    Picker("ゴール", selection: $goalOrder) {
                        ForEach(allStations) { Text($0.name).tag($0.orderNo) }
                    }
                    if startOrder == goalOrder {
                        Text("スタートとゴールは別の駅にしてください")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        LabeledContent("区間", value: "\(sectionCount) 駅（\(direction)）")
                    }
                }
                .disabled(locked)

                Section("サイコロ") {
                    Stepper("最大出目　\(diceMax)", value: $diceMax, in: 1...9)
                    if diceMax == 1 {
                        Text("毎ターン必ず1駅ずつ進むため、区間の全駅でミッションを行います")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("1ターンの最大距離の目安",
                                   value: String(format: "約 %.1f km", Double(diceMax) * 0.94))
                    LabeledContent("着地回数の見込み",
                                   value: "\(max(1, sectionCount / max(1, (diceMax + 1) / 2))) 回前後")
                }
                .disabled(locked)

                Section("到着判定") {
                    Stepper("半径　\(Int(arrivalRadius)) m",
                            value: $arrivalRadius,
                            in: ArrivalRule.radiusRange,
                            step: 10)
                    Text("南北線の最短駅間は約655m（大通〜すすきの）。"
                         + "半径を大きくしすぎると隣の駅の圏内と重なるため、"
                         + "\(Int(ArrivalRule.radiusRange.upperBound))m までに制限しています。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("座標は概値のため、現地で判定が合わない駅があれば調整してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                syncSection

                Section {
                    Button("記録をリセット", role: .destructive) { showResetConfirm = true }
                        .disabled(store.room?.turns.isEmpty ?? true)
                } footer: {
                    Text("訪問記録と写真がすべて消えます。ミッションと設定は残ります。")
                }
            }
            .navigationTitle("ルール設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(locked || startOrder == goalOrder)
                }
            }
            .sheet(isPresented: $showingRoom) {
                RoomJoinView(store: store, sync: sync)
            }
            .confirmationDialog("記録をリセットしますか",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("リセットする", role: .destructive) { store.resetProgress() }
            } message: {
                Text("訪問記録と写真が消えます。取り消せません。")
            }
            .onAppear {
                startOrder = store.room?.startStation?.orderNo ?? 1
                goalOrder = store.room?.goalStation?.orderNo ?? allStations.last?.orderNo ?? 16
                diceMax = store.room?.diceMax ?? 6
            }
        }
    }

    /// 未送信の状況（SC-20）。
    /// 送れていなくてもプレイは続けられるので、**警告ではなく状態として見せる**
    @ViewBuilder
    private var syncSection: some View {
        Section("共有") {
            Button {
                showingRoom = true
            } label: {
                LabeledContent("みんなで遊ぶ",
                               value: sync.isJoined ? (store.room?.name ?? "参加中") : "未参加")
            }

            if sync.isJoined {
                LabeledContent("未送信", value: sync.pendingCount == 0
                               ? "なし" : "\(sync.pendingCount) 件")
                if let at = sync.lastSyncedAt {
                    LabeledContent("最後に同期", value: at.formatted(date: .omitted, time: .shortened))
                }
                if let error = sync.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                Button("いま送る") {
                    Task {
                        await sync.push()
                        await sync.pull()
                    }
                }
                .disabled(sync.isSyncing)
            } else {
                Text("この端末だけで遊んでいます。記録はサーバーに送られません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let start = allStations.first { $0.orderNo == startOrder }
        let goal = allStations.first { $0.orderNo == goalOrder }
        if store.updateRule(start: start, goal: goal, diceMax: diceMax) { dismiss() }
    }
}
