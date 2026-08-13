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
    @Environment(\.locale) private var locale

    @State private var editing: ScheduleDraft?
    @State private var isLoading = false
    @State private var loadingMessage = appLocalized("予定を読み込み中…")
    @State private var sharing: SharingText?
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
            .sheet(item: $sharing) { ShareSheet(items: [$0.text]) }
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
    }

    // MARK: - 予定1件

    @ViewBuilder
    private func scheduleRows(_ schedule: Schedule) -> some View {
        header(schedule)
        sectionMap(schedule)
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

        // **`ShareLink` に `.simultaneousGesture` を足したら、
        // 押しても何も起きなくなった。** 記録を取りたいので、
        // ボタンから共有シートを出す形にしてある
        Button {
            Telemetry.scheduleShared()
            sharing = SharingText(text: ScheduleShare.text(
                for: schedule, course: course(for: schedule), room: store.room))
        } label: {
            Label("この予定を共有する", systemImage: "square.and.arrow.up")
        }

        if isMine(schedule) {
            Button("この予定を消す", role: .destructive) {
                store.deleteSchedule(schedule)
            }
        }
    }

    /// 予定の区間を地図と目安で見せる。コースが分からない古い予定には出さない
    @ViewBuilder
    private func sectionMap(_ schedule: Schedule) -> some View {
        let stations = ScheduleShare.sectionStations(schedule, course: course(for: schedule))
        if stations.count >= 2 {
            CourseSectionSummaryView(
                stations: stations,
                isLoop: schedule.isLap,
                caption: sectionText(schedule))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private func course(for schedule: Schedule) -> Course? {
        store.courses.first { $0.name == schedule.courseName }
    }

    /// 予定に決めたルールを、お題の編集画面へ渡す形にする。
    /// コースが決まっていない古い予定には渡せない
    private func plan(for schedule: Schedule) -> MissionPlan? {
        guard let course = course(for: schedule) else { return nil }
        return MissionPlan(course: course,
                           startOrder: schedule.startOrder,
                           goalOrder: schedule.goalOrder,
                           title: schedule.title,
                           sharesMissions: schedule.missionVisibility == .everyone,
                           isLap: schedule.isLap)
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
                Label(ruleText(schedule), systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
                if let place = schedule.meetPlace {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isPending(schedule) {
                    Label("みんなにはまだ届いていません", systemImage: "arrow.up.circle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// この予定が、まだ仲間のところへ届いていないか。
    ///
    /// **「未送信◯件」という数え方はやめた。** 何が送られていないのか分からず、
    /// 直しようもないので不安だけが残る。届いていない予定そのものに印を付ける。
    ///
    /// ルームに参加していないときは出さない（送る先が無いのが正しい状態）。
    /// 「共有しない」と決めた予定にも出さない（届かないのが決めたとおりの動き）。
    private func isPending(_ schedule: Schedule) -> Bool {
        sync.isJoined
            && schedule.isShared
            && schedule.syncStateRaw != SyncState.synced.rawValue
    }

    /// 集合日時。**コースのある土地の時計で読む。**
    /// 海外のコースでは、日本時間のまま出すと集合できない
    private func dateText(_ schedule: Schedule) -> String {
        let style = Date.FormatStyle(locale: locale,
                                     calendar: .japan(in: schedule.timeZone),
                                     timeZone: schedule.timeZone)
            .month().day().weekday().hour().minute()
        let text = schedule.startAt.formatted(style)
        guard schedule.timeZone != .japanStandard else { return text }
        return appLocalized("\(text)（現地時間）")
    }

    /// どこからどこまで歩くか
    private func sectionText(_ schedule: Schedule) -> String {
        let course = course(for: schedule)
        let start = course?.stations.first { $0.orderNo == schedule.startOrder }?.name ?? "—"
        if schedule.isLap {
            let direction = schedule.loopDirectionRaw >= 0
                ? course?.forwardDirectionName ?? appLocalized("順まわり")
                : course?.backwardDirectionName ?? appLocalized("逆まわり")
            return appLocalized("\(schedule.courseName)　\(start) から一周（\(direction)）")
        }
        let goal = course?.stations.first { $0.orderNo == schedule.goalOrder }?.name ?? "—"
        return appLocalized("\(schedule.courseName)　\(start) → \(goal)")
    }

    /// サイコロとお題をどう使うか。**「使わない」も立派な遊び方**なので、そのまま出す
    private func ruleText(_ schedule: Schedule) -> String {
        var parts: [String] = []
        parts.append(schedule.usesDice
                     ? appLocalized("サイコロ1〜\(schedule.diceMax)")
                     : appLocalized("サイコロなし"))
        if schedule.usesMissions {
            // 取り組み方は当日の動きがいちばん変わるところなので、見え方より先に出す
            parts.append(appLocalized("お題は\(schedule.missionStyle.label)"))
            parts.append(schedule.missionVisibility.label)
        } else {
            parts.append(appLocalized("お題なし"))
        }
        // 「共有しない」だと、送れていないのか送らない決めなのかが読み取れない。
        // 決めたとおりに端末の中だけへ置いている、と分かる言い方にする
        if !schedule.isShared { parts.append(appLocalized("この端末だけ")) }
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
            Text("集合日の翌日になった予定はここへ畳まれます。消せるのは自分で立てた予定だけです。")
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

    // 「共有」の常設セクション（ルーム名・未送信◯件・最後に同期・いま送る）は外した。
    // **何が送られていないのか分からない数字**で、見た人が不安になるだけだった。
    // ルームの状態と未送信件数はホームの「みんなで遊ぶ」に出ている。
    // 送り直しはこの一覧を下へ引く（`refreshable`）と行われる。

    // MARK: - 読み込み

    private func refresh() async {
        now = Date()
        store.reloadSchedules()          // 端末に持っているぶんを先に出す
        guard sync.isJoined else { return }
        loadingMessage = appLocalized("予定を読み込み中…")
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
        loadingMessage = appLocalized("みんなに共有中…")
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        await sync.pullSchedules()
        store.reloadSchedules()
    }
}

/// 共有する本文を `sheet(item:)` へ渡すための包み
private struct SharingText: Identifiable {
    let id = UUID()
    let text: String
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
    @State private var missionStyle: MissionStyle
    @State private var includesOwnMissions: Bool
    @State private var arrivalRadius: Double
    @State private var isShared: Bool

    @State private var showingCoursePicker = false
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

        // **名前が空でも保存できる。** 空のままなら「南北線を歩く」のような既定の名前を付ける。
        // 空だと保存を止める作りにしていたころ、入力欄が画面の外にあって
        // 「なぜ押せないのか分からない」状態になっていた
        _title = State(initialValue: existing?.title ?? "")
        // 既定は次の土曜の朝9時。歩くのはたいてい休日の午前から
        _startAt = State(initialValue: existing?.startAt ?? Self.nextSaturdayMorning())
        _meetPlace = State(initialValue: existing?.meetPlace ?? "")

        // 既定は「お題あり・共有オン・お題は全員に見える」
        _usesDice = State(initialValue: existing?.usesDice ?? true)
        _diceMax = State(initialValue: existing?.diceMax ?? store.room?.diceMax ?? 6)
        _usesMissions = State(initialValue: existing?.usesMissions ?? true)
        _missionVisibility = State(initialValue: existing?.missionVisibility ?? .everyone)
        // 既定は「みんなで1つ」。これまでどおりの遊び方から変えない
        _missionStyle = State(initialValue: existing?.missionStyle ?? .team)
        _includesOwnMissions = State(initialValue: existing?.includesOwnMissions ?? true)
        _isShared = State(initialValue: existing?.isShared ?? true)

        // 予定に決めた値 → コース既定 → いま端末が使っている値 の順に拾う。
        // `@AppStorage` は init では読めないので、同じ鍵を直接見る
        let course = store.courses.first { $0.name == initialCourse }
        let device = UserDefaults.standard.object(forKey: "arrivalRadius") as? Double
        let radius = existing?.arrivalRadius ?? course?.arrivalRadius
            ?? device ?? ArrivalRule.default.radius
        _arrivalRadius = State(initialValue: Self.clampRadius(radius))
    }

    private var selectedCourse: Course? { store.courses.first { $0.name == courseName } }
    private var stations: [Station] {
        (selectedCourse?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }
    private var canLap: Bool { selectedCourse?.isLoop == true }
    /// 一周は出発した駅へ戻ってくる。ゴールはスタートと同じ駅になる
    private var effectiveGoalOrder: Int { isLap ? startOrder : goalOrder }
    private var timeZone: TimeZone { selectedCourse?.timeZone ?? .japanStandard }

    /// 選んだコースの駅名。**いま遊んでいるコースとは限らない**ので、選んだほうから引く
    private func stationName(_ order: Int) -> String {
        stations.first { $0.orderNo == order }?.name ?? "-"
    }

    /// いま選んでいる区間の駅。地図と目安に渡す。
    /// 一周ではコース全体を通るので、全駅が対象になる
    private var sectionStations: [Station] {
        if isLap { return stations }
        let range = min(startOrder, goalOrder)...max(startOrder, goalOrder)
        return stations.filter { range.contains($0.orderNo) }
    }

    /// 保存するときの名前。空のままなら既定の名前を付ける
    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle(selectedCourse?.name) : trimmed
    }

    private var canSave: Bool {
        selectedCourse != nil && (isLap || startOrder != goalOrder)
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
            .sheet(isPresented: $showingCoursePicker) {
                CoursePickerView(courses: store.courses, selectedName: $courseName)
            }
            .onChange(of: courseName) {
                // コースが変わると駅の通し番号の意味が変わる。区間は両端に戻す。
                // 環状でないコースへ変えたら、一周の設定は残さない
                if !canLap { isLap = false }
                arrivalRadius = Self.clampRadius(selectedCourse?.arrivalRadius
                                                 ?? ArrivalRule.default.radius)
                guard let first = stations.first, let last = stations.last else { return }
                startOrder = first.orderNo
                goalOrder = last.orderNo
            }
        }
        .environment(\.calendar, .japan(in: timeZone))
        .environment(\.timeZone, timeZone)
    }

    // MARK: - 1 コース

    private var courseSection: some View {
        Section {
            Button {
                showingCoursePicker = true
            } label: {
                HStack(spacing: 6) {
                    Text("コース").foregroundStyle(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(courseName.isEmpty ? "選ぶ" : courseName)
                            .foregroundStyle(.secondary)
                        if let course = selectedCourse {
                            Text("\(CourseDirectory.regionText(course))　\(course.stations.count)駅")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("coursePicker")
        } header: {
            Text("1　コース")
        } footer: {
            Text("まず、どの路線に沿って歩くかを決めます。国 → 都道府県 → 路線 の順にたどります。")
        }
    }

    // MARK: - 2 区間

    @ViewBuilder
    private var sectionSection: some View {
        Section {
            // **環状線は一周できる。** 山手線を東京から出て東京へ戻る形。
            // 一周のときは「別の駅にしてください」を出してはいけない
            if canLap {
                Toggle("一周する", isOn: $isLap)
                if isLap {
                    Picker("まわる向き", selection: $loopDirection) {
                        // `Text(String)` はキー扱いにならない。フォールバックの文言は自分で引く
                        Text(selectedCourse?.forwardDirectionName ?? appLocalized("順まわり")).tag(1)
                        Text(selectedCourse?.backwardDirectionName ?? appLocalized("逆まわり")).tag(-1)
                    }
                }
            }

            Picker(isLap ? "出発する駅" : "スタート", selection: $startOrder) {
                ForEach(stations) { Text($0.name).tag($0.orderNo) }
            }
            if isLap {
                Text("\(stationName(startOrder)) を出て、\(stationName(startOrder)) へ戻ってきたら終わりです")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
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
            Text("スタートとゴールを決めます。環状のコースなら一周もできます。")
        }
    }

    // MARK: - 3 予定の名前

    /// **名前は地図より先に置く。** 地図を先に挟んだところ、
    /// 名前の入力欄が画面の外へ押し出され、見つけられなくなった
    private var titleSection: some View {
        Section {
            TextField("南北線を歩く", text: $title)
        } header: {
            Text("3　予定の名前")
        } footer: {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "空のままなら「\(Self.defaultTitle(selectedCourse?.name))」として保存します。"
                 : "予定の一覧とお題の画面に出る名前です。")
        }
    }

    // MARK: - 4 歩く道のり

    /// 決めた区間から出る、その日の歩く量の見当。
    /// **入力ではなく結果**なので、地図と目安を読むだけの行として置く
    @ViewBuilder
    private var distanceSection: some View {
        if sectionStations.count >= 2 {
            Section {
                CourseSectionSummaryView(stations: sectionStations, isLoop: isLap)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
                LabeledContent("1ターンで進む駅",
                               value: usesDice ? "1〜\(diceMax) 駅" : "1 駅ずつ")
            } header: {
                Text("4　歩く道のり")
            } footer: {
                Text("目安は駅と駅を直線で結び、迂回のぶん（1.3倍）を足して時速5kmで歩いたときの値です。お題や休憩の時間は含みません。")
            }
        }
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
            Text("コースのある土地の時計で入力します。海外のコースでも、その土地の時刻で集合できます。")
        }
    }

    private var timeZoneLabel: String {
        timeZone == .japanStandard ? appLocalized("日本時間") : appLocalized("現地時間")
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
                    Picker("お題の取り組み方", selection: $missionStyle) {
                        ForEach(MissionStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Text(missionStyle.detail)
                        .font(.caption).foregroundStyle(.secondary)

                    // 自分の書いたお題を引くかどうかは、**めいめいで取り組むときだけの話**。
                    // みんなで1つのときは誰か1人が引いて全員でやるので、作者は関係ない
                    if missionStyle == .individual {
                        // **選ぶ時点で割り切りを伝える。** めいめいの結果は端末の中だけに持つ作りなので、
                        // 後から「仲間の画面に出ない」と気づくのでは遅い
                        Label("引いたお題と結果はこの端末に記録されます。仲間の画面には出ません。",
                              systemImage: "iphone")
                            .font(.caption).foregroundStyle(.secondary)

                        Toggle("自分のお題も抽選に含める", isOn: $includesOwnMissions)
                        if includesOwnMissions {
                            Text("自分で書いたお題が自分に当たることがあります。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("自分で書いたお題は自分には当たりません。人数ぶんのお題が足りないと、お題なしで進む駅が出ます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

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
            Text("決めなくても遊べます。サイコロもお題も使わない、そのまま歩くだけの予定にもできます。\nお題は既定で「みんなで1つ」です。着いた駅で引いた1つのお題に、全員で同じように取り組みます。\n半径を大きくしすぎると隣の駅の圏内と重なるため、\(Int(ArrivalRule.radiusRange.upperBound))m までにしています。")
        }
    }

    // MARK: - 保存

    private func save() {
        errorMessage = store.saveSchedule(draft.existing, title: resolvedTitle,
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
                                          missionStyle: missionStyle.rawValue,
                                          includesOwnMissions: includesOwnMissions,
                                          arrivalRadius: arrivalRadius,
                                          isShared: isShared,
                                          timeZoneIdentifier: selectedCourse?.timeZoneIdentifier)
        guard errorMessage == nil else { return }
        // 到着判定は端末が見ている値でもある。予定に決めた半径をそのまま効かせる
        deviceArrivalRadius = arrivalRadius
        dismiss()
    }

    /// 半径は隣の駅と圏内が重ならない範囲に収める
    private static func clampRadius(_ value: Double) -> Double {
        min(max(value, ArrivalRule.radiusRange.lowerBound), ArrivalRule.radiusRange.upperBound)
    }

    /// 既定の名前。コースが分かれば「南北線を歩く」、分からなければ「歩く予定」
    private static func defaultTitle(_ courseName: String?) -> String {
        guard let courseName, !courseName.isEmpty else { return "歩く予定" }
        return "\(courseName)を歩く"
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
