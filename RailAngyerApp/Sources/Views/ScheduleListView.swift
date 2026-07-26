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
    @State private var isLoading = false

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
                        attendancePicker(schedule)
                        attendeeList(schedule)
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
            .sheet(item: $editing) { draft in
                ScheduleDraftView(store: store, draft: draft)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
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
                Text(schedule.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
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
        guard sync.isJoined else { return }
        isLoading = true
        defer { isLoading = false }
        await sync.push()
        await sync.pullSchedules()
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
    @State private var errorMessage: String?

    init(store: GameSessionStore, draft: ScheduleDraft) {
        self.store = store
        self.draft = draft
        _title = State(initialValue: draft.existing?.title ?? "")
        // 既定は次の土曜の朝9時。歩くのはたいてい休日の午前から
        _startAt = State(initialValue: draft.existing?.startAt ?? Self.nextSaturdayMorning())
        _meetPlace = State(initialValue: draft.existing?.meetPlace ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("何をする日か") {
                    TextField("南北線を歩く", text: $title)
                }
                Section("日時") {
                    DatePicker("集合", selection: $startAt)
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
                                                          startAt: startAt, meetPlace: meetPlace)
                        if errorMessage == nil { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private static func nextSaturdayMorning() -> Date {
        let calendar = Calendar.current
        let base = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        return calendar.nextDate(after: base,
                                 matching: DateComponents(hour: 9, weekday: 7),
                                 matchingPolicy: .nextTime) ?? base
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
