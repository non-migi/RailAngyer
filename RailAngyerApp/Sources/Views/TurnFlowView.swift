import SwiftUI
import RailAngyerCore

/// プレイ中の全画面フロー（SC-05〜SC-09、SC-21）。
/// 次にやることを画面下端に1つだけ置く（CM-01 / CM-02）。
///
/// > **全体マップはいつでも見られるようにする。**
/// > 以前はこの画面が盤面を覆い、歩いている間もサイコロを振った直後も
/// > 道のり全体が見えなかった。次の駅しか見えないと、
/// > 「あとどれくらいか」「どこを通ってきたか」が分からない。
/// > 上の「全体マップ」で切り替えられ、右上から盤面へ抜けることもできる。
struct TurnFlowView: View {
    @Bindable var store: GameSessionStore
    let location: LocationService
    /// 盤面へ戻る（この画面を一旦しまう）
    var onMinimize: (() -> Void)?
    @State private var showingCamera = false
    @State private var routes = RouteProvider()
    /// サイコロが止まったか。止まるまで行き先を伏せる
    @State private var diceSettled = false
    /// 「サイコロを止める」を押したか。押すまで転がり続ける
    @State private var diceStopped = false

    /// 押し忘れても旅が止まらないよう、これだけ経ったら自動で止める
    private static let autoStopSeconds = 12.0
    /// 地図を全体で見るか。**選んだら憶えておく**（毎回切り替え直させない）
    @AppStorage("turnShowsWholeCourse") private var showsWholeCourse = false

    var body: some View {
        VStack(spacing: 12) {
            header
            turnTiming
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            action
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingCamera) {
            CameraPicker { store.attachPhoto($0) }
                .ignoresSafeArea()
        }
    }

    /// 地図の出し方と、盤面へ抜ける口。それに休憩と「今日はここまでにする」。
    ///
    /// > **やめる口はこの画面にも要る。** 全画面のあいだはタブバーごと隠れるので、
    /// > ここに無いと「盤面へ → 予定 → いちばん下まで送る」と辿らせることになる。
    /// > 現地で疲れて即やめたい場面に、その道のりを歩かせない。
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("地図", selection: $showsWholeCourse) {
                    Text("次の駅").tag(false)
                    Text("全体マップ").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer(minLength: 0)

                if let onMinimize {
                    Button(action: onMinimize) {
                        Label("盤面へ", systemImage: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("minimizeTurn")
                }
            }

            JourneyPauseBar(store: store, isCompact: true)
        }
    }

    /// 今回のターンの時間とペース。進行中は1秒ごとに「いままで」を更新する。
    @ViewBuilder
    private var turnTiming: some View {
        if let turn = store.activeTurn {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let timing = WalkTiming.breakdown(of: turn, now: context.date)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("今回の記録").font(.caption.weight(.semibold))
                        Spacer()
                        Label(DurationText.clock(timing.totalSeconds), systemImage: "clock")
                    }
                    HStack(spacing: 12) {
                        Label("移動 \(DurationText.clock(timing.walkingSeconds))",
                              systemImage: "figure.walk")
                        if let pace = timing.pace.text {
                            Label(pace, systemImage: "gauge.with.dots.needle.50percent")
                                .foregroundStyle(PacePalette.color(
                                    minutesPerKilometer: timing.pace.minutesPerKilometer))
                        } else {
                            Text("ペースは駅に着くと表示")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - 本文

    @ViewBuilder
    private var content: some View {
        if store.showingAnnouncement, let turn = store.activeTurn {
            announcement(turn)
        } else {
            switch store.phase {
            case .walking(let next, let remaining):
                walking(next: next, remaining: remaining)
            case .arrivedPassing(let station):
                arrivedPassing(station)
            case .landed(let station):
                landed(station)
            case .mission(let station):
                mission(at: station)
            case .effectWalking(let next, let destination):
                effectWalking(next: next, destination: destination)
            default:
                EmptyView()
            }
        }
    }

    /// SC-06 着地駅の告知。「途中の駅も歩いて訪れる」ことを必ず伝える
    private func announcement(_ turn: Turn) -> some View {
        // 進行の計算は store が持つ（一周では番号ではなく「位置」で数える必要がある）
        let landing = store.landingPosition(of: turn)
        let from = turn.fromPosition ?? turn.fromStation?.orderNo ?? store.currentOrder
        let passing = store.passingPositions(of: turn)

        return VStack(alignment: .leading, spacing: 20) {
            Text("\(store.stationName(from)) から").foregroundStyle(.secondary)

            DiceRollView(value: turn.diceValue, isRolling: !diceStopped) {
                withAnimation(.easeOut(duration: 0.35)) { diceSettled = true }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .id(turn.id)   // ターンが変わったら振り直す

            if !diceStopped {
                Text("転がっています。下のボタンで止めてください")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if diceSettled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(turn.diceValue) 駅 進む").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(store.stationName(landing)) まで")
                        .font(.largeTitle.weight(.bold))
                    if passing.isEmpty {
                        Text("となりの駅です")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("途中の \(passing.map(store.stationName).joined(separator: "・")) も1駅ずつ歩いて訪れます")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if store.engine?.isCleared(landing) == true {
                        Text("この区間の終点です。到達するとクリアになります")
                            .font(.footnote).foregroundStyle(Theme.line)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                // **振った直後こそ道のり全体を見たい。** どこまで進むのかが分かる
                courseMap(at: landing)
                    .transition(.opacity)
            }

            // 出発する駅でも写真を撮れる。**旅の1駅目（スタート駅）もここに含まれる**（R-19）
            if store.currentVisit != nil { photoSection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: turn.id) {
            diceSettled = false
            diceStopped = false
            try? await Task.sleep(for: .seconds(Self.autoStopSeconds))
            guard !Task.isCancelled else { return }
            diceStopped = true          // 押し忘れても止まる
        }
    }

    /// SC-07 ナビ
    private func walking(next: Int, remaining: Int) -> some View {
        let total = store.activeTurn?.diceValue ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text("次の駅へ　\(total - remaining + 1) / \(total)")
                .font(.footnote).foregroundStyle(.secondary)
            Text(store.stationName(next))
                .font(.title.weight(.bold))
            locationStatus
            map
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 地図。**全体マップを選んでいればそちらを出す**
    @ViewBuilder
    private var map: some View {
        if showsWholeCourse {
            wholeCourseMap
        } else {
            nextStationMap
        }
    }

    /// 道のり全体。歩いた跡・通った駅・お題のある駅がまとめて見える
    @ViewBuilder
    private var wholeCourseMap: some View {
        if store.stationsInOrder.count >= 2 {
            JourneyTrackMapView(store: store)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity)
        } else {
            nextStationMap
        }
    }

    /// 次の駅までの地図と、純正マップへの受け渡し。
    /// 経路案内は自前で作らず、マップアプリに任せる
    @ViewBuilder
    private var nextStationMap: some View {
        if let target = location.target {
            StationMapView(target: target,
                           userLocation: location.lastLocation,
                           radius: location.rule.radius,
                           route: routes.route)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity)
                .task(id: target.orderNo) {
                    await routes.ensureRoute(from: location.lastLocation, to: target)
                }
                .onChange(of: location.lastLocation) {
                    Task { await routes.ensureRoute(from: location.lastLocation, to: target) }
                }

            HStack {
                if let instruction = routes.firstInstruction {
                    Label(instruction, systemImage: "arrow.turn.up.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    target.openInMaps()
                } label: {
                    Label("マップで開く", systemImage: "map").font(.subheadline)
                }
            }
        }
    }

    /// 測位の状態。判定の基準を隠さずに見せる
    @ViewBuilder
    private var locationStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !location.isAuthorized {
                Label("位置情報が使えません。下のボタンで到着を記録してください",
                      systemImage: "location.slash")
                    .font(.footnote).foregroundStyle(Theme.mission)
            } else if let routeDistance = routes.distanceText {
                // 経路が取れていれば、直線ではなく実際に歩く距離を出す
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routeDistance).font(.title3.monospacedDigit().weight(.semibold))
                    if let duration = routes.durationText {
                        Text(duration).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else if let distance = location.distanceToTarget {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distance >= 1000
                         ? appLocalized("直線 約 \(String(format: "%.1f", distance / 1000)) km")
                         : appLocalized("直線 約 \(Int(distance.rounded())) m"))
                        .font(.title3.monospacedDigit().weight(.semibold))
                    if routes.isLoading {
                        ProgressView().controlSize(.small)
                    } else if routes.didFail {
                        Text("経路を取得できません")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("現在地を取得しています…", systemImage: "location")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Label("半径 \(Int(location.rule.radius))m に入ると到着になります",
                  systemImage: "location.circle")
                .font(.footnote).foregroundStyle(.secondary)

            if location.accuracyIsPoor {
                Label("電波が悪いようです。地下では判定できないことがあります",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.mission)
            }
        }
    }

    /// SC-08 通り道の駅に到着。ミッションは引かないが、写真は撮れる
    private func arrivedPassing(_ station: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(store.stationName(station)) に到着")
                .font(.largeTitle.weight(.bold))
            Text("通り道の駅です。ミッションはありません")
                .font(.subheadline).foregroundStyle(.secondary)
            photoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// SC-08 着地。ミッションを引く前
    private func landed(_ station: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(store.stationName(station)) に到着")
                .font(.largeTitle.weight(.bold))
            let count = store.missionCandidates(at: station).count
            Text(count > 0
                 ? "この駅のミッション \(count) 個から1つ引きます"
                 : "この駅にミッションはありません")
                .font(.subheadline)
                .foregroundStyle(count > 0 ? Theme.mission : .secondary)
            // 引く前に、みんなでやるのか自分でやるのかを伝える
            if count > 0, let style = store.room?.missionStyle {
                Text(style.notice)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            photoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 撮影と、この訪問で撮った写真の一覧（F-05）。
    /// 写真は任意なので、主ボタンにはせず控えめに置く（R-19）
    @ViewBuilder
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingCamera = true
            } label: {
                Label(CameraPicker.isCameraAvailable ? "写真を撮る" : "写真を選ぶ",
                      systemImage: "camera")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            PhotoStrip(fileNames: store.currentVisit?.photos
                .sorted { $0.takenAt > $1.takenAt }
                .map(\.localFileName) ?? [])
        }
        .padding(.top, 4)
    }

    /// SC-09 ミッションの実行
    private func mission(at station: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.stationName(station)).font(.headline)
            if let m = store.activeTurn?.selectedMission {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(m.member?.displayName ?? "だれか") が書いた")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(m.content).font(.title2.weight(.semibold))
                    if let effect = effectText(m) {
                        Label(effect, systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mission)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                // **どちらの遊び方なのかを必ず伝える。**
                // 「自分ひとりでやるのか、みんなでやるのか」が分からないまま
                // 駅に着くと、その場で相談から始めることになる
                if let style = store.room?.missionStyle {
                    Label(style.notice, systemImage: style == .team ? "person.3" : "person")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.mission)
                }

                Text("すぐに決められないお題は「あとで」。歩きながら続けられます。達成したかは、旅の画面の「旅のお題」から後で付けられます。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("ミッションはありません").foregroundStyle(.secondary)
            }
            courseMap(at: station)
            photoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// いま立っている駅が、選んだコースのどこなのかを出す。
    /// お題をやっている最中は次の駅へ向かう地図が消えるため、
    /// **道のり全体の中の現在地**が分かるようにしておく
    @ViewBuilder
    private func courseMap(at station: Int) -> some View {
        let stations = store.stationsInOrder
        if stations.count >= 2 {
            if showsWholeCourse {
                // 全体マップを選んでいるあいだは、着地・お題の場面でも全体を出す
                JourneyTrackMapView(store: store)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                CourseSectionMapView(stations: stations,
                                     isLoop: store.room?.isLap == true,
                                     highlightedOrder: station)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// SC-21 効果による移動
    private func effectWalking(next: Int, destination: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let m = store.activeTurn?.selectedMission, let text = effectText(m) {
                Text(m.content).font(.subheadline).foregroundStyle(.secondary)
                Text(text).font(.title3.weight(.semibold)).foregroundStyle(Theme.mission)
            }
            Divider()
            Text("次の駅へ").font(.footnote).foregroundStyle(.secondary)
            Text(store.stationName(next)).font(.title.weight(.bold))
            Text("\(store.stationName(destination)) まで歩きます。ここではミッションを引きません")
                .font(.footnote).foregroundStyle(.secondary)
            locationStatus
            map
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 主操作（常に1つ）

    @ViewBuilder
    private var action: some View {
        if store.showingAnnouncement {
            if !diceStopped {
                // 出目はもう決まっている。**止めるのは演出だけ**なので、いつ押してもよい
                primary("サイコロを止める") {
                    withAnimation(.easeOut(duration: 0.2)) { diceStopped = true }
                }
            } else {
                // 収まりきるまでは押させない
                primary("向かう") { store.showingAnnouncement = false }
                    .disabled(!diceSettled)
                    .opacity(diceSettled ? 1 : 0.4)
            }
        } else {
            switch store.phase {
            case .walking(let next, _):
                arrivalButton(next)
            case .arrivedPassing:
                primary("次の駅へ") { store.continueWalking() }
            case .landed(let station):
                primary(store.missionCandidates(at: station).isEmpty
                        ? "次へ" : "ミッションを引く") { store.drawMission() }
            case .mission:
                VStack(spacing: 8) {
                    primary("達成した") { store.finishMission(done: true) }
                    HStack(spacing: 24) {
                        Button("できなかった") { store.finishMission(done: false) }
                        if store.activeTurn?.selectedMission != nil {
                            // 歩きながら続けられるお題のための逃げ道。
                            // 判定は旅の画面の「旅のお題」から後で付けられる
                            Button("あとで") { store.deferMission() }
                        }
                    }
                    .font(.subheadline)
                }
            case .effectWalking(let next, _):
                arrivalButton(next)
            default:
                EmptyView()
            }
        }
    }

    /// 到着の記録。半径に入れば自動で進むが、手動でも押せるようにしておく（E-01）。
    /// 地下駅では手動が主要な手段になる想定。
    private func arrivalButton(_ next: Int) -> some View {
        primary("\(store.stationName(next)) に到着した") {
            store.arriveAtNextStop(expected: next)
        }
    }

    /// 局面ごとに文字が変わる、この画面の主操作。
    ///
    /// **識別子は変えない。** 文字は9言語で変わるので、
    /// 言語ごとのスクリーンショットを撮るときはこれを頼りに進める
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityIdentifier("primaryAction")
        .buttonStyle(.borderedProminent)
        .tint(Theme.line)
    }

    private func effectText(_ m: Mission) -> String? {
        switch m.effectType {
        case .none: nil
        case .forward: appLocalized("終わったら \(m.effectValue ?? 0) 駅 進む")
        case .back: appLocalized("終わったら \(m.effectValue ?? 0) 駅 戻る")
        case .rollAgain: appLocalized("終わったら もう一度サイコロを振る")
        case .jump: appLocalized("終わったら \(m.effectStation?.name ?? "?") へ移動する")
        }
    }
}

/// サイコロの目をCSSのピップ風に描く
struct DiceFace: View {
    let value: Int

    var body: some View {
        if (1...6).contains(value) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            Circle()
                                .fill(pips.contains([row, col]) ? Theme.ink : .clear)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink.opacity(0.4), lineWidth: 2))
        } else {
            Text("\(value)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .frame(width: 88, height: 88)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink.opacity(0.4), lineWidth: 2))
        }
    }

    /// 目ごとの点の位置（行, 列）
    private var pips: [[Int]] {
        switch value {
        case 1: [[1, 1]]
        case 2: [[0, 0], [2, 2]]
        case 3: [[0, 0], [1, 1], [2, 2]]
        case 4: [[0, 0], [0, 2], [2, 0], [2, 2]]
        case 5: [[0, 0], [0, 2], [1, 1], [2, 0], [2, 2]]
        case 6: [[0, 0], [0, 2], [1, 0], [1, 2], [2, 0], [2, 2]]
        default: []
        }
    }
}
