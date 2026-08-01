import Foundation
import SwiftData
import RailAngyerCore

// 10_アプリ設計.md §3 のモデル定義。
// サーバー側のテーブルとほぼ1対1にしてある（AD-01）。
// 区分値は Int で保持し、計算プロパティで enum を返す（移行に強い形）。

// MARK: - マスタ

@Model
final class Course {
    var id: UUID = UUID()
    var serverId: Int?
    var name: String = ""
    var lineColorHex: String?
    /// 環状線か。一周して戻ってこられる
    var isLoop: Bool = false
    /// この路線での到着判定の半径（メートル）。駅間が短い路線だけ持つ
    var arrivalRadius: Double?
    /// 一周する向きの呼び名（通し番号が増える向き／減る向き）
    var forwardDirectionName: String?
    var backwardDirectionName: String?

    @Relationship(deleteRule: .cascade, inverse: \Station.course)
    var stations: [Station] = []

    init(name: String, lineColorHex: String? = nil) {
        self.name = name
        self.lineColorHex = lineColorHex
    }
}

@Model
final class Station {
    var id: UUID = UUID()
    var serverId: Int?
    var name: String = ""
    /// 路線の端からの通し番号（始点=1）。位置計算はすべてこの値
    var orderNo: Int = 0
    var latitude: Double = 0
    var longitude: Double = 0
    var course: Course?

    init(name: String, orderNo: Int, latitude: Double, longitude: Double) {
        self.name = name
        self.orderNo = orderNo
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - ルーム

@Model
final class MissionSet {
    var id: UUID = UUID()
    var name: String = ""
    var inviteCode: String?
    /// 最大出目（1〜9）
    var diceMax: Int = 6
    var createdAt: Date = Date()
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    var course: Course?
    var startStation: Station?
    var goalStation: Station?

    @Relationship(deleteRule: .cascade, inverse: \Member.missionSet)
    var members: [Member] = []
    @Relationship(deleteRule: .cascade, inverse: \Mission.missionSet)
    var missions: [Mission] = []
    @Relationship(deleteRule: .cascade, inverse: \Turn.missionSet)
    var turns: [Turn] = []
    @Relationship(deleteRule: .cascade, inverse: \Visit.missionSet)
    var visits: [Visit] = []

    init(name: String, diceMax: Int = 6) {
        self.name = name
        self.diceMax = diceMax
    }

    /// このルームのルール計算器。区間と最大出目から作る
    /// 一周するときにまわる向き。`1` で通し番号が増える向き、`-1` で減る向き
    var loopDirectionRaw: Int = 1

    /// 環状コースを一周する設定か（スタートとゴールが同じ駅）
    var isLap: Bool {
        course?.isLoop == true && startStation != nil && startStation?.orderNo == goalStation?.orderNo
    }

    var engine: GameEngine? {
        guard let s = startStation?.orderNo else { return nil }

        // 一周は「通し番号が1周ぶん伸びた直線」として扱う（GameEngine.lap）
        if isLap, let count = course?.stations.count, count > 1 {
            return GameEngine.lap(from: s, stationCount: count,
                                  forward: loopDirectionRaw >= 0, diceMax: diceMax)
        }

        guard let g = goalStation?.orderNo, s != g else { return nil }
        return GameEngine(startOrder: s, goalOrder: g, diceMax: diceMax)
    }
}

@Model
final class Member {
    var id: UUID = UUID()
    var displayName: String = ""
    var joinedAt: Date = Date()
    /// この端末の持ち主か（フェーズ1では常に1人）
    var isMe: Bool = false
    var missionSet: MissionSet?

    init(displayName: String, isMe: Bool = false) {
        self.displayName = displayName
        self.isMe = isMe
    }
}

@Model
final class Mission {
    var id: UUID = UUID()
    var content: String = ""
    var effectTypeRaw: Int = EffectType.none.rawValue
    /// 進む・戻るのときの駅数
    var effectValue: Int?
    var createdAt: Date = Date()
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    var missionSet: MissionSet?
    var member: Member?
    var station: Station?
    /// 指定駅へ移動の移動先
    var effectStation: Station?

    var effectType: EffectType {
        get { EffectType(rawValue: effectTypeRaw) ?? .none }
        set { effectTypeRaw = newValue.rawValue }
    }

    init(content: String, effectType: EffectType = .none, effectValue: Int? = nil) {
        self.content = content
        self.effectTypeRaw = effectType.rawValue
        self.effectValue = effectValue
    }

    /// サーバーの CHECK 制約（CK-06 / CK-07）に相当する検証。
    /// ローカルには制約がないため、保存前にこれで弾く。
    var validationError: String? {
        Mission.validationError(content: content,
                                effectType: effectType,
                                effectValue: effectValue,
                                hasEffectStation: effectStation != nil)
    }

    /// 値だけでの検証。
    ///
    /// **関係を張る前に呼べるようにしてある。** SwiftData は
    /// 保存済みのオブジェクトに関係を張った時点でコンテキストに入れてしまうため、
    /// 「作ってから弾く」と不正なお題が残ってしまう。
    static func validationError(content: String, effectType: EffectType,
                                effectValue: Int?, hasEffectStation: Bool) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "お題が空です" }
        if trimmed.count > 300 { return "お題は300文字までです" }

        if effectType.needsValue {
            guard let v = effectValue, (1...9).contains(v) else { return "駅数は1〜9で指定してください" }
        } else if effectValue != nil {
            return "この効果では駅数を指定できません"
        }
        if effectType.needsStation {
            guard hasEffectStation else { return "移動先の駅を選んでください" }
        } else if hasEffectStation {
            return "この効果では移動先を指定できません"
        }
        return nil
    }
}

// MARK: - 進行記録

@Model
final class Turn {
    var id: UUID = UUID()
    /// ルーム内の連番（1始まり）。現在位置の判定はこの順で行う
    var turnNo: Int = 0
    var diceValue: Int = 0
    var rolledAt: Date = Date()
    /// 着地駅に着いた時刻。nil なら移動中
    var arrivedAt: Date?
    var missionDone: Bool = false
    var appliedEffectTypeRaw: Int?
    /// nil なら進行中
    var completedAt: Date?
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    // 環状コースを一周するときの「位置」。駅の通し番号は一周すると元に戻ってしまうため、
    // **周回ぶん伸びた番号**を別に持つ。直線のコースでは駅の通し番号と同じ値になる。
    // 古い記録には無いので、無ければ駅の通し番号から読む
    var fromPosition: Int?
    var landingPosition: Int?
    var endPosition: Int?

    var missionSet: MissionSet?
    var fromStation: Station?
    var landingStation: Station?
    /// 効果適用後の終了位置。nil なら進行中
    var endStation: Station?
    var selectedMission: Mission?

    @Relationship(deleteRule: .nullify, inverse: \Visit.turn)
    var visits: [Visit] = []

    init(turnNo: Int, diceValue: Int) {
        self.turnNo = turnNo
        self.diceValue = diceValue
    }

    /// 進行中のターンか（サーバーの UX_Turn_Active に対応する概念）
    var isActive: Bool { endStation == nil }

    var appliedEffectType: EffectType? {
        get { appliedEffectTypeRaw.flatMap(EffectType.init(rawValue:)) }
        set { appliedEffectTypeRaw = newValue?.rawValue }
    }
}

@Model
final class Visit {
    var id: UUID = UUID()
    var arrivedAt: Date = Date()
    var visitKindRaw: Int = VisitKind.passing.rawValue
    /// 一周のときの位置（`Turn.fromPosition` と同じ考え方）
    var position: Int?
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    var missionSet: MissionSet?
    /// 始点の記録のみ nil
    var turn: Turn?
    var station: Station?

    @Relationship(deleteRule: .cascade, inverse: \Photo.visit)
    var photos: [Photo] = []

    init(kind: VisitKind) {
        self.visitKindRaw = kind.rawValue
    }

    var visitKind: VisitKind {
        get { VisitKind(rawValue: visitKindRaw) ?? .passing }
        set { visitKindRaw = newValue.rawValue }
    }
}

@Model
final class Photo {
    var id: UUID = UUID()
    /// Application Support 配下の相対パス
    var localFileName: String = ""
    /// フェーズ2で埋める
    var blobUrl: String?
    var takenAt: Date = Date()
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    var visit: Visit?
    var member: Member?

    init(localFileName: String) {
        self.localFileName = localFileName
    }
}

// MARK: - 予定（フェーズ3）

@Model
final class Schedule {
    var id: UUID = UUID()
    var title: String = ""
    var startAt: Date = Date()
    var meetPlace: String?
    /// 予定時点のルール。ルーム設定を後から変えても、集合予定の内容は変わらない。
    var courseServerId: Int?
    var courseName: String = ""
    var startOrder: Int = 0
    var goalOrder: Int = 0
    var diceMax: Int = 6
    /// 立てた人。この人だけが直せる（サーバー側でも同じ判定をしている）
    var createdById: UUID?
    var syncStateRaw: Int = SyncState.localOnly.rawValue

    var missionSet: MissionSet?

    @Relationship(deleteRule: .cascade, inverse: \Attendance.schedule)
    var attendees: [Attendance] = []

    init(title: String, startAt: Date, meetPlace: String? = nil) {
        self.title = title
        self.startAt = startAt
        self.meetPlace = meetPlace
    }
}

// MARK: - 保存済みの旅

/// 1回の旅を終えた時点のスナップショット。
///
/// 現在進行中の `Turn` / `Visit` とは分けて残すため、何度遊んでも過去の記録を一覧できる。
@Model
final class JourneyArchive {
    var id: UUID = UUID()
    var roomName: String = ""
    var courseName: String = ""
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var elapsedSeconds: Double = 0
    var walkingSeconds: Double = 0
    var meters: Double = 0
    var visitedCount: Int = 0
    var stationCount: Int = 0
    var turnCount: Int = 0
    var photoCount: Int = 0
    var isCleared: Bool = false
    /// 駅名を矢印で連結した表示用文字列。
    var routeSummary: String = ""
    /// Application Support 内のファイル名を改行区切りで保持する。
    var photoFileNamesText: String = ""

    init(roomName: String, courseName: String, startedAt: Date, endedAt: Date) {
        self.roomName = roomName
        self.courseName = courseName
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var photoFileNames: [String] {
        photoFileNamesText.split(separator: "\n").map(String.init)
    }
}

/// 出欠。0=未定 1=参加 2=不参加（サーバーの `ScheduleAttendee.Status` と同じ値）
@Model
final class Attendance {
    /// メンバーIDと予定の組で一意。SwiftDataに複合主キーは無いので、こちらで守る
    var memberId: UUID = UUID()
    var displayName: String = ""
    var statusRaw: Int = AttendanceStatus.undecided.rawValue

    var schedule: Schedule?

    init(memberId: UUID, displayName: String, status: AttendanceStatus = .undecided) {
        self.memberId = memberId
        self.displayName = displayName
        self.statusRaw = status.rawValue
    }

    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .undecided }
        set { statusRaw = newValue.rawValue }
    }
}

enum AttendanceStatus: Int, CaseIterable {
    case undecided = 0
    case going = 1
    case notGoing = 2

    var label: String {
        switch self {
        case .undecided: return "未定"
        case .going:     return "参加"
        case .notGoing:  return "不参加"
        }
    }
}

// MARK: - コンテナ

enum AppSchema {
    static let all: [any PersistentModel.Type] = [
        Course.self, Station.self, MissionSet.self, Member.self,
        Mission.self, Turn.self, Visit.self, Photo.self,
        Schedule.self, Attendance.self, JourneyArchive.self,
        // 送信キュー。記録そのものではないが、圏外で落としても残す必要がある
        PendingChange.self
    ]
}
