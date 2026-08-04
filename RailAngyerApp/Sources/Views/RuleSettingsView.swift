import SwiftUI
import RailAngyerCore

/// 区間と最大出目の設定（SC-02 のローカル版）。
/// プレイ開始後（ターンが1件でもある間）は変更できない（T-06）。
struct RuleSettingsView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Bindable var language: LanguageSetting
    @Environment(\.dismiss) private var dismiss

    @State private var startOrder = 1
    @State private var goalOrder = 16
    @State private var diceMax = 6
    @State private var showResetConfirm = false
    @State private var showingRoom = false
    @State private var visibilityError: String?
    @State private var showingHowToPlay = false
    @State private var document: DocumentView.Kind?
    @State private var showingSupport = false
    @State private var showingAttribution = false
    @State private var tipJar = TipJar()
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

                Section {
                    Picker("コース", selection: Binding(
                        get: { store.room?.course?.name ?? "" },
                        set: { name in
                            guard let course = store.courses.first(where: { $0.name == name }) else { return }
                            if store.updateCourse(course) {
                                startOrder = course.stations.map(\.orderNo).min() ?? 1
                                goalOrder = course.stations.map(\.orderNo).max() ?? 1
                            }
                        })) {
                            ForEach(store.courses) { course in
                                Text("\(course.name)（\(course.stations.count)駅）").tag(course.name)
                            }
                        }
                } header: {
                    Text("コース")
                } footer: {
                    Text("コースを変えると区間は両端に戻ります。"
                         + "前のコースに書いたお題は消えず、そのコースを選んだときに使えます。")
                }
                .disabled(locked)

                if store.room?.course?.isLoop == true { loopSection }

                if store.room?.isLap != true {
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
                }

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
                    Text("札幌3路線は国土交通省の鉄道データ（JGD2011）に合わせた駅位置です。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // **応援の導線はここに置く。** 一番下のアプリ情報に埋めると誰も見つけない。
                // ただし遊びの流れには一切割り込ませない（設定の中だけ）
                Section {
                    Picker("言語", selection: $language.selected) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("言語")
                } footer: {
                    Text("選ぶとすぐに切り替わります。訳が入っていないところは日本語のまま出ます。")
                }

                Section {
                    Button {
                        showingSupport = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.mission)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("開発者を応援する")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("1人で作っています。¥300から")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportDeveloper")
                } footer: {
                    Text("応援しても機能は増えません。気持ちだけを受け取る仕組みです。")
                }

                Section {
                    Button {
                        showingHowToPlay = true
                    } label: {
                        Label("遊び方", systemImage: "questionmark.circle")
                    }
                    Button {
                        document = .terms
                    } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    Button {
                        document = .privacy
                    } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                    Button {
                        showingAttribution = true
                    } label: {
                        Label("データの出典", systemImage: "map")
                    }
                } header: {
                    Text("使い方とお約束")
                } footer: {
                    Text("実際の道を歩く遊びです。歩きながら画面を操作しないでください。")
                }

                missionVisibilitySection

                syncSection

                Section("アプリ情報") {
                    HStack(spacing: 14) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("レイルアンギャー")
                                .font(.headline)
                            Text(versionText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button("記録を保存して新しい旅へ", role: .destructive) { showResetConfirm = true }
                        .disabled(store.room?.turns.isEmpty ?? true)
                } footer: {
                    Text("現在の旅は「記録」に保存され、同じルールで新しい旅を始められます。")
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
            .sheet(isPresented: $showingHowToPlay) {
                HowToPlayView()
            }
            .sheet(item: $document) { DocumentView(kind: $0) }
            .sheet(isPresented: $showingSupport) {
                SupportDeveloperView(tipJar: tipJar)
            }
            .sheet(isPresented: $showingAttribution) { AttributionView() }
            .confirmationDialog("現在の旅を保存して、新しい旅を始めますか",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("保存して新しい旅へ", role: .destructive) { store.resetProgress() }
            } message: {
                Text("訪問記録と写真は過去の旅として残ります。")
            }
            .onAppear {
                startOrder = store.room?.startStation?.orderNo ?? 1
                goalOrder = store.room?.goalStation?.orderNo ?? allStations.last?.orderNo ?? 16
                diceMax = store.room?.diceMax ?? 6
            }
        }
    }

    /// 環状のコースだけに出す。一周するか、どちらへまわるかを決める
    @ViewBuilder
    private var loopSection: some View {
        let course = store.room?.course

        Section {
            Toggle("一周する", isOn: Binding(
                get: { store.room?.isLap ?? false },
                set: { on in
                    if store.updateLap(on) {
                        startOrder = store.room?.startStation?.orderNo ?? startOrder
                        goalOrder = store.room?.goalStation?.orderNo ?? goalOrder
                    }
                }))

            if store.room?.isLap == true {
                Picker("まわる向き", selection: Binding(
                    get: { store.room?.loopDirectionRaw ?? 1 },
                    set: { _ = store.updateLoopDirection($0) })) {
                        Text(course?.forwardDirectionName ?? "順まわり").tag(1)
                        Text(course?.backwardDirectionName ?? "逆まわり").tag(-1)
                    }
                    .pickerStyle(.inline)

                Picker("出発する駅", selection: Binding(
                    get: { store.room?.startStation?.orderNo ?? 1 },
                    set: { _ = store.updateLapStart(orderNo: $0) })) {
                        ForEach(allStations) { Text($0.name).tag($0.orderNo) }
                    }
            }
        } header: {
            Text("環状線")
        } footer: {
            Text(store.room?.isLap == true
                 ? "出発した駅に戻ってきたら一周です。区間の設定は使いません。"
                 : "一周せず、区間を決めて歩くこともできます。")
        }
        .disabled(locked)
    }

    /// 未送信の状況（SC-20）。
    /// お題を当日まで伏せるか、いつでも見せるか。
    ///
    /// **遊び方そのものが変わる取り決め**なので、ルームの設定として持つ。
    /// 区間や出目と違い、プレイ中でも切り替えられる（記録の整合を壊さない）。
    @ViewBuilder
    private var missionVisibilitySection: some View {
        Section {
            Picker("お題の見え方", selection: Binding(
                get: { store.room?.missionVisibility ?? .surprise },
                set: { newValue in
                    store.updateMissionVisibility(newValue)
                    Task { visibilityError = await sync.updateMissionVisibility(newValue) }
                })) {
                ForEach(MissionVisibility.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if let error = visibilityError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("お題の見え方")
        } footer: {
            Text((store.room?.missionVisibility ?? .surprise).detail
                 + (sync.isJoined ? "" : "\n参加していないあいだは、この端末の中だけの設定です。"))
        }
    }

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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return "バージョン \(version)（\(build)）"
    }
}
