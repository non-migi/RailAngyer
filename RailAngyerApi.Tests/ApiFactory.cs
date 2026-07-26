using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using RailAngyerApi.Data;
using RailAngyerApi.Storage;

namespace RailAngyerApi.Tests;

/// <summary>
/// テスト用にAPIを立ち上げる。
///
/// <para>SQL Server の代わりに <b>SQLite のインメモリDB</b>を使う。
/// Azure のDBを汚さず、無料枠も消費せずに、実際のHTTPを通した確認ができる。
/// スキーマは <c>EnsureCreated</c> で DbContext の定義から作る
/// （本番のテーブルは 06_schema.sql が正であり、こちらはその写しである点に注意）。</para>
/// </summary>
public class ApiFactory : WebApplicationFactory<Program>, IDisposable
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    /// <summary>Blob の代わり。テストから中身を確認できるよう外に出す</summary>
    public FakePhotoStorage Photos { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        _connection.Open();   // 開いている間だけインメモリDBが生きる

        // ⚠️ SQLite は既定で外部キーを検査しない。
        // 自分で開いた接続には EF が PRAGMA を送らないので、ここで有効にする。
        // これが無いと <b>FK違反が本番でしか出ない</b>
        //（MissionSet と Member の循環参照による 547 を実際に取り逃がした）
        using (var pragma = _connection.CreateCommand())
        {
            pragma.CommandText = "PRAGMA foreign_keys = ON;";
            pragma.ExecuteNonQuery();
        }

        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            // 本番用の SQL Server 登録を捨てて SQLite に差し替える
            var descriptors = services
                .Where(d => d.ServiceType == typeof(DbContextOptions<RailAngyerDbContext>)
                         || d.ServiceType == typeof(RailAngyerDbContext))
                .ToList();
            foreach (var d in descriptors) services.Remove(d);

            services.AddDbContext<RailAngyerDbContext>(o => o.UseSqlite(_connection));

            // Blob も本物には触らない
            services.RemoveAll<IPhotoStorage>();
            services.AddSingleton<IPhotoStorage>(Photos);

            using var scope = services.BuildServiceProvider().CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<RailAngyerDbContext>();
            db.Database.EnsureCreated();
            Seed(db);
        });
    }

    /// <summary>南北線の一部（テストに必要な最低限）</summary>
    private static void Seed(RailAngyerDbContext db)
    {
        if (db.Courses.Any()) return;

        var course = new Course { Name = "南北線", LineColor = "#00A85A", CreatedAt = DateTime.UtcNow };
        db.Courses.Add(course);
        db.SaveChanges();

        string[] names = ["麻生", "北34条", "北24条", "北18条", "北12条", "さっぽろ",
                          "大通", "すすきの", "中島公園", "幌平橋", "中の島", "平岸",
                          "南平岸", "澄川", "自衛隊前", "真駒内"];
        for (var i = 0; i < names.Length; i++)
        {
            db.Stations.Add(new Station
            {
                CourseId = course.CourseId,
                Name = names[i],
                OrderNo = i + 1,
                Latitude = 43.11 - i * 0.008,
                Longitude = 141.34 + i * 0.001
            });
        }
        db.SaveChanges();
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) _connection.Dispose();
    }
}
