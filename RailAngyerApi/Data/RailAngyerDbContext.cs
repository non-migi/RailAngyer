using Microsoft.EntityFrameworkCore;

namespace RailAngyerApi.Data;

/// <summary>
/// 既存のスキーマ（06_schema.sql ver.2）に合わせた DbContext。
/// <b>マイグレーションでスキーマを作らない。</b>テーブルはSQLスクリプトが正であり、
/// ここはその形に合わせるだけにする（DBとアプリの両方から定義が生えると食い違うため）。
/// </summary>
public class RailAngyerDbContext(DbContextOptions<RailAngyerDbContext> options) : DbContext(options)
{
    public DbSet<Course> Courses => Set<Course>();
    public DbSet<Station> Stations => Set<Station>();
    public DbSet<MissionSet> MissionSets => Set<MissionSet>();
    public DbSet<Member> Members => Set<Member>();
    public DbSet<Mission> Missions => Set<Mission>();
    public DbSet<Turn> Turns => Set<Turn>();
    public DbSet<Visit> Visits => Set<Visit>();
    public DbSet<Photo> Photos => Set<Photo>();
    public DbSet<Schedule> Schedules => Set<Schedule>();
    public DbSet<ScheduleAttendee> ScheduleAttendees => Set<ScheduleAttendee>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Course>(e =>
        {
            e.ToTable("Course");
            e.HasKey(x => x.CourseId);
            e.Property(x => x.Name).HasMaxLength(50).IsRequired();
            e.Property(x => x.LineColor).HasMaxLength(9);
            e.HasIndex(x => x.Name).IsUnique();
        });

        b.Entity<Station>(e =>
        {
            e.ToTable("Station");
            e.HasKey(x => x.StationId);
            e.Property(x => x.Name).HasMaxLength(50).IsRequired();
            e.HasOne(x => x.Course).WithMany(x => x.Stations).HasForeignKey(x => x.CourseId);
            e.HasIndex(x => new { x.CourseId, x.OrderNo }).IsUnique();
        });

        b.Entity<MissionSet>(e =>
        {
            e.ToTable("MissionSet");
            e.HasKey(x => x.MissionSetId);
            e.Property(x => x.Name).HasMaxLength(100).IsRequired();
            e.Property(x => x.InviteCode).HasMaxLength(10).IsRequired();
            e.HasIndex(x => x.InviteCode).IsUnique();
            e.HasOne(x => x.Course).WithMany().HasForeignKey(x => x.CourseId);
            e.HasOne(x => x.StartStation).WithMany().HasForeignKey(x => x.StartStationId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.GoalStation).WithMany().HasForeignKey(x => x.GoalStationId)
                .OnDelete(DeleteBehavior.NoAction);
            // 06_schema.sql の FK_MissionSet_Creator。ナビゲーションは持たないが、
            // <b>EFに教えておかないとテスト用のSQLiteにこの制約が作られない</b>。
            // Member 側とで参照が循環するため、書き込み順を誤ると本番だけ落ちる
            e.HasOne<Member>().WithMany().HasForeignKey(x => x.CreatedBy)
                .OnDelete(DeleteBehavior.NoAction);
        });

        b.Entity<Member>(e =>
        {
            e.ToTable("Member");
            e.HasKey(x => x.MemberId);
            e.Property(x => x.DisplayName).HasMaxLength(50).IsRequired();
            e.Property(x => x.TokenHash).HasColumnType("binary(32)");
            e.HasOne(x => x.MissionSet).WithMany(x => x.Members).HasForeignKey(x => x.MissionSetId)
                .OnDelete(DeleteBehavior.NoAction);
            // 同一ルーム内の同名を禁止（UQ-04）
            e.HasIndex(x => new { x.MissionSetId, x.DisplayName }).IsUnique();
        });

        b.Entity<Mission>(e =>
        {
            e.ToTable("Mission");
            e.HasKey(x => x.MissionId);
            e.Property(x => x.Content).HasMaxLength(300).IsRequired();
            e.HasOne(x => x.Member).WithMany().HasForeignKey(x => x.MemberId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.Station).WithMany().HasForeignKey(x => x.StationId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.EffectStation).WithMany().HasForeignKey(x => x.EffectStationId)
                .OnDelete(DeleteBehavior.NoAction);
            // 駅ごとに1人1個まで（UQ-05）
            e.HasIndex(x => new { x.MissionSetId, x.MemberId, x.StationId }).IsUnique();
        });

        b.Entity<Turn>(e =>
        {
            e.ToTable("Turn");
            e.HasKey(x => x.TurnId);
            e.HasOne(x => x.FromStation).WithMany().HasForeignKey(x => x.FromStationId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.LandingStation).WithMany().HasForeignKey(x => x.LandingStationId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.EndStation).WithMany().HasForeignKey(x => x.EndStationId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.SelectedMission).WithMany().HasForeignKey(x => x.SelectedMissionId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasIndex(x => new { x.MissionSetId, x.TurnNo }).IsUnique();
        });

        b.Entity<Visit>(e =>
        {
            e.ToTable("Visit");
            e.HasKey(x => x.VisitId);
            e.HasOne(x => x.Turn).WithMany().HasForeignKey(x => x.TurnId)
                .OnDelete(DeleteBehavior.NoAction);
            e.HasOne(x => x.Station).WithMany().HasForeignKey(x => x.StationId)
                .OnDelete(DeleteBehavior.NoAction);
            // 駅の一意制約は持たない。戻る・ジャンプで再訪するため（ver.2）
            e.HasIndex(x => new { x.MissionSetId, x.StationId });
        });

        b.Entity<Photo>(e =>
        {
            e.ToTable("Photo");
            e.HasKey(x => x.PhotoId);
            e.Property(x => x.BlobUrl).HasMaxLength(500).IsRequired();
            e.HasOne(x => x.Visit).WithMany(x => x.Photos).HasForeignKey(x => x.VisitId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Member).WithMany().HasForeignKey(x => x.MemberId)
                .OnDelete(DeleteBehavior.NoAction);
        });

        b.Entity<Schedule>(e =>
        {
            e.ToTable("Schedule");
            e.HasKey(x => x.ScheduleId);
            e.Property(x => x.Title).HasMaxLength(100).IsRequired();
            e.Property(x => x.MeetPlace).HasMaxLength(100);
        });

        b.Entity<ScheduleAttendee>(e =>
        {
            e.ToTable("ScheduleAttendee");
            e.HasKey(x => new { x.ScheduleId, x.MemberId });
            e.HasOne(x => x.Schedule).WithMany(x => x.Attendees).HasForeignKey(x => x.ScheduleId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Member).WithMany().HasForeignKey(x => x.MemberId)
                .OnDelete(DeleteBehavior.NoAction);
        });
    }
}
