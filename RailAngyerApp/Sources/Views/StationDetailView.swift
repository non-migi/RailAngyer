import SwiftUI
import RailAngyerCore

/// SC-18 駅詳細。1駅ぶんの記録。
///
/// 戻る効果があると同じ駅を複数回訪れるため、**訪問ごとに分けて並べる**。
/// 写真も訪問ごとに紐づく（ver.2 で駅の一意制約を外した設計に対応）。
struct StationDetailView: View {
    @Bindable var store: GameSessionStore
    let order: Int
    @Environment(\.dismiss) private var dismiss

    private var visits: [Visit] { store.visits(at: order) }
    private var arrivingLegs: [WalkTiming.Leg] { store.legs(arrivingAt: order) }
    /// この駅に書かれているお題。**まだ訪れていなくても見せる**
    private var missions: [Mission] { store.missions(at: order) }

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty && missions.isEmpty {
                    ContentUnavailableView("まだ訪れていません",
                                           systemImage: "figure.walk",
                                           description: Text("サイコロを振って歩くと記録が残ります"))
                } else {
                    List {
                        // **着く前に「この駅で何をするか」が分かるようにする。**
                        // 地図から駅を押したとき、知りたいのはまずそこ
                        if !missions.isEmpty {
                            Section {
                                ForEach(missions) { missionRow($0) }
                            } header: {
                                Text("この駅のお題　\(missions.count)個")
                            } footer: {
                                Text(visits.isEmpty
                                     ? "着地すると、この中から1つ引かれます。"
                                     : "着地したときに1つ引かれます。")
                            }
                        }

                        ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                            Section {
                                visitRow(visit)
                            } header: {
                                Text(visits.count > 1 ? "\(index + 1) 回目の訪問" : "訪問")
                            }
                        }

                        if visits.isEmpty {
                            Section {
                                Text("まだこの駅には来ていません。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(store.stationName(order))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func missionRow(_ mission: Mission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mission.content).font(.subheadline)
            Text(mission.member?.displayName.nilIfEmpty.map { "\($0)のお題" } ?? "だれかのお題")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func visitRow(_ visit: Visit) -> some View {
        LabeledContent("到着", value: visit.arrivedAt.formatted(date: .abbreviated, time: .shortened))

        LabeledContent("経緯", value: kindText(visit))

        if let leg = arrivingLegs.first(where: { $0.id == visit.id }) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DurationText.text(leg.seconds))
                        .monospacedDigit()
                    if let pace = leg.pace.text {
                        Text(pace)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PacePalette.color(
                                minutesPerKilometer: leg.pace.minutesPerKilometer))
                    }
                }
            } label: {
                Label("\(leg.fromName)から", systemImage: "figure.walk")
            }

            if leg.isEffectMove {
                Text("ミッション効果による移動")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // ミッションは着地したときだけ
        if visit.visitKind == .landing, let turn = visit.turn {
            if let mission = turn.selectedMission {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mission.content).font(.subheadline)
                    HStack(spacing: 8) {
                        Text(mission.member?.displayName ?? "だれか")
                            .font(.caption).foregroundStyle(.secondary)
                        // 判定前のお題は「未達成」ではなく「進行中」
                        let outcome = MissionOutcome(turn)
                        Text(outcome.label)
                            .font(.caption)
                            .foregroundStyle(JourneySummaryView.color(of: outcome))
                    }
                }
            } else {
                Text("この駅にミッションはありませんでした")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if !visit.photos.isEmpty {
            let names = visit.photos.sorted { $0.takenAt < $1.takenAt }.map(\.localFileName)
            PhotoStrip(fileNames: names)
        }
    }

    private func kindText(_ visit: Visit) -> String {
        switch visit.visitKind {
        case .start: "スタート地点"
        case .passing: "通り道"
        case .landing:
            if let dice = visit.turn?.diceValue { "サイコロ \(dice) で着地" } else { "着地" }
        case .effectPassing: "ミッションの効果で移動中に通過"
        case .effectArrival: "ミッションの効果で移動した先"
        }
    }
}
