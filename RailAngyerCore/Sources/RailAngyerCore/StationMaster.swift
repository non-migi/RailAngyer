import Foundation

/// 駅マスタの1件。SwiftData のモデルではなく、同梱JSONを読むための値型。
public struct StationRef: Codable, Sendable, Hashable, Identifiable {
    /// 路線の端からの通し番号（始点=1）。位置計算はすべてこの値で行う
    public let orderNo: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public var id: Int { orderNo }

    public init(orderNo: Int, name: String, latitude: Double, longitude: Double) {
        self.orderNo = orderNo
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// コースの定義。
public struct CourseRef: Codable, Sendable {
    public let name: String
    public let lineColorHex: String
    public let stations: [StationRef]

    /// 進む向きに関係なく、OrderNo 昇順で並んだ駅
    public var sortedStations: [StationRef] { stations.sorted { $0.orderNo < $1.orderNo } }

    public func station(orderNo: Int) -> StationRef? {
        stations.first { $0.orderNo == orderNo }
    }

    /// 区間に含まれる駅を、進む向きに並べて返す
    public func stations(in engine: GameEngine) -> [StationRef] {
        engine.orderedRange.compactMap { station(orderNo: $0) }
    }
}

/// アプリに同梱したマスタの読み込み。
///
/// 座標は概値のため、現地で実測して更新する必要がある（03_Azure構成と料金.md E-02 / T-03）。
public enum StationMaster {

    public enum LoadError: Error, CustomStringConvertible {
        case resourceNotFound(String)
        public var description: String {
            switch self {
            case .resourceNotFound(let name): "マスタが見つかりません: \(name).json"
            }
        }
    }

    /// 札幌市営地下鉄 南北線（麻生 → 真駒内、16駅）
    public static func nanboku() throws -> CourseRef {
        try load(resource: "nanboku")
    }

    /// 札幌市営地下鉄 東西線（宮の沢 → 新さっぽろ、19駅）
    public static func tozai() throws -> CourseRef {
        try load(resource: "tozai")
    }

    /// 札幌市営地下鉄 東豊線（栄町 → 福住、14駅）
    public static func toho() throws -> CourseRef {
        try load(resource: "toho")
    }

    /// JR山手線（東京 → 有楽町、30駅）。
    ///
    /// **環状線だが、直線として並べてある。** `GameEngine` は始点と終点のある区間を
    /// 前提にしており、一周して戻る動きは扱えない。
    /// 東京から順に並べた30駅を通しで歩けば、最後の1区間（有楽町→東京）を残して
    /// ほぼ一周ぶんになる。環状としてきちんと扱うにはルール計算の作り直しが要る。
    public static func yamanote() throws -> CourseRef {
        try load(resource: "yamanote")
    }

    /// 同梱しているコースすべて
    public static func all() throws -> [CourseRef] {
        [try nanboku(), try tozai(), try toho(), try yamanote()]
    }

    static func load(resource: String) throws -> CourseRef {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            throw LoadError.resourceNotFound(resource)
        }
        return try JSONDecoder().decode(CourseRef.self, from: Data(contentsOf: url))
    }
}
