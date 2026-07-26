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
    var engine: GameEngine? {
        guard let s = startStation?.orderNo, let g = goalStation?.orderNo, s != g else { return nil }
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
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "お題が空です"
        }
        if effectType.needsValue {
            guard let v = effectValue, (1...9).contains(v) else { return "駅数は1〜9で指定してください" }
        } else if effectValue != nil {
            return "この効果では駅数を指定できません"
        }
        if effectType.needsStation {
            guard effectStation != nil else { return "移動先の駅を選んでください" }
        } else if effectStation != nil {
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

// MARK: - コンテナ

enum AppSchema {
    static let all: [any PersistentModel.Type] = [
        Course.self, Station.self, MissionSet.self, Member.self,
        Mission.self, Turn.self, Visit.self, Photo.self,
        // 送信キュー。記録そのものではないが、圏外で落としても残す必要がある
        PendingChange.self
    ]
}
