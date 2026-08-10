namespace RailAngyerApi.Data;

// 06_schema.sql（ver.2）のテーブルと1対1で対応させる。
// 列名・型を変えると同期がずれるため、勝手に変えない。

public class Course
{
    public int CourseId { get; set; }
    public string Name { get; set; } = "";
    public string? LineColor { get; set; }
    public DateTime CreatedAt { get; set; }

    public List<Station> Stations { get; set; } = [];
}

public class Station
{
    public int StationId { get; set; }
    public int CourseId { get; set; }
    public string Name { get; set; } = "";
    /// <summary>路線の端からの通し番号。位置計算はすべてこの値で行う</summary>
    public int OrderNo { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }

    public Course? Course { get; set; }
}

public class MissionSet
{
    public Guid MissionSetId { get; set; }
    public int CourseId { get; set; }
    public string Name { get; set; } = "";
    public string InviteCode { get; set; } = "";
    /// <summary>区間のスタート駅。戻る効果でもここより手前へは行かない</summary>
    public int StartStationId { get; set; }
    /// <summary>区間のゴール駅。ここに到達でクリア</summary>
    public int GoalStationId { get; set; }
    /// <summary>最大出目（1〜9）</summary>
    public byte DiceMax { get; set; } = 6;
    public DateTime CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }

    public Course? Course { get; set; }
    public Station? StartStation { get; set; }
    public Station? GoalStation { get; set; }
    public List<Member> Members { get; set; } = [];
}

public class Member
{
    public Guid MemberId { get; set; }
    public Guid MissionSetId { get; set; }
    public string DisplayName { get; set; } = "";
    public DateTime JoinedAt { get; set; }

    /// <summary>
    /// 参加時に発行したトークンの SHA-256。平文は保存しない（11_API設計.md §2）。
    /// リクエストの MemberId を信用せず、ここから本人を引く。
    /// </summary>
    public byte[]? TokenHash { get; set; }

    public MissionSet? MissionSet { get; set; }
}

public class Mission
{
    public Guid MissionId { get; set; }
    public Guid MissionSetId { get; set; }
    public Guid MemberId { get; set; }
    public int StationId { get; set; }
    public string Content { get; set; } = "";
    /// <summary>0=なし 1=進む 2=戻る 3=もう一度振る 4=指定駅へ移動</summary>
    public byte EffectType { get; set; }
    public byte? EffectValue { get; set; }
    public int? EffectStationId { get; set; }
    public DateTime CreatedAt { get; set; }

    public Member? Member { get; set; }
    public Station? Station { get; set; }
    public Station? EffectStation { get; set; }
}

public class Turn
{
    public Guid TurnId { get; set; }
    public Guid MissionSetId { get; set; }
    /// <summary>表示用の連番。順序の判定には使わない（11_API設計.md §4）</summary>
    public int TurnNo { get; set; }
    public int FromStationId { get; set; }
    public byte DiceValue { get; set; }
    public int LandingStationId { get; set; }
    /// <summary>クライアントが振った時刻。<b>現在位置の判定はこの順で行う</b></summary>
    public DateTime RolledAt { get; set; }
    public DateTime? ArrivedAt { get; set; }
    public Guid? SelectedMissionId { get; set; }
    public bool MissionDone { get; set; }
    public byte? AppliedEffectType { get; set; }
    /// <summary>効果適用後の終了位置。null なら進行中</summary>
    public int? EndStationId { get; set; }
    public DateTime? CompletedAt { get; set; }

    public Station? FromStation { get; set; }
    public Station? LandingStation { get; set; }
    public Station? EndStation { get; set; }
    public Mission? SelectedMission { get; set; }
}

public class Visit
{
    public Guid VisitId { get; set; }
    public Guid MissionSetId { get; set; }
    /// <summary>始点の記録のみ null</summary>
    public Guid? TurnId { get; set; }
    public int StationId { get; set; }
    public DateTime ArrivedAt { get; set; }
    /// <summary>0=始点 1=通り道 2=着地 3=効果移動の通り道 4=効果移動の到達点</summary>
    public byte VisitKind { get; set; }

    public Turn? Turn { get; set; }
    public Station? Station { get; set; }
    public List<Photo> Photos { get; set; } = [];
}

public class Photo
{
    public Guid PhotoId { get; set; }
    public Guid VisitId { get; set; }
    /// <summary>撮影者</summary>
    public Guid MemberId { get; set; }
    public string BlobUrl { get; set; } = "";
    public DateTime TakenAt { get; set; }

    public Visit? Visit { get; set; }
    public Member? Member { get; set; }
}

public class Schedule
{
    public Guid ScheduleId { get; set; }
    public Guid MissionSetId { get; set; }
    public string Title { get; set; } = "";
    public DateTime StartAt { get; set; }
    public string? MeetPlace { get; set; }
    public int? CourseId { get; set; }
    public string? CourseName { get; set; }
    public int? StartOrder { get; set; }
    public int? GoalOrder { get; set; }
    public byte? DiceMax { get; set; }
    public Guid? CreatedBy { get; set; }

    // --- 予定ごとに決める詳細設定（25_migration_v5_schedule_detail.sql）。
    // NULL は「これまで通りの遊び方」。旧アプリからのリクエストは NULL のまま届く。

    /// <summary>環状コースを一周する予定か。true のときスタートとゴールは同じ駅</summary>
    public bool? IsLap { get; set; }
    /// <summary>一周するときにまわる向き。1=通し番号が増える向き -1=減る向き</summary>
    public short? LoopDirection { get; set; }
    /// <summary>サイコロを使うか。false なら1駅ずつ順に歩くだけ</summary>
    public bool? UsesDice { get; set; }
    /// <summary>お題を使うか</summary>
    public bool? UsesMissions { get; set; }
    /// <summary>お題の見え方。0=全員に見える 1=着いた人だけ</summary>
    public byte? MissionVisibility { get; set; }
    /// <summary>到着判定の半径（メートル / 50〜320）</summary>
    public double? ArrivalRadius { get; set; }
    /// <summary>仲間と共有するか</summary>
    public bool? IsShared { get; set; }
    /// <summary>集合日時をどの土地の時計で読むか（例 Asia/Tokyo）。NULL は日本時間</summary>
    public string? TimeZoneId { get; set; }

    public List<ScheduleAttendee> Attendees { get; set; } = [];
}

public class ScheduleAttendee
{
    public Guid ScheduleId { get; set; }
    public Guid MemberId { get; set; }
    /// <summary>0=未定 1=参加 2=不参加</summary>
    public byte Status { get; set; }

    public Schedule? Schedule { get; set; }
    public Member? Member { get; set; }
}
