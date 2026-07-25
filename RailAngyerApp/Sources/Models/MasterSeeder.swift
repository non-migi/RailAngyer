import Foundation
import SwiftData
import RailAngyerCore

/// 同梱の駅マスタを SwiftData へ投入する（10_アプリ設計.md §8 手順2）。
///
/// 初回起動時に1回だけ走る。既に入っていれば何もしない。
enum MasterSeeder {

    /// コースが1件も無ければ南北線を投入する
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext) throws -> Course {
        if let existing = try context.fetch(FetchDescriptor<Course>()).first {
            return existing
        }
        return try seedNanboku(context)
    }

    static func seedNanboku(_ context: ModelContext) throws -> Course {
        let ref = try StationMaster.nanboku()
        let course = Course(name: ref.name, lineColorHex: ref.lineColorHex)
        context.insert(course)

        for s in ref.sortedStations {
            let station = Station(name: s.name,
                                  orderNo: s.orderNo,
                                  latitude: s.latitude,
                                  longitude: s.longitude)
            station.course = course
            context.insert(station)
        }
        try context.save()
        return course
    }

    /// フェーズ1用のルームを1件だけ用意する。
    /// 共有機能が無いため、メンバーは自分1人・招待コードなし（10_アプリ設計.md AD-02）。
    @discardableResult
    static func seedLocalRoomIfNeeded(_ context: ModelContext,
                                      course: Course,
                                      displayName: String = "じぶん") throws -> MissionSet {
        if let existing = try context.fetch(FetchDescriptor<MissionSet>()).first {
            return existing
        }
        let sorted = course.stations.sorted { $0.orderNo < $1.orderNo }
        guard let first = sorted.first, let last = sorted.last else {
            throw SeedError.emptyCourse
        }

        let room = MissionSet(name: "\(course.name) ローカル", diceMax: 6)
        room.course = course
        room.startStation = first
        room.goalStation = last
        context.insert(room)

        let me = Member(displayName: displayName, isMe: true)
        me.missionSet = room
        context.insert(me)

        try context.save()
        return room
    }

    /// フェーズ1用の仮ミッション。
    /// 本来はメンバーが自分で書くもの（SC-12）だが、フェーズ1では固定データでよい
    /// （04_ロードマップ.md「作らないもの」）。効果の動作確認を兼ねる。
    @discardableResult
    static func seedSampleMissionsIfNeeded(_ context: ModelContext,
                                           room: MissionSet) throws -> [Mission] {
        guard room.missions.isEmpty else { return room.missions }
        guard let me = room.members.first(where: { $0.isMe }) ?? room.members.first else { return [] }

        let byOrder = Dictionary(uniqueKeysWithValues: (room.course?.stations ?? []).map { ($0.orderNo, $0) })

        // (駅番号, お題, 効果, 駅数, ジャンプ先)
        let seeds: [(Int, String, EffectType, Int?, Int?)] = [
            (2,  "駅の看板を入れて記念撮影する", .none, nil, nil),
            (3,  "商店街で一番安い自販機を見つける", .none, nil, nil),
            (4,  "すれ違った犬の数を報告する", .rollAgain, nil, nil),
            (6,  "地上に出て、方角を指差しで当てる", .back, 1, nil),
            (7,  "時計台の方角を全員で指差す。割れたら", .back, 2, nil),
            (8,  "ラーメンを食べて元気になる", .forward, 2, nil),
            (9,  "ベンチで5分休憩する", .rollAgain, nil, nil),
            (11, "橋の上から川を眺める", .none, nil, nil),
            (12, "この区間で一番よかった駅を全員で決める", .jump, nil, 6),
            (14, "自販機で当たりを狙う", .none, nil, nil),
            (15, "ゴールまでの意気込みを一言ずつ", .forward, 1, nil)
        ]

        var created: [Mission] = []
        for (order, content, effect, value, jump) in seeds {
            guard let station = byOrder[order] else { continue }
            let mission = Mission(content: content, effectType: effect, effectValue: value)
            mission.missionSet = room
            mission.member = me
            mission.station = station
            if let jump { mission.effectStation = byOrder[jump] }
            guard mission.validationError == nil else { continue }
            context.insert(mission)
            created.append(mission)
        }
        try context.save()
        return created
    }

    enum SeedError: Error { case emptyCourse }
}
