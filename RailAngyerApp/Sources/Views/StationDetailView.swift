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

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView("まだ訪れていません",
                                           systemImage: "figure.walk",
                                           description: Text("サイコロを振って歩くと記録が残ります"))
                } else {
                    List {
                        ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                            Section {
                                visitRow(visit)
                            } header: {
                                Text(visits.count > 1 ? "\(index + 1) 回目の訪問" : "訪問")
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
                        Text(turn.missionDone ? "達成" : "未達成")
                            .font(.caption)
                            .foregroundStyle(turn.missionDone ? Theme.line : .secondary)
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
