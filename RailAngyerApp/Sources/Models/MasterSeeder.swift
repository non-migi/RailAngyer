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

    enum SeedError: Error { case emptyCourse }
}
