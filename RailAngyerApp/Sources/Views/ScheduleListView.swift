import SwiftUI
import RailAngyerCore

/// 予定と出欠（SC-21 / フェーズ3）。
///
/// 「いつ・どこに集まるか」「どう歩くか」「誰が来るか」を決める画面。
/// **予定を立てた人だけが直せる**が、出欠は各自が自分のぶんを答える。
///
/// 遊び方のルールはここで決める。端末の設定ではなく予定に紐づくので、
/// 「前回の設定が残っていて、今日の遊び方と違う」ということが起きない。
struct ScheduleListView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ScheduleDraft?
    @State private var isLoading = false
    @State private var loadingMessage = "予定を読み込み中…"
    @State private var showingFinished = false
    @State private var showResetConfirm = false

    /// 終わった予定を畳むかどうかの境目。開いている画面のあいだは動かさない。
    /// 秒ごとに `Date()` を読むと、リストが描き直されるたびに区切りがずれる
    @State private var now = Date()

    /// これからの予定は近いものから、終わった予定は新しいものから並べる
    private var upcoming: [Schedule] {
        store.schedules.filter { !$0.isFinished(asOf: now) }.sorted { $0.startAt < $1.startAt }
    }
    private var finished: [Schedule] {
        store.schedules.filter { $0.isFinished(asOf: now) }.sorted { $0.startAt > $1.startAt }
    }
    private var myFinished: [Schedule] { finished.filter(isMine) }

    var body: some View {
        NavigationStack {
            List {
                if store.schedules.isEmpty {
                    Section {
                        Text(sync.isJoined
                             ? "まだ予定がありません。右上の＋から立ててください。"
                             : "予定は参加しているルームで共有されます。ホームの「みんなで遊ぶ」から参加してください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if upcoming.isEmpty {
                    Section {
                        Text("これからの予定はありません。右上の＋から立ててください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                ForEach(upcoming) { schedule in
                    Section { scheduleRows(schedule) }
                }

                if !finished.isEmpty { finishedSection }

                currentJourneySection
                syncSection
            }
            .navigationTitle("予定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = ScheduleDraft(existing: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing, onDismiss: { Task { await syncAfterEdit() } }) { draft in
                ScheduleDraftView(store: store, draft: draft)
            }
            .overlay {
                if isLoading {
                    ProgressView(loadingMessage)
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .confirmationDialog("現在の旅を保存して、新しい旅を始めますか",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("保存して新しい旅へ", role: .destructive) { store.resetProgress() }
            } message: {
                Text("訪問記録と写真は過去の旅として残ります。")
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, .japanStandard)
        .environment(\.timeZone, .japanStandard)
    }

    // MARK: - 予定1件

    @ViewBuilder
    private func scheduleRows(_ schedule: Schedule) -> some View {
        header(schedule)
        attendancePicker(schedule)
        attendeeList(schedule)
        // シートを重ねず、この一覧の上に積む。「戻る」一回で予定へ帰れる
        if schedule.usesMissions {
            NavigationLink {
                if let plan = plan(for: schedule) {
                    MissionEditorView(store: store, sync: sync,
                                      plan: plan, isPushed: true)
                }
            } label: {
                Label("この予定のお題を書く", systemImage: "square.and.pencil")
            }
            .disabled(plan(for: schedule) == nil)
        }

        if isMine(schedule) {
            Button("この予定を消す", role: .destructive) {
                store.deleteSchedule(schedule)
            }
        }
    }

    /// 予定に決めたルールを、お題の編集画面へ渡す形にする。
    /// コースが決まっていない古い予定には渡せない
    private func plan(for schedule: Schedule) -> MissionPlan? {
        guard let course = store.courses.first(where: { $0.name == schedule.courseName })
        else { return nil }
        // 一周する予定はコースの全駅を通る。区間として渡すと1駅ぶんしか書けなくなる
        let orders = course.stations.map(\.orderNo)
        let start = schedule.isLap ? (orders.min() ?? schedule.startOrder) : schedule.startOrder
        let goal = schedule.isLap ? (orders.max() ?? schedule.goalOrder) : schedule.goalOrder
        return MissionPlan(course: course,
                           startOrder: start,
                           goalOrder: goal,
                           title: schedule.title,
                           sharesMissions: schedule.missionVisibility == .everyone)
    }

    private func isMine(_ schedule: Schedule) -> Bool {
        schedule.createdById == nil || schedule.createdById == store.me?.id
    }

    @ViewBuilder
    private func header(_ schedule: Schedule) -> some View {
        Button {
            guard isMine(schedule) else { return }
            editing = ScheduleDraft(existing: schedule)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title).font(.headline).foregroundStyle(.primary)
                Text(dateText(schedule))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !schedule.courseName.isEmpty {
                    Label(sectionText(schedule), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption).foregroundStyle(Theme.line)
                }
                Label(ruleText(schedule), systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
                if let place = schedule.meetPlace {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 集合日時。**コースのある土地の時計で読む。**
    /// 海外のコースを足したとき、日本時間のまま出すと集合できない
    private func dateText(_ schedule: Schedule) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: "ja_JP"),
                                     calendar: .japan(in: schedule.timeZone),
                                     timeZone: schedule.timeZone)
            .month().day().weekday().hour().minute()
        let text = schedule.startAt.formatted(style)
        guard schedule.timeZone != .japanStandard else { return text }
        return "\(text)（\(schedule.timeZone.identifier)）"
    }

    /// どこからどこまで歩くか
    private func sectionText(_ schedule: Schedule) -> String {
        let course = store.courses.first { $0.name == schedule.courseName }
        let start = course?.stations.first { $0.orderNo == schedule.startOrder }?.name ?? "—"
        if schedule.isLap {
            let direction = schedule.loopDirectionRaw >= 0
                ? course?.forwardDirectionName ?? "順まわり"
                : course?.backwardDirectionName ?? "逆まわり"
            return "\(schedule.courseName)　\(start) から一周（\(direction)）"
        }
        let goal = course?.stations.first { $0.orderNo == schedule.goalOrder }?.name ?? "—"
        return "\(schedule.courseName)　\(start) → \(goal)"
    }

    /// サイコロとお題をどう使うか。**「使わない」も立派な遊び方**なので、そのまま出す
    private func ruleText(_ schedule: Schedule) -> String {
        var parts: [String] = []
        parts.append(schedule.usesDice ? "サイコロ1〜\(schedule.diceMax)" : "サイコロなし")
        parts.append(schedule.usesMissions
                     ? "お題は\(schedule.missionVisibility.label)"
                     : "お題なし")
        if !schedule.isShared { parts.append("共有しない") }
        return parts.joined(separator: "　")
    }

    private func attendancePicker(_ schedule: Schedule) -> some View {
        Picker("あなたの出欠", selection: Binding(
            get: { store.myAttendance(schedule) },
            set: { store.answerAttendance(schedule, status: $0) })) {
                ForEach(AttendanceStatus.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func attendeeList(_ schedule: Schedule) -> some View {
        // 答えていない人は出さない。全員ぶんの行を並べても情報が増えない
        ForEach(schedule.attendees.filter { $0.status != .undecided }
                                  .sorted { $0.displayName < $1.displayName }) { attendee in
            LabeledContent(attendee.displayName) {
                Text(attendee.status.label)
                    .foregroundStyle(attendee.status == .going ? Theme.line : .secondary)
            }
            .font(.subheadline)
        }
    }

    // MARK: - 終わった予定

    /// 済んだ予定は**消さずに畳む。**
    ///
    /// 消してしまうと「いつ誰と歩いたか」を後から辿れない。
    /// かといって並べたままだと、これからの予定が埋もれて見つからなくなる
    private var finishedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showingFinished) {
                ForEach(finished) { schedule in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.title).font(.subheadline)
                        Text(dateText(schedule)).font(.caption).foregroundStyle(.secondary)
                        if !schedule.courseName.isEmpty {
                            Text(sectionText(schedule))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !myFinished.isEmpty {
                    Button("終わった予定をまとめて消す", role: .destructive) {
                        for schedule in myFinished { store.deleteSchedule(schedule) }
                    }
                    .font(.subheadline)
                }
            } label: {
                Label("終わった予定（\(finished.count)件）", systemImage: "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("集合日の翌日になった予定はここへ畳まれます。"
                 + "消せるのは自分で立てた予定だけです。")
        }
    }

    // MARK: - いまの旅

    /// 設定から移してきた「記録を保存して新しい旅へ」。
    /// 旅の段取りをする場所に置くほうが、遊び方のルールと並んで筋が通る
    private var currentJourneySection: some View {
        Section {
            Button("記録を保存して新しい旅へ", role: .destructive) { showResetConfirm = true }
                .disabled(store.room?.turns.isEmpty ?? true)
        } header: {
            Text("いまの旅")
        } footer: {
            Text("現在の旅は「記録」に保存され、次の予定を新しい旅として始められます。")
        }
    }

    /// 未送信の状況（SC-20）。
    /// 送れていなくてもプレイは続けられるので、**警告ではなく状態として見せる**。
    /// 参加そのものはホームの「みんなで遊ぶ」から行う（入口は1か所にまとめる）
    @ViewBuilder
    private var syncSection: some View {
        Section("共有") {
            if sync.isJoined {
                LabeledContent("ルーム", value: store.room?.name ?? "参加中")
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
                Text("この端末だけで遊んでいます。記録はサーバーに送られません。"
                     + "ホームの「みんなで遊ぶ」から参加できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 読み込み

    private func refresh() async {
        now = Date()
        store.reloadSchedules()          // 端末に持っているぶんを先に出す
        guard sync.isJoined else { return }
        loadingMessage = "予定を読み込み中…"
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        await sync.pullSchedules()
        store.reloadSchedules()
    }

    /// 予定を足した・直した直後。**保存そのものは端末で完結している**ので、
    /// 一覧にはすでに出ている。ここで待つのは、仲間へ届けるための送信だけ
    private func syncAfterEdit() async {
        now = Date()
        store.reloadSchedules()
        guard sync.isJoined else { return }
        loadingMessage = "みんなに共有中…"
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        await sync.pullSchedules()
        store.reloadSchedules()
    }
}

struct ScheduleDraft: Identifiable {
    let id = UUID()
    let existing: Schedule?
}

/// 予定1件の入力。
///
/// **上から順に決めれば予定ができあがる**ように並べてある。
/// どこを歩くか（コース→区間）→ 名前 → 道のりの確認 → 集合 → 詳細設定、の順。
/// サイコロもお題も任意で、両方使わない「そのまま歩くだけ」の予定も立てられる。
private struct ScheduleDraftView: View {

    @Bindable var store: GameSessionStore
    let draft: ScheduleDraft
    @Environment(\.dismiss) private var dismiss

    @State private var courseName: String
    @State private var startOrder: Int
    @State private var goalOrder: Int
    @State private var isLap: Bool
    @State private var loopDirection: Int

    @State private var title: String
    @State private var startAt: Date
    @State private var meetPlace: String

    @State private var usesDice: Bool
    @State private var diceMax: Int
    @State private var usesMissions: Bool
    @State private var missionVisibility: ScheduleMissionVisibility
    @State private var arrivalRadius: Double
    @State private var isShared: Bool

    @State private var showingDetail = false
    @State private var errorMessage: String?

    /// 端末の到着判定。予定に半径を決めていない古い予定と、
    /// 到着判定を持たないコースはこの値で歩く（RootView が読んでいる設定と同じもの）
    @AppStorage("arrivalRadius") private var deviceArrivalRadius: Double = ArrivalRule.default.radius

    init(store: GameSessionStore, draft: ScheduleDraft) {
        self.store = store
        self.draft = draft
        let existing = draft.existing

        let initialCourse = existing?.courseName.nilIfEmpty ?? store.room?.course?.name ?? ""
        _courseName = State(initialValue: initialCourse)
        _startOrder = State(initialValue: (existing?.startOrder ?? 0) > 0
                            ? existing!.startOrder : store.room?.startStation?.orderNo ?? 1)
        _goalOrder = State(initialValue: (existing?.goalOrder ?? 0) > 0
                           ? existing!.goalOrder : store.room?.goalStation?.orderNo ?? 1)
        _isLap = State(initialValue: existing?.isLap ?? false)
        _loopDirection = State(initialValue: existing?.loopDirectionRaw ?? 1)

        _title = State(initialValue: existing?.title ?? "")
        // 既定は次の土曜の朝9時。歩くのはたいてい休日の午前から
        _startAt = State(initialValue: existing?.startAt ?? Self.nextSaturdayMorning())
        _meetPlace = State(initialValue: existing?.meetPlace ?? "")

        // 既定は「お題あり・共有オン・お題は全員に見える」
        _usesDice = State(initialValue: existing?.usesDice ?? true)
        _diceMax = State(initialValue: existing?.diceMax ?? store.room?.diceMax ?? 6)
        _usesMissions = State(initialValue: existing?.usesMissions ?? true)
        _missionVisibility = State(initialValue: existing?.missionVisibility ?? .everyone)
        _isShared = State(initialValue: existing?.isShared ?? true)

        // 予定に決めた値 → コース既定 → いま端末が使っている値 の順に拾う。
        // `@AppStorage` は init では読めないので、同じ鍵を直接見る
        let course = store.courses.first { $0.name == initialCourse }
        let device = UserDefaults.standard.object(forKey: "arrivalRadius") as? Double
        let radius = existing?.arrivalRadius ?? course?.arrivalRadius
            ?? device ?? ArrivalRule.default.radius
        _arrivalRadius = State(initialValue: min(max(radius, ArrivalRule.radiusRange.lowerBound),
                                                 ArrivalRule.radiusRange.upperBound))
    }

    private var selectedCourse: Course? { store.courses.first { $0.name == courseName } }
    private var stations: [Station] {
        (selectedCourse?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }
    private var canLap: Bool { selectedCourse?.isLoop == true }
    /// 一周は出発した駅へ戻ってくる。ゴールはスタートと同じ駅になる
    private var effectiveGoalOrder: Int { isLap ? startOrder : goalOrder }
    private var timeZone: TimeZone { selectedCourse?.timeZone ?? .japanStandard }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCourse != nil
            && (isLap || startOrder != goalOrder)
    }

    var body: some View {
        NavigationStack {
            Form {
                courseSection
                sectionSection
                titleSection
                distanceSection
                meetingSection
                placeSection
                detailSection

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(draft.existing == nil ? "予定を立てる" : "予定を書き換える")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: courseName) {
                // コースが変わると駅の通し番号の意味が変わる。区間は両端に戻す
                guard let first = stations.first, let last = stations.last else { return }
                startOrder = first.orderNo
                goalOrder = last.orderNo
                if !canLap { isLap = false }
                arrivalRadius = selectedCourse?.arrivalRadius ?? ArrivalRule.default.radius
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, .japan(in: timeZone))
        .environment(\.timeZone, timeZone)
    }

    // MARK: - 1 コース

    private var courseSection: some View {
        Section {
            Picker("コース", selection: $courseName) {
                ForEach(store.courses) { course in
                    Text("\(course.name)（\(course.stations.count)駅）").tag(course.name)
                }
            }
        } header: {
            Text("1　コース")
        } footer: {
            Text("まず、どの路線に沿って歩くかを決めます。")
        }
    }

    // MARK: - 2 区間

    @ViewBuilder
    private var sectionSection: some View {
        Section {
            if canLap {
                Toggle("一周する", isOn: $isLap)
                if isLap {
                    Picker("まわる向き", selection: $loopDirection) {
                        Text(selectedCourse?.forwardDirectionName ?? "順まわり").tag(1)
                        Text(selectedCourse?.backwardDirectionName ?? "逆まわり").tag(-1)
                    }
                    .pickerStyle(.inline)
                }
            }

            Picker(isLap ? "出発する駅" : "スタート", selection: $startOrder) {
                ForEach(stations) { Text($0.name).tag($0.orderNo) }
            }
            if !isLap {
                Picker("ゴール", selection: $goalOrder) {
                    ForEach(stations) { Text($0.name).tag($0.orderNo) }
                }
                if startOrder == goalOrder {
                    Text("スタートとゴールは別の駅にしてください")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("2　区間")
        } footer: {
            Text(isLap
                 ? "出発した駅に戻ってきたら一周です。"
                 : "スタートとゴールを決めます。環状のコースなら一周もできます。")
        }
    }

    // MARK: - 3 予定の名前

    private var titleSection: some View {
        Section("3　予定の名前") {
            TextField("南北線を歩く", text: $title)
        }
    }

    // MARK: - 4 歩く道のり

    /// 決めた区間から出る、その日の歩く量の見当。
    /// **入力ではなく結果**なので、読むだけの行として置く
    private var distanceSection: some View {
        Section {
            LabeledContent("駅の数", value: "\(stationCount) 駅")
            LabeledContent("おおよその道のり",
                           value: String(format: "約 %.1f km", Double(stationCount - 1) * 0.94))
            if usesDice {
                LabeledContent("1ターンで進む駅",
                               value: "1〜\(diceMax) 駅")
            } else {
                LabeledContent("1ターンで進む駅", value: "1 駅ずつ")
            }
        } header: {
            Text("4　歩く道のり")
        } footer: {
            Text("駅の間はおよそ0.94kmとして計算しています。実際の道のりは経路によって変わります。")
        }
    }

    /// 歩く駅の数。一周はコース一周ぶん、区間なら両端を含めた数
    private var stationCount: Int {
        if isLap { return max(stations.count + 1, 1) }
        return abs(goalOrder - startOrder) + 1
    }

    // MARK: - 5 集合日時

    private var meetingSection: some View {
        Section {
            DatePicker("集合日", selection: $startAt, displayedComponents: .date)
                .datePickerStyle(.graphical)
            DatePicker("集合時刻", selection: $startAt, displayedComponents: .hourAndMinute)
        } header: {
            Text("5　集合日時（\(timeZoneLabel)）")
        } footer: {
            Text("コースのある土地の時計で入力します。"
                 + "海外のコースを足したときも、その土地の時刻で集合できます。")
        }
    }

    private var timeZoneLabel: String {
        timeZone == .japanStandard ? "日本時間" : timeZone.identifier
    }

    // MARK: - 6 集合場所

    private var placeSection: some View {
        Section {
            TextField("麻生駅 改札前", text: $meetPlace)
        } header: {
            Text("6　集合場所")
        } footer: {
            Text("空でも構いません。当日の連絡は各自の連絡手段で。")
        }
    }

    // MARK: - 7 詳細設定

    /// 決めなくても遊べるものは、畳んだ中に入れておく。
    /// 既定のまま（サイコロあり・お題あり・全員に見える・共有オン）で成立する
    private var detailSection: some View {
        Section {
            DisclosureGroup("詳細設定", isExpanded: $showingDetail) {
                Toggle("サイコロを使う", isOn: $usesDice)
                if usesDice {
                    Stepper("最大出目　\(diceMax)", value: $diceMax, in: 1...9)
                    if diceMax == 1 {
                        Text("毎ターン必ず1駅ずつ進みます")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("サイコロを振らず、1駅ずつ順に歩きます。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("お題を使う", isOn: $usesMissions)
                if usesMissions {
                    Picker("お題の見え方", selection: $missionVisibility) {
                        ForEach(ScheduleMissionVisibility.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                } else {
                    Text("お題は出しません。駅を巡って歩くだけの予定になります。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Stepper("到着とみなす半径　\(Int(arrivalRadius)) m",
                        value: $arrivalRadius,
                        in: ArrivalRule.radiusRange,
                        step: 10)

                Toggle("仲間と共有する", isOn: $isShared)
                if !isShared {
                    Text("この予定はこの端末の中だけに置きます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("7　詳細設定")
        } footer: {
            Text("決めなくても遊べます。"
                 + "サイコロもお題も使わない、そのまま歩くだけの予定にもできます。"
                 + "半径を大きくしすぎると隣の駅の圏内と重なるため、"
                 + "\(Int(ArrivalRule.radiusRange.upperBound))m までにしています。")
        }
    }

    // MARK: - 保存

    private func save() {
        errorMessage = store.saveSchedule(draft.existing, title: title,
                                          startAt: startAt, meetPlace: meetPlace,
                                          course: selectedCourse,
                                          startOrder: startOrder,
                                          goalOrder: effectiveGoalOrder,
                                          diceMax: diceMax,
                                          isLap: isLap,
                                          loopDirection: loopDirection,
                                          usesDice: usesDice,
                                          usesMissions: usesMissions,
                                          missionVisibility: missionVisibility.rawValue,
                                          arrivalRadius: arrivalRadius,
                                          isShared: isShared,
                                          timeZoneIdentifier: selectedCourse?.timeZoneIdentifier)
        guard errorMessage == nil else { return }
        // 到着判定は端末が見ている値でもある。予定に決めた半径をそのまま効かせる
        deviceArrivalRadius = arrivalRadius
        dismiss()
    }

    private static func nextSaturdayMorning() -> Date {
        let calendar = Calendar.japanStandard
        let base = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        return calendar.nextDate(after: base,
                                 matching: DateComponents(hour: 9, weekday: 7),
                                 matchingPolicy: .nextTime) ?? base
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
