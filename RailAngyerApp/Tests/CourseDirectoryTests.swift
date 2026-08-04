import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// コースを国 → 都道府県 → 路線でたどる並べ替え（`CourseDirectory`）。
///
/// **路線が増えるほど、平らな一覧では自分の街の路線を探せなくなる。**
/// ここで確かめたいのは「たどれば必ず着く」こと。とくに
/// **県をまたぐ路線がどちらの県からも見つかる**ことと、
/// 国と県を持たない古い端末のデータでも行き止まりにならないこと。
@MainActor
struct CourseDirectoryTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    private var directory: CourseDirectory { CourseDirectory(courses: store.courses) }

    private func courses(inRegion name: String) throws -> [String] {
        let japan = try #require(directory.countries.first { $0.id == "JP" })
        let region = try #require(japan.regions.first { $0.name == name })
        return region.courses.map(\.name)
    }

    @Test("国は日本を先頭に、あとは名前の順で並ぶ")
    func japanComesFirst() throws {
        // **日本を先に出す。** 作った人の地元であり、コースもいちばん多い。
        // 以降は国名の順（アメリカ合衆国 → イギリス → ドイツ → ロシア → 中国）
        #expect(directory.countries.map(\.id) == ["JP", "US", "GB", "DE", "RU", "CN"])

        let japan = try #require(directory.countries.first)
        #expect(japan.name == "日本")
    }

    @Test("国ごとのコース数が合う")
    func courseCountPerCountry() throws {
        let japan = try #require(directory.countries.first { $0.id == "JP" })
        let germany = try #require(directory.countries.first { $0.id == "DE" })

        // 県をまたぐ路線も1本として数える
        #expect(japan.courseCount == 7)
        #expect(germany.courseCount == 1)
        // モスクワは2本（環状線と大環状線）
        let russia = try #require(directory.countries.first { $0.id == "RU" })
        #expect(russia.courseCount == 2)
        // アメリカは2本（ニューヨークとロサンゼルス）
        let usa = try #require(directory.countries.first { $0.id == "US" })
        #expect(usa.courseCount == 2)
        #expect(directory.countries.reduce(0) { $0 + $1.courseCount } == store.courses.count)
    }

    @Test("日本の外のコースも、その国の下からたどれる")
    func overseasCoursesAreReachable() throws {
        let germany = try #require(directory.countries.first { $0.id == "DE" })
        let berlin = try #require(germany.regions.first { $0.name == "ベルリン" })

        #expect(berlin.courses.map(\.name) == ["ベルリン Ringbahn"])

        let uk = try #require(directory.countries.first { $0.id == "GB" })
        #expect(uk.regions.first?.courses.map(\.name) == ["ロンドン サークル線"])
    }

    @Test("都道府県は北から南の順に並ぶ")
    func regionsAreOrderedNorthToSouth() throws {
        let japan = try #require(directory.countries.first { $0.id == "JP" })

        // 全国地方公共団体コードと同じ順（北海道 → 東京都 → 京都府 → 大阪府）
        #expect(japan.regions.map(\.name) == ["北海道", "東京都", "京都府", "大阪府"])
    }

    @Test("県をまたぐ路線は、通るどちらの県からも見つかる")
    func crossingCourseAppearsInEveryRegion() throws {
        #expect(try courses(inRegion: "大阪府").contains("阪急京都本線"))
        #expect(try courses(inRegion: "京都府").contains("阪急京都本線"))
    }

    @Test("札幌の4路線は北海道の下だけに入る")
    func sapporoCoursesStayInHokkaido() throws {
        #expect(try courses(inRegion: "北海道").sorted()
                == ["南北線", "東豊線", "東西線", "札幌市電"].sorted())
        #expect(try courses(inRegion: "東京都") == ["山手線"])
    }

    @Test("県の中では駅数の多い路線が先")
    func coursesAreOrderedByStationCount() throws {
        let hokkaido = try courses(inRegion: "北海道")

        // 札幌市電24 → 東西線19 → 南北線16 → 東豊線14
        #expect(hokkaido == ["札幌市電", "東西線", "南北線", "東豊線"])
    }

    @Test("コースからその国を引ける")
    func findsCountryOfCourse() throws {
        let course = try #require(store.courses.first { $0.name == "阪急京都本線" })

        #expect(directory.country(of: course)?.name == "日本")
    }

    @Test("県の表示は中黒でつなぐ")
    func regionTextJoinsWithSeparator() throws {
        let hankyu = try #require(store.courses.first { $0.name == "阪急京都本線" })
        let nanboku = try #require(store.courses.first { $0.name == "南北線" })

        #expect(CourseDirectory.regionText(hankyu) == "大阪府・京都府")
        #expect(CourseDirectory.regionText(nanboku) == "北海道")
    }

    @Test("県を持たない古いデータは「その他」にまとめる")
    func courseWithoutRegionFallsBack() throws {
        // 国と県は後から足した項目。書き足す前に作られたコースが端末に残りうる
        let orphan = Course(name: "むかしのコース")
        orphan.regionNamesText = ""
        context.insert(orphan)
        try context.save()

        let japan = try #require(CourseDirectory(courses: store.courses)
            .countries.first { $0.id == "JP" })
        let other = try #require(japan.regions.first { $0.name == "その他" })

        #expect(other.courses.map(\.name) == ["むかしのコース"])
        // 一覧に無い名前は後ろへ回す。既知の県が先に並ぶ
        #expect(japan.regions.last?.name == "その他")
    }

    @Test("マスタを読み直しても国と県は消えない")
    func reseedingKeepsRegions() throws {
        _ = try MasterSeeder.seedIfNeeded(context)

        for course in store.courses {
            // **日本とは限らない。** ベルリン=DE、ロンドン=GB
            #expect(course.countryCode.count == 2, "\(course.name) の国コードが変")
            #expect(course.regionNames.isEmpty == false, "\(course.name) に地方が無い")
        }
    }
}
