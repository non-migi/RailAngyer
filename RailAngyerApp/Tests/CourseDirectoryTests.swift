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

    @Test("同梱コースはすべて日本の下に入る")
    func everyCourseIsUnderJapan() throws {
        #expect(directory.countries.map(\.id) == ["JP"])

        let japan = try #require(directory.countries.first)
        #expect(japan.name == "日本")
        // 県をまたぐ路線も1本として数える
        #expect(japan.courseCount == store.courses.count)
    }

    @Test("都道府県は北から南の順に並ぶ")
    func regionsAreOrderedNorthToSouth() throws {
        let japan = try #require(directory.countries.first)

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
            #expect(course.countryCode == "JP")
            #expect(course.regionNames.isEmpty == false, "\(course.name) に都道府県が無い")
        }
    }
}
