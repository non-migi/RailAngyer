import SwiftUI

/// 予定と出欠（SC-21 / フェーズ3）。
///
/// 「いつ・どこに集まるか」と「誰が来るか」だけの画面。
/// **予定を立てた人だけが直せる**が、出欠は各自が自分のぶんを答える。
struct ScheduleListView: View {

    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ScheduleDraft?
    @State private var missionPlan: MissionPlan?
    @State private var isLoading = false
    @State private var loadingMessage = "予定を読み込み中…"

    var body: some View {
        NavigationStack {
            List {
                if store.schedules.isEmpty {
                    Section {
                        Text(sync.isJoined
                             ? "まだ予定がありません。右上の＋から立ててください。"
                             : "予定は参加しているルームで共有されます。設定の「みんなで遊ぶ」から参加してください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.schedules) { schedule in
                    Section {
                        header(schedule)
                        sectionMap(schedule)
                        attendancePicker(schedule)
                        attendeeList(schedule)
                        Button {
                            missionPlan = plan(for: schedule)
                        } label: {
                            Label("この予定のお題を書く", systemImage: "square.and.pencil")
                        }
                        .disabled(plan(for: schedule) == nil)

                        ShareLink(item: ScheduleShare.text(for: schedule,
                                                           course: course(for: schedule),
                                                           room: store.room)) {
                            Label("この予定を共有する", systemImage: "square.and.arrow.up")
                        }

                        if isMine(schedule) {
                            Button("この予定を消す", role: .destructive) {
                                store.deleteSchedule(schedule)
                            }
                        }
                    }
                }
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
            .sheet(item: $missionPlan) { plan in
                MissionEditorView(store: store, sync: sync, plan: plan)
            }
            .overlay {
                if isLoading {
                    ProgressView(loadingMessage)
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, .japanStandard)
        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
    }

    /// 予定の区間を地図と目安で見せる。コースが分からない古い予定には出さない
    @ViewBuilder
    private func sectionMap(_ schedule: Schedule) -> some View {
        let stations = ScheduleShare.sectionStations(schedule, course: course(for: schedule))
        if stations.count >= 2 {
            CourseSectionSummaryView(
                stations: stations,
                isLoop: schedule.isLap,
                caption: schedule.isLap
                    ? "\(schedule.courseName)　\(stations.first?.name ?? "") から一周"
                    : "\(schedule.courseName)　"
                      + "\(stations.first?.name ?? "") → \(stations.last?.name ?? "")")
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
                Text(schedule.startAt.formatted(
                    .dateTime.locale(Locale(identifier: "ja_JP"))
                        .month().day().weekday().hour().minute()))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !schedule.courseName.isEmpty {
                    Label(ruleText(schedule), systemImage: "slider.horizontal.3")
                        .font(.caption).foregroundStyle(Theme.line)
                }
                if let place = schedule.meetPlace {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if schedule.startAt < Date() {
                    Text("終わった予定").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func ruleText(_ schedule: Schedule) -> String {
        let course = store.courses.first { $0.name == schedule.courseName }
        let start = course?.stations.first { $0.orderNo == schedule.startOrder }?.name ?? "—"
        if schedule.isLap {
            return "\(schedule.courseName)　\(start) から一周　サイコロ1〜\(schedule.diceMax)"
        }
        let goal = course?.stations.first { $0.orderNo == schedule.goalOrder }?.name ?? "—"
        return "\(schedule.courseName)　\(start) → \(goal)　サイコロ1〜\(schedule.diceMax)"
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

    private func refresh() async {
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

/// 予定1件の入力
private struct ScheduleDraftView: View {

    @Bindable var store: GameSessionStore
    let draft: ScheduleDraft
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startAt: Date
    @State private var meetPlace: String
    @State private var courseName: String
    @State private var startOrder: Int
    @State private var goalOrder: Int
    @State private var diceMax: Int
    @State private var isLap: Bool
    @State private var loopDirection: Int
    @State private var errorMessage: String?
    @State private var showingCoursePicker = false

    init(store: GameSessionStore, draft: ScheduleDraft) {
        self.store = store
        self.draft = draft
        // **名前を空で始めない。** 空だと保存ボタンが押せず、
        // しかもその入力欄は下の方にあって、開いた画面には映らない。
        // 「立てられない」ように見えるので、そのまま保存できる名前を最初から入れておく
        let initialTitle = draft.existing?.title
            ?? Self.defaultTitle(store.room?.course?.name)
        _title = State(initialValue: initialTitle)
        // 既定は次の土曜の朝9時。歩くのはたいてい休日の午前から
        _startAt = State(initialValue: draft.existing?.startAt ?? Self.nextSaturdayMorning())
        _meetPlace = State(initialValue: draft.existing?.meetPlace ?? "")
        let initialCourse = draft.existing?.courseName.nilIfEmpty ?? store.room?.course?.name ?? ""
        _courseName = State(initialValue: initialCourse)
        _startOrder = State(initialValue: (draft.existing?.startOrder ?? 0) > 0
                            ? draft.existing!.startOrder : store.room?.startStation?.orderNo ?? 1)
        _goalOrder = State(initialValue: (draft.existing?.goalOrder ?? 0) > 0
                           ? draft.existing!.goalOrder : store.room?.goalStation?.orderNo ?? 1)
        _diceMax = State(initialValue: draft.existing?.diceMax ?? store.room?.diceMax ?? 6)
        _isLap = State(initialValue: draft.existing?.isLap ?? false)
        _loopDirection = State(initialValue: draft.existing?.loopDirectionRaw ?? 1)
    }

    private var selectedCourse: Course? { store.courses.first { $0.name == courseName } }
    private var stations: [Station] {
        (selectedCourse?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
    }

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

    var body: some View {
        NavigationStack {
            Form {
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
                                    Text("\(CourseDirectory.regionText(course))"
                                         + "　\(course.stations.count)駅")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("coursePicker")
                    // **環状線は一周できる。** 山手線を東京から出て東京へ戻る形。
                    // 一周のときは「別の駅にしてください」を出してはいけない
                    if selectedCourse?.isLoop == true {
                        Toggle("一周する", isOn: $isLap)
                        if isLap {
                            Picker("まわる向き", selection: $loopDirection) {
                                Text(selectedCourse?.forwardDirectionName ?? "順まわり").tag(1)
                                Text(selectedCourse?.backwardDirectionName ?? "逆まわり").tag(-1)
                            }
                        }
                    }

                    Picker(isLap ? "出発する駅" : "スタート", selection: $startOrder) {
                        ForEach(stations) { Text($0.name).tag($0.orderNo) }
                    }
                    if !isLap {
                        Picker("ゴール", selection: $goalOrder) {
                            ForEach(stations) { Text($0.name).tag($0.orderNo) }
                        }
                    }
                    Stepper("サイコロ　1〜\(diceMax)", value: $diceMax, in: 1...9)
                    if isLap {
                        Text("\(stationName(startOrder)) を出て、"
                             + "\(stationName(startOrder)) へ戻ってきたら終わりです")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if startOrder == goalOrder {
                        Text("スタートとゴールは別の駅にしてください")
                            .font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("1　ルールセット")
                } footer: {
                    Text("歩く場所は国と都道府県からたどって選びます。"
                         + "区間とサイコロの最大出目もここで決めます。")
                }

                // **名前は地図より先に置く。** 地図（170pt）を先に挟んだところ、
                // 名前の入力欄が画面の外へ押し出され、
                // 「保存が押せない理由が見えない」状態になった
                Section {
                    TextField("南北線を歩く", text: $title)
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("名前を入れると保存できます")
                            .font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("2　予定の名前")
                }

                if sectionStations.count >= 2 {
                    Section {
                        CourseSectionSummaryView(stations: sectionStations, isLoop: isLap)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16,
                                                      bottom: 12, trailing: 16))
                    } header: {
                        Text("歩く道のり")
                    } footer: {
                        Text("目安は駅と駅を直線で結び、迂回のぶん（1.3倍）を足して"
                             + "時速5kmで歩いたときの値です。お題や休憩の時間は含みません。")
                    }
                }
                Section("3　集合日時（日本時間）") {
                    DatePicker("集合日", selection: $startAt, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    DatePicker("集合時刻", selection: $startAt, displayedComponents: .hourAndMinute)
                }
                Section {
                    TextField("麻生駅 改札前", text: $meetPlace)
                } header: {
                    Text("集合場所")
                } footer: {
                    Text("空でも構いません。当日の連絡は各自の連絡手段で。")
                }
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
                    Button("保存") {
                        errorMessage = store.saveSchedule(draft.existing, title: title,
                                                          startAt: startAt, meetPlace: meetPlace,
                                                          course: selectedCourse,
                                                          startOrder: startOrder,
                                                          goalOrder: goalOrder,
                                                          diceMax: diceMax,
                                                          isLap: isLap,
                                                          loopDirection: loopDirection)
                        if errorMessage == nil { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (!isLap && startOrder == goalOrder)
                              || selectedCourse == nil)
                }
            }
            .sheet(isPresented: $showingCoursePicker) {
                CoursePickerView(courses: store.courses, selectedName: $courseName)
            }
            .onChange(of: courseName) {
                // 環状でないコースへ変えたら、一周の設定は残さない
                if selectedCourse?.isLoop != true { isLap = false }
                guard let first = stations.first, let last = stations.last else { return }
                startOrder = first.orderNo
                goalOrder = last.orderNo
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, .japanStandard)
        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
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

private extension Calendar {
    static var japanStandard: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 1
        return calendar
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
