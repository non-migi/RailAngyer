import SwiftUI

/// 旅を始めるときに、立ててある予定から選ぶ（SC-23）。
///
/// **予定にはもうルールが書いてある。** コース・区間・サイコロを決めたのが予定なのだから、
/// 始めるたびに設定画面をたどり直すのは、同じことを二度決めていることになる。
/// 選べば、そのルールをそのまま今回の旅に移して始められる。
struct StartFromScheduleView: View {

    @Bindable var store: GameSessionStore
    /// ルールを決め終えて、盤面へ進むとき
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.startableSchedules) { schedule in
                        Button {
                            choose(schedule)
                        } label: {
                            row(schedule)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("これからの予定")
                } footer: {
                    Text("選ぶと、その予定のコース・区間・サイコロで始めます。予定に書いたお題もそのまま使えます。")
                }

                Section {
                    Button {
                        dismiss()
                        start()
                    } label: {
                        Label("いまの設定のまま始める", systemImage: "figure.walk.motion")
                    }
                } footer: {
                    Text(currentRuleText)
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("どの予定で歩きますか")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
        }
        // 時計は日本時間のまま（場所の属性）。言葉はアプリの言語設定に任せる
        .environment(\.timeZone, .japanStandard)
    }

    private func row(_ schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(schedule.title).font(.headline).foregroundStyle(.primary)
            Text(ScheduleShare.dateText(schedule.startAt, timeZone: schedule.timeZone))
                .font(.subheadline).foregroundStyle(.secondary)
            if !schedule.courseName.isEmpty {
                Label(ruleText(schedule), systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(Theme.line)
            }
            if let place = schedule.meetPlace {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func ruleText(_ schedule: Schedule) -> String {
        let course = store.courses.first { $0.name == schedule.courseName }
        let start = course?.stations.first { $0.orderNo == schedule.startOrder }?.name ?? "—"
        if schedule.isLap {
            return appLocalized("\(schedule.courseName)　\(start) から一周　サイコロ1〜\(schedule.diceMax)")
        }
        let goal = course?.stations.first { $0.orderNo == schedule.goalOrder }?.name ?? "—"
        return appLocalized("\(schedule.courseName)　\(start) → \(goal)　サイコロ1〜\(schedule.diceMax)")
    }

    private var currentRuleText: String {
        guard let room = store.room, let course = room.course else { return "" }
        let start = room.startStation?.name ?? "—"
        let goal = room.goalStation?.name ?? "—"
        return appLocalized("いまの設定：\(course.name)　\(start) → \(goal)　サイコロ1〜\(room.diceMax)")
    }

    private func choose(_ schedule: Schedule) {
        if let error = store.applySchedule(schedule) {
            errorMessage = error
            return
        }
        dismiss()
        start()
    }
}
