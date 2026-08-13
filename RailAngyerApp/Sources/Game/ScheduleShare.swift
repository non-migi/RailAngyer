import Foundation
import RailAngyerCore

/// 予定を、アプリの外へ持ち出せる文にする。
///
/// **相手がこのアプリを入れていなくても伝わる**ことを第一にする。
/// 招待コードや内部のIDは載せない（誘う相手と、ルームに入れる相手は別の話）。
/// 集合場所は地図のリンクにして、当日その場へ迷わず来られるようにする。
enum ScheduleShare {

    /// 共有する本文。
    ///
    /// - Parameter room: 誘う相手をルームへ入れるための招待元。
    ///   渡すと**アプリを開いて参加できるリンク**が付く
    static func text(for schedule: Schedule, course: Course?,
                     room: MissionSet? = nil, now: Date = Date()) -> String {
        var lines: [String] = [appLocalized("【レイルアンギャー】\(schedule.title)")]

        lines.append("🗓 \(dateText(schedule.startAt, timeZone: schedule.timeZone))")
        if let place = schedule.meetPlace, !place.isEmpty {
            lines.append(appLocalized("📍 集合　\(place)"))
        }

        if !schedule.courseName.isEmpty {
            lines.append("🚉 \(courseText(schedule, course: course))")
            lines.append(appLocalized("🎲 サイコロ 1〜\(schedule.diceMax)"))
        }

        if let estimate = estimate(schedule, course: course) {
            lines.append(appLocalized("🚶 歩く目安　\(estimate.distanceText)（\(estimate.durationText)）"))
        }

        if let going = attendanceText(schedule) {
            lines.append("👥 \(going)")
        }

        if let missions = missionsText(schedule, course: course, room: room) {
            lines.append("")
            lines.append(missions)
        }

        // **地図ではなくアプリへ誘う。** 見てほしいのは集合場所ではなく、
        // 「入って、お題を書いて、当日いっしょに歩く」ところまで
        if let invite = inviteText(room) {
            lines.append("")
            lines.append(invite)
        } else if let url = mapURL(schedule, course: course) {
            lines.append(url.absoluteString)
        }

        return lines.joined(separator: "\n")
    }

    /// お題の一覧。**「当日までのお楽しみ」のルームでは出さない**。
    /// 共有した先で中身が読めてしまうと、その場で設定を守った意味がなくなる
    static func missionsText(_ schedule: Schedule, course: Course?,
                             room: MissionSet?) -> String? {
        guard let room, room.missionVisibility == .always else { return nil }

        let orders = Set(sectionStations(schedule, course: course).map(\.orderNo))
        let missions = room.missions
            .filter { $0.station?.course?.name == course?.name }
            .filter { orders.isEmpty || orders.contains($0.station?.orderNo ?? -1) }
            .sorted { ($0.station?.orderNo ?? 0) < ($1.station?.orderNo ?? 0) }
        guard !missions.isEmpty else { return nil }

        var lines = [appLocalized("📝 お題　\(missions.count)個")]
        for mission in missions {
            let station = mission.station?.name ?? "?"
            let author = mission.member?.displayName.nilIfEmpty
            lines.append("・\(station)　\(mission.content)"
                         + (author.map { "（\($0)）" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }

    /// アプリを開いてルームへ入るための案内。
    /// **コードも文字で残す**（アプリを入れていない相手にはリンクが効かないため）
    static func inviteText(_ room: MissionSet?) -> String? {
        guard let room, let code = room.inviteCode?.nilIfEmpty else { return nil }
        var lines = [appLocalized("🚃 アプリで開くと、そのまま参加できます")]
        if let url = InviteLink.url(inviteCode: code, roomName: room.name) {
            lines.append(url.absoluteString)
        }
        lines.append(appLocalized("（アプリの「みんなで遊ぶ」＞招待コード：\(code) からでも入れます）"))
        return lines.joined(separator: "\n")
    }

    /// 「8月9日(土) 9:00」。海外のコースは**その土地の時計**で書く。
    /// 言葉（月・曜日）はアプリの言語設定に追随させる
    static func dateText(_ date: Date, timeZone: TimeZone = .japanStandard) -> String {
        let style = Date.FormatStyle(locale: AppLanguage.currentLocale,
                                     calendar: .japan(in: timeZone),
                                     timeZone: timeZone)
            .month().day().weekday().hour().minute()
        return date.formatted(style)
    }

    /// 「南北線（北海道）　麻生 → 真駒内　16駅」
    static func courseText(_ schedule: Schedule, course: Course?) -> String {
        var text = schedule.courseName
        if let course, !course.regionNamesForDisplay.isEmpty {
            text += "（\(CourseDirectory.regionText(course))）"
        }
        let stations = sectionStations(schedule, course: course)
        if schedule.isLap, let start = stations.first {
            text += "　" + appLocalized("\(start.name) から一周　\(stations.count)駅")
        } else if let start = stations.first, let goal = stations.last,
                  start.orderNo != goal.orderNo {
            text += "　" + appLocalized("\(start.name) → \(goal.name)　\(stations.count)駅")
        }
        return text
    }

    /// 区間の駅（通し番号の順）
    static func sectionStations(_ schedule: Schedule, course: Course?) -> [Station] {
        guard let course else { return [] }

        // **一周はスタートとゴールが同じ駅。** そのまま範囲にすると1駅しか取れず、
        // 地図も目安も出なくなる（札幌市電の予定で実際に起きた）。一周ならコース全体を通る
        if schedule.isLap { return course.stationsInOrder }

        let range = min(schedule.startOrder, schedule.goalOrder)...max(schedule.startOrder,
                                                                      schedule.goalOrder)
        return course.stationsInOrder.filter { range.contains($0.orderNo) }
    }

    /// 歩く距離と時間の目安。コースが分からなければ出さない
    static func estimate(_ schedule: Schedule, course: Course?) -> WalkEstimate? {
        let stations = sectionStations(schedule, course: course)
        guard stations.count >= 2 else { return nil }
        // 一周では出発した駅へ戻るぶんまで数える
        let points = schedule.isLap ? stations + [stations[0]] : stations
        return WalkEstimator.estimate(points: points)
    }

    /// 「参加 2人・不参加 1人」。誰も答えていなければ出さない
    static func attendanceText(_ schedule: Schedule) -> String? {
        let going = schedule.attendees.filter { $0.status == .going }.count
        let notGoing = schedule.attendees.filter { $0.status == .notGoing }.count
        guard going + notGoing > 0 else { return nil }
        var parts = [appLocalized("参加 \(going)人")]
        if notGoing > 0 { parts.append(appLocalized("不参加 \(notGoing)人")) }
        return parts.joined(separator: "・")
    }

    /// 集合場所の地図（スタート駅の座標）。
    /// アプリを入れていない相手でもブラウザで開ける形にする
    static func mapURL(_ schedule: Schedule, course: Course?) -> URL? {
        guard let start = sectionStations(schedule, course: course).first
                ?? course?.stationsInOrder.first else { return nil }
        let query = schedule.meetPlace?.nilIfEmpty ?? "\(start.name)駅"
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f",
                                                   start.latitude, start.longitude)),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }
}
