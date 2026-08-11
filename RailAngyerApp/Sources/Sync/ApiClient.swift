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

    /// ルームの設定を変える。**お題の見え方はプレイ中でも変えられる**
    /// （区間や最大出目と違い、すでにある記録の整合を壊さないため）
    func updateRoom(roomId: UUID, _ request: UpdateRoomRequest) async throws {
        _ = try await sendRaw(.patch, "/rooms/\(roomId.apiString)",
                              rawBody: try encoder.encode(request), authorized: true)
    }

    /// お題の一覧。**既定では全員ぶん**が返る（お題はみんなに見えるのが既定）。
    /// 当日まで伏せる設定では `includeOthers: false` にして、自分のぶんだけ取る
    func missions(roomId: UUID, includeOthers: Bool = true) async throws -> [MissionResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/missions",
                                     query: [.init(name: "includeOthers", value: String(includeOthers))],
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    /// 駅ごとの準備状況。**既定では中身も返る**。
    /// `includeContent: false` のときは件数だけで、中身は端末に降りてこない
    func missionSummary(roomId: UUID,
                        includeContent: Bool = true) async throws -> [MissionSummaryResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/missions/summary",
                                     query: [.init(name: "includeContent", value: String(includeContent))],
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    // MARK: - 写真（11_API設計.md §5 / G-6）

    /// アップロード用のSASをもらう。
    /// **実体はAPIを通さない**ので、これで場所と鍵だけを受け取る
    func photoUploadUrl(roomId: UUID, photoId: UUID,
                        visitId: UUID) async throws -> UploadUrlResponse {
        try await send(.post, "/rooms/\(roomId.apiString)/photos/upload-url",
                       body: UploadUrlRequest(photoId: photoId, visitId: visitId))
    }

    /// メタを登録する。**Blobへ上げ終えてから呼ぶ**（先に呼ぶと実体の無い行が残る）
    func savePhotoMeta(roomId: UUID, photoId: UUID, visitId: UUID, takenAt: Date) async throws {
        _ = try await sendRaw(.put, "/rooms/\(roomId.apiString)/photos/\(photoId.apiString)",
                              rawBody: try encoder.encode(SavePhotoBody(visitId: visitId,
                                                                        takenAt: takenAt)),
                              authorized: true)
    }

    /// ルームの写真一覧（表示用SAS付き）。**仲間が撮ったぶんも返る**
    func photos(roomId: UUID) async throws -> [PhotoResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/photos",
                                     rawBody: nil, authorized: true)
        return try decode(data)
    }

    /// 写真を消す（撮影者本人のみ）。実体も一緒に消える
    func deletePhoto(roomId: UUID, photoId: UUID) async throws {
        _ = try await sendRaw(.delete, "/rooms/\(roomId.apiString)/photos/\(photoId.apiString)",
                              rawBody: nil, authorized: true)
    }

    /// Blobへ実体を上げる。**APIを通らない**ので、baseURL もトークンも使わない
    func uploadBlob(_ data: Data, to url: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: Self.coldStartTimeout)
        request.httpMethod = HTTPMethod.put.rawValue
        // **Azure Blob は種別の指定が要る。** 無いと 400 で弾かれる
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            throw ApiError.offline(underlying: error)
        }
        try check(response)
    }

    /// Blobから実体を取る
    func downloadBlob(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: Self.coldStartTimeout)
        request.httpMethod = HTTPMethod.get.rawValue

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.offline(underlying: error)
        }
        try check(response)
        return data
    }

    func schedules(roomId: UUID) async throws -> [ScheduleResponse] {
        let data = try await sendRaw(.get, "/rooms/\(roomId.apiString)/schedules",
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
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
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
                         query: [URLQueryItem] = [],
                         rawBody: Data?, authorized: Bool) async throws -> Data {
        var request = URLRequest(url: url(path, query: query),
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

        try check(response, body: data)
        return data
    }

    /// 応答が成功かを見る。失敗なら本文からサーバーの言い分を読む
    private func check(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ApiError.malformedResponse(underlying: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError.server(
                status: http.statusCode,
                detail: body.flatMap { try? decoder.decode(ApiErrorBody.self, from: $0) })
        }
    }

    /// 問い合わせ付きのURLを組み立てる。
    /// **`appendingPathComponent` に `?` を渡すと `%3F` に化ける**ので、別々に組む
    private func url(_ path: String, query: [URLQueryItem]) -> URL {
        let base = baseURL.appendingPathComponent(path)
        guard !query.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = query
        return components.url ?? base
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
    /// お題の見え方（0=お楽しみ / 1=いつでも見える）。
    /// **古いサーバーは返さない**ので省略できるようにしてある
    let missionVisibility: Int?
}

/// ルームの設定を変える（いまはお題の見え方だけ）。
/// 送らなかった項目は変えない
struct UpdateRoomRequest: Encodable {
    var startStationId: Int?
    var goalStationId: Int?
    var diceMax: Int?
    var missionVisibility: Int?
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
    /// 書いた人。**古いサーバーは返さない**ので省略可にしてある
    let memberId: UUID?
    let createdByName: String
}

struct MissionSummaryResponse: Codable {
    let stationId: Int
    let count: Int
    let effectCount: Int
    let backEffectCount: Int
    /// 中身。伏せる設定のときと、古いサーバーからは空で返る
    let missions: [MissionBriefResponse]?
}

struct MissionBriefResponse: Codable, Identifiable {
    let missionId: UUID
    let memberId: UUID?
    let content: String
    let createdByName: String

    var id: UUID { missionId }
}

// MARK: - 写真

private struct UploadUrlRequest: Encodable {
    let photoId: UUID
    let visitId: UUID
}

private struct SavePhotoBody: Encodable {
    let visitId: UUID
    let takenAt: Date
}

struct UploadUrlResponse: Codable {
    let photoId: UUID
    /// コンテナ内のパス。**署名付きURLではない**ので、記録として持てる
    let blobPath: String
    /// 期限付きの書き込み先
    let uploadUrl: String
    let expiresAt: Date
}

struct PhotoResponse: Codable {
    let photoId: UUID
    let visitId: UUID
    let stationId: Int
    let takenBy: UUID
    let takenByName: String
    let takenAt: Date
    /// 期限付きの読み取り先。**そのまま保存しない**（切れると意味を失う）
    let url: String
    let urlExpiresAt: Date
}

struct ScheduleResponse: Codable {
    let scheduleId: UUID
    let title: String
    let startAt: Date
    let meetPlace: String?
    let courseId: Int?
    let courseName: String?
    let startOrder: Int?
    let goalOrder: Int?
    let diceMax: Int?
    let createdBy: UUID?
    /// ここから詳細設定。**古いサーバーは返さない**ので、すべて省略可
    let isLap: Bool?
    let loopDirection: Int?
    let usesDice: Bool?
    let usesMissions: Bool?
    let missionVisibility: Int?
    let arrivalRadius: Double?
    let isShared: Bool?
    let timeZoneId: String?
    /// お題の取り組み方（0=みんなで1つ 1=めいめい）。古いサーバーは返さない
    let missionStyle: Int?
    let includesOwnMissions: Bool?
    let attendees: [AttendeeResponse]
}

struct AttendeeResponse: Codable {
    let memberId: UUID
    let displayName: String
    let status: Int
}

/// 終わったターン。**現在地はこれで決まる**
struct CompletedTurnResponse: Codable {
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
    let endStationId: Int
    let completedAt: Date?
}

struct StateResponse: Codable {
    let currentStationId: Int
    let isCleared: Bool
    let activeTurn: ActiveTurnResponse?
    let visits: [VisitResponse]
    let completedTurnCount: Int
    /// 終わったターン。**古いサーバーは返さない**ので省略できるようにしてある
    let completedTurns: [CompletedTurnResponse]?
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
