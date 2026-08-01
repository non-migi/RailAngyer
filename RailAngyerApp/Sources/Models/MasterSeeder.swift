import Foundation
import SwiftData
import RailAngyerCore

/// 同梱の駅マスタを SwiftData へ投入する（10_アプリ設計.md §8 手順2）。
///
/// 初回起動時に投入し、同梱マスタの改訂時は既存座標も同期する。
enum MasterSeeder {

    /// 同梱しているコースをすべて投入し、最初のもの（南北線）を返す。
    ///
    /// 座標は国土交通省「国土数値情報 鉄道データ（N02-22 / JGD2011）」に合わせる。
    /// 旧版の概略座標が端末に残っていても、アプリ更新時に正しい位置へ直す。
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext) throws -> Course {
        let existing = try context.fetch(FetchDescriptor<Course>())
        var courses = existing

        for ref in try StationMaster.all() {
            if let course = existing.first(where: { $0.name == ref.name }) {
                course.lineColorHex = ref.lineColorHex
                // 国と都道府県は後から足した項目。すでに入っているコースにも書き足す
                course.countryName = ref.country
                course.countryCode = ref.countryCode
                course.regionNames = ref.regions
                for source in ref.sortedStations {
                    guard let station = course.stations.first(where: {
                        $0.orderNo == source.orderNo && $0.name == source.name
                    }) else { continue }
                    station.latitude = source.latitude
                    station.longitude = source.longitude
                }
            } else {
                courses.append(try seed(ref, into: context))
            }
        }

        try context.save()

        guard let first = courses.first(where: { $0.name == "南北線" }) ?? courses.first else {
            throw SeedError.emptyCourse
        }
        return first
    }

    /// 南北線だけを投入する（既存の呼び出し向け）
    @discardableResult
    static func seedNanboku(_ context: ModelContext) throws -> Course {
        try seed(try StationMaster.nanboku(), into: context)
    }

    private static func seed(_ ref: CourseRef, into context: ModelContext) throws -> Course {
        let course = Course(name: ref.name, lineColorHex: ref.lineColorHex)
        course.countryName = ref.country
        course.countryCode = ref.countryCode
        course.regionNames = ref.regions
        course.isLoop = ref.isLoop
        course.arrivalRadius = ref.arrivalRadius
        course.forwardDirectionName = ref.directionName(forward: true)
        course.backwardDirectionName = ref.directionName(forward: false)
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

    /// 旧ビルドが自動投入したお題だけを取り除く。ユーザーが書いたお題は残す。
    static func removeBundledSampleMissions(_ context: ModelContext,
                                            room: MissionSet) throws {
        let bundled: Set<String> = [
            "駅の看板を入れて記念撮影する",
            "商店街で一番安い自販機を見つける",
            "すれ違った犬の数を報告する",
            "地上に出て、方角を指差しで当てる",
            "時計台の方角を全員で指差す。割れたら",
            "ラーメンを食べて元気になる",
            "ベンチで5分休憩する",
            "橋の上から川を眺める",
            "この区間で一番よかった駅を全員で決める",
            "自販機で当たりを狙う",
            "ゴールまでの意気込みを一言ずつ"
        ]
        let samples = room.missions.filter {
            bundled.contains($0.content) && $0.syncStateRaw == SyncState.localOnly.rawValue
        }
        var changed = !samples.isEmpty
        for mission in samples { context.delete(mission) }
        for mission in room.missions where !samples.contains(where: { $0.id == mission.id }) {
            if mission.effectType != .none || mission.effectValue != nil || mission.effectStation != nil {
                changed = true
            }
            mission.effectType = .none
            mission.effectValue = nil
            mission.effectStation = nil
        }
        guard changed else { return }
        try context.save()
    }

    enum SeedError: Error { case emptyCourse }
}
