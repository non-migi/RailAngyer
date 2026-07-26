import Foundation

/// APIの入口（11_API設計.md §3）。
///
/// <b>ここは通信するだけ</b>。いつ送るか・失敗をどうするかは `SyncService` が決める。
final class ApiClient {

    /// App Service（F1）とサーバーレスDBは寝ていることがある。
    /// 両方の起床を待てる長さにしておく（§1 コールドスタートを前提にする）
    static let coldStartTimeout: TimeInterval = 90

    private let baseURL: URL
    private let session: URLSession
    private let credentials: CredentialStoring

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // サーバーは秒までの DATETIME2(0)。小数の有無どちらでも読めるようにする
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ApiDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                      debugDescription: "日時として読めません: \(text)")
            }
            return date
        }
        return d
    }()

    init(baseURL: URL, credentials: CredentialStoring, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    // MARK: - マスタ

    func courses() async throws -> [CourseResponse] {
        let data = try await sendRaw(.get, "/courses", rawBody: nil, authorized: false)
        return try decode(data)
    }

    // MARK: - 参加

    func createRoom(_ request: CreateRoomRequest) async throws -> JoinedRoomResponse {
        try await send(.post, "/rooms", body: request, authorized: false)
    }

    func joinRoom(inviteCode: String, displayName: String) async throws -> JoinedRoomResponse {
        try await send(.post, "/rooms/join",
                       body: JoinRoomRequest(inviteCode: inviteCode, displayName: displayName),
                       authorized: false)
    }

    /// 起こすためだけの呼び出し。失敗しても構わない
    func wakeUp() async {
        _ = try? await sendRaw(.get, "/health", rawBody: nil, authorized: false)
    }

    // MARK: - 状態

    func room(roomId: UUID) async throws -> RoomResponse {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)", rawBody: nil, authorized: true)
        return try decode(data)
    }

    /// **自分のぶんだけ**返る。他人のお題はサーバーが伏せる
    func missions(roomId: UUID) async throws -> [MissionResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/missions",
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    /// 駅ごとの件数だけ。**内容は返らない**ので、当日の驚きが損なわれない
    func missionSummary(roomId: UUID) async throws -> [MissionSummaryResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/missions/summary",
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    func state(roomId: UUID) async throws -> StateResponse {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/state",
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    // MARK: - 送信（すべて冪等）

    @discardableResult
    func perform(_ change: PendingChange) async throws -> Data {
        try await sendRaw(HTTPMethod(rawValue: change.method) ?? .put,
                          change.path,
                          rawBody: change.payload,
                          authorized: true)
    }

    // MARK: - 実行

    private enum HTTPMethod: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: HTTPMethod, _ path: String, body: Body, authorized: Bool = true
    ) async throws -> Response {
        let data = try await sendRaw(method, path,
                                     rawBody: try encoder.encode(body), authorized: authorized)
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ApiError.malformedResponse(underlying: error)
        }
    }

    private func sendRaw(_ method: HTTPMethod, _ path: String,
                         rawBody: Data?, authorized: Bool) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path),
                                 timeoutInterval: Self.coldStartTimeout)
        request.httpMethod = method.rawValue

        if let rawBody {
            request.httpBody = rawBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = credentials.load()?.token else { throw ApiError.notJoined }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // 圏外・タイムアウト。キューに残して後で送り直す
            throw ApiError.offline(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.malformedResponse(underlying: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError.server(status: http.statusCode,
                                  detail: try? decoder.decode(ApiErrorBody.self, from: data))
        }
        return data
    }
}

// MARK: - エラー

enum ApiError: Error {
    /// 通信そのものが届かなかった。**再送する**
    case offline(underlying: Error)
    /// サーバーが応答したが失敗。再送すべきかは `isRetryable` で判断する
    case server(status: Int, detail: ApiErrorBody?)
    case malformedResponse(underlying: Error?)
    /// まだルームに参加していない
    case notJoined

    /// 後で送り直す価値があるか。
    /// 4xx は何度送っても同じなので捨てる（キューに残すと以降が永久に詰まる）。
    /// ただし 401 は「トークンが無効」で、再参加すれば通るため残す
    var isRetryable: Bool {
        switch self {
        case .offline, .notJoined: return true
        case .malformedResponse: return false
        case .server(let status, _): return status == 401 || status >= 500
        }
    }

    var message: String {
        switch self {
        case .offline: return "通信できませんでした"
        case .notJoined: return "ルームに参加していません"
        case .malformedResponse: return "応答を読み取れませんでした"
        case .server(let status, let detail): return detail?.message ?? "サーバーエラー（\(status)）"
        }
    }
}

struct ApiErrorBody: Decodable {
    let error: String
    let message: String
}

// MARK: - やりとりする型

struct CreateRoomRequest: Codable {
    let courseId: Int
    let name: String
    let startStationId: Int
    let goalStationId: Int
    let diceMax: Int
    let displayName: String
}

struct JoinRoomRequest: Codable {
    let inviteCode: String
    let displayName: String
}

struct JoinedRoomResponse: Codable {
    let roomId: UUID
    let inviteCode: String
    let memberId: UUID
    let token: String

    var credentials: RoomCredentials {
        RoomCredentials(roomId: roomId, memberId: memberId, token: token)
    }
}

struct CourseResponse: Codable {
    let courseId: Int
    let name: String
    let lineColor: String?
    let stations: [StationResponse]
}

struct StationResponse: Codable {
    let stationId: Int
    let name: String
    let orderNo: Int
    let latitude: Double
    let longitude: Double
}

struct RoomResponse: Codable {
    let roomId: UUID
    let name: String
    let courseId: Int
    let startStationId: Int
    let goalStationId: Int
    let diceMax: Int
    let inviteCode: String
    let members: [MemberResponse]
}

struct MemberResponse: Codable {
    let memberId: UUID
    let displayName: String
    let joinedAt: Date
}

struct MissionResponse: Codable {
    let missionId: UUID
    let stationId: Int
    let content: String
    let effectType: Int
    let effectValue: Int?
    let effectStationId: Int?
    let createdByName: String
}

struct MissionSummaryResponse: Codable {
    let stationId: Int
    let count: Int
    let effectCount: Int
    let backEffectCount: Int
}

struct StateResponse: Codable {
    let currentStationId: Int
    let isCleared: Bool
    let activeTurn: ActiveTurnResponse?
    let visits: [VisitResponse]
    let completedTurnCount: Int
}

struct ActiveTurnResponse: Codable {
    let turnId: UUID
    let turnNo: Int
    let diceValue: Int
    let fromStationId: Int
    let landingStationId: Int
    let rolledAt: Date
    let arrivedAt: Date?
    let selectedMissionId: UUID?
    let missionDone: Bool
    let appliedEffectType: Int?
}

struct VisitResponse: Codable {
    let visitId: UUID
    let turnId: UUID?
    let stationId: Int
    let arrivedAt: Date
    let visitKind: Int
}

// MARK: - 補助

extension UUID {
    /// サーバーのルーティングは小文字のUUIDを想定している
    var apiString: String { uuidString.lowercased() }
}

/// サーバーの日時は `DATETIME2(0)` 由来で小数秒が付かないことも、
/// `SYSUTCDATETIME()` 由来で付くこともある。**両方受ける**
enum ApiDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ text: String) -> Date? {
        // サーバーは UTC で返すが、末尾の Z が省かれることがある（DATETIME2 をそのまま出した場合）
        let normalized = text.hasSuffix("Z") || text.contains("+") ? text : text + "Z"
        return withFraction.date(from: normalized) ?? plain.date(from: normalized)
    }

    static func text(_ date: Date) -> String { withFraction.string(from: date) }
}
