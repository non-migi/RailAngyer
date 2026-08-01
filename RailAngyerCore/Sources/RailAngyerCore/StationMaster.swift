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
    /// 国の名前（表示用）。**いずれ日本の外も扱う**ため、国から先にたどれる形にしてある
    public let country: String
    /// ISO 3166-1 alpha-2。並び順と旗の表示に使う
    public let countryCode: String
    /// 通る行政区画（日本では都道府県）。**またぐ路線は複数持つ**
    public let regions: [String]
    public let stations: [StationRef]
    /// 環状線か。一周して戻ってこられる
    public let isLoop: Bool
    /// 到着とみなす半径（メートル）。駅間が短い路線では既定の150mだと隣と重なる
    public let arrivalRadius: Double?
    /// 一周する向きの呼び名。`forward` は通し番号が増える向き
    public let loopDirectionNames: LoopDirectionNames?

    public struct LoopDirectionNames: Codable, Sendable {
        public let forward: String
        public let backward: String
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        lineColorHex = try c.decode(String.self, forKey: .lineColorHex)
        stations = try c.decode([StationRef].self, forKey: .stations)
        // 国と地方を書いていない定義は日本のものとして読む（既存の5コースはすべて日本）
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? "日本"
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode) ?? "JP"
        regions = try c.decodeIfPresent([String].self, forKey: .regions) ?? []
        // 既存のコース定義には無い項目なので、書いていなければ直線・既定半径として読む
        isLoop = try c.decodeIfPresent(Bool.self, forKey: .isLoop) ?? false
        arrivalRadius = try c.decodeIfPresent(Double.self, forKey: .arrivalRadius)
        loopDirectionNames = try c.decodeIfPresent(LoopDirectionNames.self,
                                                   forKey: .loopDirectionNames)
    }

    /// 一周する向きの呼び名。定義が無ければ当たり障りのない名前にする
    public func directionName(forward: Bool) -> String {
        guard let names = loopDirectionNames else { return forward ? "順まわり" : "逆まわり" }
        return forward ? names.forward : names.backward
    }

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
/// 札幌3路線の座標は国土交通省「国土数値情報 鉄道データ（N02-22）」の
/// 駅区間中央を採用している（測地系 JGD2011）。
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

    /// JR山手線（30駅・環状）。一周できる。
    /// 通し番号が増える向きが**内回り**（東京 → 上野 → 池袋 → 新宿 → 渋谷 → 品川 → 東京）
    public static func yamanote() throws -> CourseRef {
        try load(resource: "yamanote")
    }

    /// 札幌市電（24電停・環状）。
    ///
    /// **電停の間隔が短い**ため、到着判定の半径を路線ごとに持たせている。
    public static func shiden() throws -> CourseRef {
        try load(resource: "shiden")
    }

    /// 阪急京都本線（大阪梅田 → 京都河原町、28駅）。
    ///
    /// 座標は OpenStreetMap の駅ノード（© OpenStreetMap contributors / ODbL）。
    /// 直線距離の合計は約46.8kmで、営業キロ47.7kmとよく合う。
    public static func hankyuKyoto() throws -> CourseRef {
        try load(resource: "hankyu_kyoto")
    }

    /// 同梱しているコースすべて
    public static func all() throws -> [CourseRef] {
        [try nanboku(), try tozai(), try toho(), try yamanote(), try shiden(),
         try hankyuKyoto()]
    }

    static func load(resource: String) throws -> CourseRef {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            throw LoadError.resourceNotFound(resource)
        }
        return try JSONDecoder().decode(CourseRef.self, from: Data(contentsOf: url))
    }
}
