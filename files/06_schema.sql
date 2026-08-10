/* ============================================================
   RailAngyer
   Azure SQL Database / SQL Server 用 スキーマ定義  ver.2

   ver.2 での変更点（可変ルール対応）
     - Turn（手番）テーブルを新設。1回のサイコロ＝1行。
       これにより「戻る」「ジャンプ」「もう一度振る」と、
       進行中ターンの永続化（アプリ再起動からの復帰）が可能になった。
     - Visit から DiceValue / SelectedMissionId / MissionDone を Turn へ移動。
       Visit は「いつどの駅に着いたか」だけを積む記録に単純化し、
       同じ駅への再訪（戻る・ジャンプで発生する）を許可した。
     - MissionSet に 区間（StartStationId / GoalStationId）と
       サイコロの最大出目（DiceMax 1〜9）を追加。
     - Mission に 効果（EffectType / EffectValue / EffectStationId）を追加。

   仕様の出典: 01_企画仕様書.md / 05_フロー仕様.html / 07_データモデル仕様.html
   ============================================================ */

/* ------------------------------------------------------------
   0. 作り直し用（開発中のみ。本番では実行しないこと）
   ------------------------------------------------------------ */
IF OBJECT_ID('dbo.Photo',            'U') IS NOT NULL DROP TABLE dbo.Photo;
IF OBJECT_ID('dbo.Visit',            'U') IS NOT NULL DROP TABLE dbo.Visit;
IF OBJECT_ID('dbo.Turn',             'U') IS NOT NULL DROP TABLE dbo.Turn;
IF OBJECT_ID('dbo.ScheduleAttendee', 'U') IS NOT NULL DROP TABLE dbo.ScheduleAttendee;
IF OBJECT_ID('dbo.Schedule',         'U') IS NOT NULL DROP TABLE dbo.Schedule;
IF OBJECT_ID('dbo.Mission',          'U') IS NOT NULL DROP TABLE dbo.Mission;
IF OBJECT_ID('dbo.Member',           'U') IS NOT NULL DROP TABLE dbo.Member;
IF OBJECT_ID('dbo.MissionSet',       'U') IS NOT NULL DROP TABLE dbo.MissionSet;
IF OBJECT_ID('dbo.Station',          'U') IS NOT NULL DROP TABLE dbo.Station;
IF OBJECT_ID('dbo.Course',           'U') IS NOT NULL DROP TABLE dbo.Course;
GO


/* ============================================================
   1. マスタ ── コースと駅
   ============================================================ */

CREATE TABLE dbo.Course (
    CourseId    INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(50)      NOT NULL,   -- 「南北線」「山手線」など
    LineColor   NVARCHAR(9)       NULL,       -- 路線カラー #RRGGBB
    CreatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Course_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Course      PRIMARY KEY (CourseId),
    CONSTRAINT UQ_Course_Name UNIQUE (Name)
);
GO

CREATE TABLE dbo.Station (
    StationId   INT IDENTITY(1,1) NOT NULL,
    CourseId    INT               NOT NULL,
    Name        NVARCHAR(50)      NOT NULL,
    OrderNo     INT               NOT NULL,   -- コース内の並び順。路線の端から通しで振る（区間の指定とは独立）
    Latitude    FLOAT             NOT NULL,
    Longitude   FLOAT             NOT NULL,
    CONSTRAINT PK_Station          PRIMARY KEY (StationId),
    CONSTRAINT FK_Station_Course   FOREIGN KEY (CourseId) REFERENCES dbo.Course(CourseId),
    CONSTRAINT UQ_Station_Order    UNIQUE (CourseId, OrderNo),
    CONSTRAINT CK_Station_OrderNo  CHECK (OrderNo >= 1),
    CONSTRAINT CK_Station_Lat      CHECK (Latitude  BETWEEN -90  AND 90),
    CONSTRAINT CK_Station_Lng      CHECK (Longitude BETWEEN -180 AND 180)
);
GO


/* ============================================================
   2. ルーム ── ミッションセットとメンバー

   区間（Start / Goal）と最大出目（DiceMax）はルーム単位の設定。
   同じコースでも、ルームごとに違う区間・違うサイコロで遊べる。
   ============================================================ */

CREATE TABLE dbo.MissionSet (
    MissionSetId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_MissionSet_Id DEFAULT NEWID(),
    CourseId       INT              NOT NULL,
    Name           NVARCHAR(100)    NOT NULL,
    InviteCode     NVARCHAR(10)     NOT NULL,

    /* --- 区間設定 ------------------------------------------------
       StartStationId と GoalStationId は同一コース内の任意の駅。
       Start の OrderNo < Goal の OrderNo なら順方向、逆なら逆方向に進む。
       全線を通しで遊ぶ場合は両端の駅を指定する。
       ------------------------------------------------------------ */
    StartStationId INT              NOT NULL,
    GoalStationId  INT              NOT NULL,

    /* --- サイコロ設定 --------------------------------------------
       出目は 1〜DiceMax の一様乱数。DiceMax=1 なら毎ターン必ず1駅ずつ進む
       （＝区間内の全駅でミッションを行うモードになる）。
       ------------------------------------------------------------ */
    DiceMax        TINYINT          NOT NULL CONSTRAINT DF_MissionSet_DiceMax DEFAULT 6,

    /* --- お題の見え方 --------------------------------------------
       0 = 当日までのお楽しみ（既定）。他人のお題は件数しか返さない
       1 = いつでも見える。予定の段階から全員のお題を読める

       **サーバーが他人のお題を返すかどうかを決める値。**
       クライアントで隠すだけでは、通信を覗けば見えてしまう。
       ------------------------------------------------------------ */
    MissionVisibility TINYINT       NOT NULL CONSTRAINT DF_MissionSet_MissionVisibility DEFAULT 0,

    CreatedAt      DATETIME2(0)     NOT NULL CONSTRAINT DF_MissionSet_CreatedAt DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_MissionSet         PRIMARY KEY (MissionSetId),
    CONSTRAINT FK_MissionSet_Course  FOREIGN KEY (CourseId)       REFERENCES dbo.Course(CourseId),
    CONSTRAINT FK_MissionSet_Start   FOREIGN KEY (StartStationId) REFERENCES dbo.Station(StationId),
    CONSTRAINT FK_MissionSet_Goal    FOREIGN KEY (GoalStationId)  REFERENCES dbo.Station(StationId),
    CONSTRAINT UQ_MissionSet_Invite  UNIQUE (InviteCode),
    CONSTRAINT CK_MissionSet_Range   CHECK (StartStationId <> GoalStationId),
    CONSTRAINT CK_MissionSet_DiceMax CHECK (DiceMax BETWEEN 1 AND 9),
    CONSTRAINT CK_MissionSet_MissionVisibility CHECK (MissionVisibility IN (0, 1))
);
GO

/* Start / Goal が CourseId と同じコースの駅であることは CHECK では表現できない
   （他テーブルの参照が必要）。アプリ側または下記のトリガーで担保する。 */

CREATE TABLE dbo.Member (
    MemberId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Member_Id DEFAULT NEWID(),
    MissionSetId UNIQUEIDENTIFIER NOT NULL,
    DisplayName  NVARCHAR(50)     NOT NULL,
    JoinedAt     DATETIME2(0)     NOT NULL CONSTRAINT DF_Member_JoinedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Member            PRIMARY KEY (MemberId),
    /* MissionSet 直下の子テーブルには CASCADE を付けない。
       Member を経由する参照と多重カスケード経路になり、ルーム削除が実行時に失敗するため。 */
    CONSTRAINT FK_Member_MissionSet FOREIGN KEY (MissionSetId) REFERENCES dbo.MissionSet(MissionSetId),
    CONSTRAINT UQ_Member_Name       UNIQUE (MissionSetId, DisplayName)
);
GO

ALTER TABLE dbo.MissionSet ADD CreatedBy UNIQUEIDENTIFIER NULL;
GO
ALTER TABLE dbo.MissionSet ADD CONSTRAINT FK_MissionSet_Creator
    FOREIGN KEY (CreatedBy) REFERENCES dbo.Member(MemberId);
GO


/* ============================================================
   3. ミッション

   駅ごとに、1メンバーにつき1個まで（0個でもよい）。
   ver.2 から「効果」を持てる。効果なし（EffectType=0）が通常のお題。
   ============================================================ */

CREATE TABLE dbo.Mission (
    MissionId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Mission_Id DEFAULT NEWID(),
    MissionSetId    UNIQUEIDENTIFIER NOT NULL,
    MemberId        UNIQUEIDENTIFIER NOT NULL,
    StationId       INT              NOT NULL,
    Content         NVARCHAR(300)    NOT NULL,

    /* --- 効果 ----------------------------------------------------
       0 = なし          … 通常のお題。コマは動かない
       1 = 進む          … EffectValue 駅ぶん、ゴール方向へ進む
       2 = 戻る          … EffectValue 駅ぶん、スタート方向へ戻る
       3 = もう一度振る  … そのままもう1ターン
       4 = 指定駅へ移動  … EffectStationId の駅へ飛ぶ（前後どちらも可）

       効果による移動でも、途中の駅は歩いて訪れる（P-03）。
       移動先ではミッションを引かない（連鎖を防ぐ）。
       ------------------------------------------------------------ */
    EffectType      TINYINT          NOT NULL CONSTRAINT DF_Mission_EffectType DEFAULT 0,
    EffectValue     TINYINT          NULL,     -- EffectType 1/2 のときの駅数
    EffectStationId INT              NULL,     -- EffectType 4 のときの移動先

    CreatedAt       DATETIME2(0)     NOT NULL CONSTRAINT DF_Mission_CreatedAt DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Mission             PRIMARY KEY (MissionId),
    CONSTRAINT FK_Mission_MissionSet  FOREIGN KEY (MissionSetId)    REFERENCES dbo.MissionSet(MissionSetId),
    CONSTRAINT FK_Mission_Member      FOREIGN KEY (MemberId)        REFERENCES dbo.Member(MemberId),
    CONSTRAINT FK_Mission_Station     FOREIGN KEY (StationId)       REFERENCES dbo.Station(StationId),
    CONSTRAINT FK_Mission_EffectStn   FOREIGN KEY (EffectStationId) REFERENCES dbo.Station(StationId),

    /* 「1人1駅につき1個まで」を担保する中核の制約 */
    CONSTRAINT UQ_Mission_PerStation  UNIQUE (MissionSetId, MemberId, StationId),
    CONSTRAINT CK_Mission_Content     CHECK (LEN(LTRIM(RTRIM(Content))) > 0),
    CONSTRAINT CK_Mission_EffectType  CHECK (EffectType IN (0,1,2,3,4)),
    /* 進む・戻るのときだけ駅数が必要。それ以外では入れさせない */
    CONSTRAINT CK_Mission_EffectValue CHECK (
        (EffectType IN (1,2) AND EffectValue BETWEEN 1 AND 9)
        OR (EffectType NOT IN (1,2) AND EffectValue IS NULL)
    ),
    /* 指定駅へ移動のときだけ移動先が必要 */
    CONSTRAINT CK_Mission_EffectStn   CHECK (
        (EffectType = 4 AND EffectStationId IS NOT NULL)
        OR (EffectType <> 4 AND EffectStationId IS NULL)
    )
);
GO

CREATE INDEX IX_Mission_Station ON dbo.Mission (MissionSetId, StationId)
    INCLUDE (Content, MemberId, EffectType, EffectValue, EffectStationId);
GO


/* ============================================================
   4. 予定
   ============================================================ */

CREATE TABLE dbo.Schedule (
    ScheduleId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Schedule_Id DEFAULT NEWID(),
    MissionSetId UNIQUEIDENTIFIER NOT NULL,
    Title        NVARCHAR(100)    NOT NULL,
    StartAt      DATETIME2(0)     NOT NULL,
    MeetPlace    NVARCHAR(100)    NULL,
    CourseId     INT              NULL,
    CourseName   NVARCHAR(50)     NULL,
    StartOrder   INT              NULL,
    GoalOrder    INT              NULL,
    DiceMax      TINYINT          NULL,
    CreatedBy    UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_Schedule            PRIMARY KEY (ScheduleId),
    CONSTRAINT FK_Schedule_MissionSet FOREIGN KEY (MissionSetId) REFERENCES dbo.MissionSet(MissionSetId),
    CONSTRAINT FK_Schedule_Creator    FOREIGN KEY (CreatedBy)    REFERENCES dbo.Member(MemberId),
    CONSTRAINT CK_Schedule_Dice       CHECK (DiceMax IS NULL OR DiceMax BETWEEN 1 AND 9),
    CONSTRAINT CK_Schedule_Section    CHECK (StartOrder IS NULL OR GoalOrder IS NULL OR StartOrder <> GoalOrder)
);
GO

CREATE TABLE dbo.ScheduleAttendee (
    ScheduleId UNIQUEIDENTIFIER NOT NULL,
    MemberId   UNIQUEIDENTIFIER NOT NULL,
    Status     TINYINT          NOT NULL CONSTRAINT DF_Attendee_Status DEFAULT 0,  -- 0=未定 1=参加 2=不参加
    CONSTRAINT PK_ScheduleAttendee PRIMARY KEY (ScheduleId, MemberId),
    CONSTRAINT FK_Attendee_Schedule FOREIGN KEY (ScheduleId)
        REFERENCES dbo.Schedule(ScheduleId) ON DELETE CASCADE,
    CONSTRAINT FK_Attendee_Member   FOREIGN KEY (MemberId) REFERENCES dbo.Member(MemberId),
    CONSTRAINT CK_Attendee_Status   CHECK (Status IN (0, 1, 2))
);
GO


/* ============================================================
   5. Turn（手番）  ── ver.2 で新設

   サイコロを1回振るごとに1行。ゲームの進行そのものを表す。
     - 振った時点で INSERT する（EndStationId は NULL のまま）ので、
       アプリが落ちても「何を振ってどこへ向かっていたか」が残る。
     - ミッションの効果で動いた場合は EndStationId が LandingStationId と異なる。
     - 現在位置 = 最後に完了したターンの EndStationId（0件ならルームの StartStationId）。
   ============================================================ */

CREATE TABLE dbo.Turn (
    TurnId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Turn_Id DEFAULT NEWID(),
    MissionSetId      UNIQUEIDENTIFIER NOT NULL,
    TurnNo            INT              NOT NULL,   -- ルーム内の連番。1始まり

    FromStationId     INT              NOT NULL,   -- 振った時点の位置
    DiceValue         TINYINT          NOT NULL,   -- 出た目（1〜DiceMax）
    LandingStationId  INT              NOT NULL,   -- 出目による着地駅（区間の端でクランプ済み）
    RolledAt          DATETIME2(0)     NOT NULL CONSTRAINT DF_Turn_RolledAt DEFAULT SYSUTCDATETIME(),
    ArrivedAt         DATETIME2(0)     NULL,       -- 着地駅に到着した時刻。NULLなら移動中

    SelectedMissionId UNIQUEIDENTIFIER NULL,       -- 抽選で当たったミッション。候補0件ならNULL
    MissionDone       BIT              NOT NULL CONSTRAINT DF_Turn_MissionDone DEFAULT 0,

    AppliedEffectType TINYINT          NULL,       -- 発動した効果。0/NULL なら移動なし
    EndStationId      INT              NULL,       -- 効果適用後の最終位置。NULLならターン未完了
    CompletedAt       DATETIME2(0)     NULL,

    CONSTRAINT PK_Turn            PRIMARY KEY (TurnId),
    CONSTRAINT FK_Turn_MissionSet FOREIGN KEY (MissionSetId)      REFERENCES dbo.MissionSet(MissionSetId),
    CONSTRAINT FK_Turn_From       FOREIGN KEY (FromStationId)     REFERENCES dbo.Station(StationId),
    CONSTRAINT FK_Turn_Landing    FOREIGN KEY (LandingStationId)  REFERENCES dbo.Station(StationId),
    CONSTRAINT FK_Turn_End        FOREIGN KEY (EndStationId)      REFERENCES dbo.Station(StationId),
    CONSTRAINT FK_Turn_Mission    FOREIGN KEY (SelectedMissionId) REFERENCES dbo.Mission(MissionId),
    CONSTRAINT UQ_Turn_No         UNIQUE (MissionSetId, TurnNo),
    CONSTRAINT CK_Turn_Dice       CHECK (DiceValue BETWEEN 1 AND 9),
    CONSTRAINT CK_Turn_Effect     CHECK (AppliedEffectType IS NULL OR AppliedEffectType IN (0,1,2,3,4)),
    /* 完了したターンには終了時刻が入る */
    CONSTRAINT CK_Turn_Completed  CHECK (
        (EndStationId IS NULL AND CompletedAt IS NULL)
        OR (EndStationId IS NOT NULL AND CompletedAt IS NOT NULL)
    )
);
GO

/* 進行中（未完了）のターンは1ルームにつき1つまで。
   二重にサイコロを振ることをDB側で防ぐ。フィルター選択されたインデックス。 */
CREATE UNIQUE INDEX UX_Turn_Active ON dbo.Turn (MissionSetId) WHERE EndStationId IS NULL;
GO

CREATE INDEX IX_Turn_Set_No ON dbo.Turn (MissionSetId, TurnNo DESC) INCLUDE (EndStationId, CompletedAt);
GO


/* ============================================================
   6. Visit（訪問記録）

   ver.2 では「いつどの駅に着いたか」だけを積む。
   出目・ミッション・達成は Turn 側に持つ。
   戻る・ジャンプで同じ駅を再訪しうるため、駅の一意制約は持たない。
   ============================================================ */

CREATE TABLE dbo.Visit (
    VisitId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Visit_Id DEFAULT NEWID(),
    MissionSetId UNIQUEIDENTIFIER NOT NULL,
    TurnId       UNIQUEIDENTIFIER NULL,     -- どのターンでの訪問か。始点の記録のみ NULL
    StationId    INT              NOT NULL,
    ArrivedAt    DATETIME2(0)     NOT NULL CONSTRAINT DF_Visit_ArrivedAt DEFAULT SYSUTCDATETIME(),

    /* 0 = 始点（ゲーム開始時の記録）
       1 = 通り道（出目による移動の途中）
       2 = 着地（ミッションを行う駅）
       3 = 効果による移動の通り道
       4 = 効果による移動の到達点（ここではミッションを引かない） */
    VisitKind    TINYINT          NOT NULL,

    CONSTRAINT PK_Visit            PRIMARY KEY (VisitId),
    CONSTRAINT FK_Visit_MissionSet FOREIGN KEY (MissionSetId) REFERENCES dbo.MissionSet(MissionSetId),
    CONSTRAINT FK_Visit_Turn       FOREIGN KEY (TurnId)       REFERENCES dbo.Turn(TurnId),
    CONSTRAINT FK_Visit_Station    FOREIGN KEY (StationId)    REFERENCES dbo.Station(StationId),
    CONSTRAINT CK_Visit_Kind       CHECK (VisitKind IN (0,1,2,3,4)),
    /* 始点だけがターンに属さない */
    CONSTRAINT CK_Visit_TurnLink   CHECK (
        (VisitKind = 0 AND TurnId IS NULL) OR (VisitKind <> 0 AND TurnId IS NOT NULL)
    )
);
GO

CREATE INDEX IX_Visit_Set_Station ON dbo.Visit (MissionSetId, StationId) INCLUDE (VisitKind, ArrivedAt);
GO
CREATE INDEX IX_Visit_Turn ON dbo.Visit (TurnId);
GO


/* ============================================================
   7. 写真メタ
   ============================================================ */

CREATE TABLE dbo.Photo (
    PhotoId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Photo_Id DEFAULT NEWID(),
    VisitId  UNIQUEIDENTIFIER NOT NULL,
    MemberId UNIQUEIDENTIFIER NOT NULL,   -- 撮影者
    BlobUrl  NVARCHAR(500)    NOT NULL,
    TakenAt  DATETIME2(0)     NOT NULL CONSTRAINT DF_Photo_TakenAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Photo        PRIMARY KEY (PhotoId),
    CONSTRAINT FK_Photo_Visit  FOREIGN KEY (VisitId) REFERENCES dbo.Visit(VisitId) ON DELETE CASCADE,
    CONSTRAINT FK_Photo_Member FOREIGN KEY (MemberId) REFERENCES dbo.Member(MemberId)
);
GO

CREATE INDEX IX_Photo_Visit ON dbo.Photo (VisitId);
GO


/* ============================================================
   8. マスタ投入 ── 札幌市営地下鉄 南北線（麻生 → 真駒内、16駅）

   座標は国土交通省「国土数値情報 鉄道データ（N02-22）」の駅区間中央（JGD2011）。
   ============================================================ */

INSERT INTO dbo.Course (Name, LineColor) VALUES (N'南北線', N'#00A85A');

DECLARE @CourseId INT = SCOPE_IDENTITY();

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude) VALUES
    (@CourseId, N'麻生',      1, 43.108340, 141.338480),
    (@CourseId, N'北34条',    2, 43.100105, 141.342130),
    (@CourseId, N'北24条',    3, 43.089610, 141.344825),
    (@CourseId, N'北18条',    4, 43.081645, 141.346755),
    (@CourseId, N'北12条',    5, 43.074700, 141.348495),
    (@CourseId, N'さっぽろ',  6, 43.065860, 141.350665),
    (@CourseId, N'大通',      7, 43.060027, 141.352137),
    (@CourseId, N'すすきの',  8, 43.055300, 141.353365),
    (@CourseId, N'中島公園',  9, 43.048475, 141.355055),
    (@CourseId, N'幌平橋',   10, 43.040220, 141.355835),
    (@CourseId, N'中の島',   11, 43.037450, 141.361195),
    (@CourseId, N'平岸',     12, 43.034620, 141.368370),
    (@CourseId, N'南平岸',   13, 43.026660, 141.371343),
    (@CourseId, N'澄川',     14, 43.016825, 141.367360),
    (@CourseId, N'自衛隊前', 15, 43.006005, 141.364915),
    (@CourseId, N'真駒内',   16, 42.991180, 141.358545);
GO


/* ============================================================
   9. ルーム作成の例

   9.1 全線を通しで、通常のサイコロ
       麻生(1) → 真駒内(16) / DiceMax = 6
   9.2 一部区間を、小さいサイコロで
       さっぽろ(6) → 中の島(11) / DiceMax = 3
       6駅の区間を最大3で進む。ミッションの実施回数が増える
   9.3 逆方向
       真駒内(16) → 麻生(1) / DiceMax = 6
       Start の OrderNo > Goal の OrderNo なので、進む向きが反転する
   9.4 全駅でミッション
       麻生(1) → 真駒内(16) / DiceMax = 1
       毎ターン必ず1駅ずつ進むため、16駅すべてが着地駅になる
   ============================================================ */
/*
DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'南北線');

INSERT INTO dbo.MissionSet (CourseId, Name, InviteCode, StartStationId, GoalStationId, DiceMax)
VALUES (@CourseId, N'夏の南北線ツアー', N'ABC123',
        (SELECT StationId FROM dbo.Station WHERE CourseId=@CourseId AND OrderNo=1),
        (SELECT StationId FROM dbo.Station WHERE CourseId=@CourseId AND OrderNo=16),
        6);
*/


/* ============================================================
   10. 主要クエリ
   ============================================================ */

/* ------------------------------------------------------------
   10.0 ルームの設定値を取り出す（以降のクエリの前提）
   ------------------------------------------------------------ */
/*
DECLARE @MissionSetId UNIQUEIDENTIFIER = '...';

DECLARE @CourseId   INT, @DiceMax TINYINT, @StartOrder INT, @GoalOrder INT;
SELECT @CourseId   = ms.CourseId,
       @DiceMax    = ms.DiceMax,
       @StartOrder = ss.OrderNo,
       @GoalOrder  = gs.OrderNo
FROM dbo.MissionSet ms
JOIN dbo.Station ss ON ss.StationId = ms.StartStationId
JOIN dbo.Station gs ON gs.StationId = ms.GoalStationId
WHERE ms.MissionSetId = @MissionSetId;

-- 進む向き： +1 = OrderNo が増える方向 / -1 = 減る方向
DECLARE @Dir INT = CASE WHEN @GoalOrder > @StartOrder THEN 1 ELSE -1 END;
*/

/* ------------------------------------------------------------
   10.1 現在位置
   最後に完了したターンの EndStationId。1ターンも完了していなければ
   ルームの StartStationId。
   ※ ver.1 の「OrderNo が最大の着地駅」は、戻る効果があると成立しない。
   ------------------------------------------------------------ */
/*
SELECT TOP (1) s.StationId, s.Name, s.OrderNo
FROM dbo.Turn t
JOIN dbo.Station s ON s.StationId = t.EndStationId
WHERE t.MissionSetId = @MissionSetId AND t.EndStationId IS NOT NULL
ORDER BY t.TurnNo DESC;
-- 0件なら MissionSet.StartStationId が現在位置
*/

/* ------------------------------------------------------------
   10.2 進行中ターンの復元（アプリ再起動時）
   ver.1 では出目がDBに無く復元できなかった。ver.2 では Turn に残る。
   ------------------------------------------------------------ */
/*
SELECT t.TurnId, t.TurnNo, t.DiceValue,
       f.Name AS FromStation, f.OrderNo AS FromOrder,
       l.Name AS LandingStation, l.OrderNo AS LandingOrder,
       t.ArrivedAt, t.SelectedMissionId, t.MissionDone
FROM dbo.Turn t
JOIN dbo.Station f ON f.StationId = t.FromStationId
JOIN dbo.Station l ON l.StationId = t.LandingStationId
WHERE t.MissionSetId = @MissionSetId AND t.EndStationId IS NULL;

-- 未訪問の駅（＝どこまで歩いたか）は Visit との差分で分かる
SELECT s.StationId, s.Name, s.OrderNo
FROM dbo.Station s
WHERE s.CourseId = @CourseId
  AND (@Dir = 1  AND s.OrderNo > (SELECT OrderNo FROM dbo.Station WHERE StationId = @FromStationId)
                 AND s.OrderNo <= (SELECT OrderNo FROM dbo.Station WHERE StationId = @LandingStationId)
    OR @Dir = -1 AND s.OrderNo < (SELECT OrderNo FROM dbo.Station WHERE StationId = @FromStationId)
                 AND s.OrderNo >= (SELECT OrderNo FROM dbo.Station WHERE StationId = @LandingStationId))
  AND NOT EXISTS (SELECT 1 FROM dbo.Visit v WHERE v.TurnId = @TurnId AND v.StationId = s.StationId)
ORDER BY s.OrderNo * @Dir;
*/

/* ------------------------------------------------------------
   10.3 サイコロを振る → 着地駅と通り道駅を求める
   出目は 1〜DiceMax。ゴールを超えたらゴールでクランプ（R-04）。
   ------------------------------------------------------------ */
/*
DECLARE @Dice INT = 3;                       -- アプリ側で 1〜@DiceMax の乱数
DECLARE @CurrentOrder INT = ...;             -- 10.1 の結果、なければ @StartOrder
DECLARE @Raw INT = @CurrentOrder + @Dir * @Dice;
DECLARE @TargetOrder INT =
    CASE WHEN @Dir = 1 THEN (CASE WHEN @Raw > @GoalOrder THEN @GoalOrder ELSE @Raw END)
         ELSE               (CASE WHEN @Raw < @GoalOrder THEN @GoalOrder ELSE @Raw END) END;

-- 歩く順に、通り道駅と着地駅を返す（最終行が着地駅）
SELECT StationId, Name, OrderNo,
       CAST(CASE WHEN OrderNo = @TargetOrder THEN 1 ELSE 0 END AS BIT) AS IsLanding
FROM dbo.Station
WHERE CourseId = @CourseId
  AND (@Dir = 1  AND OrderNo >  @CurrentOrder AND OrderNo <= @TargetOrder
    OR @Dir = -1 AND OrderNo <  @CurrentOrder AND OrderNo >= @TargetOrder)
ORDER BY OrderNo * @Dir;

-- 振った時点で Turn を作る（これが進行中ターンになる）
INSERT INTO dbo.Turn (MissionSetId, TurnNo, FromStationId, DiceValue, LandingStationId)
SELECT @MissionSetId,
       ISNULL((SELECT MAX(TurnNo) FROM dbo.Turn WHERE MissionSetId = @MissionSetId), 0) + 1,
       @CurrentStationId, @Dice,
       (SELECT StationId FROM dbo.Station WHERE CourseId = @CourseId AND OrderNo = @TargetOrder);
*/

/* ------------------------------------------------------------
   10.4 着地駅のミッション抽選候補
   効果の列も一緒に取り、当たったものの効果を適用する。
   0件ならミッションを実行せずターンを完了させる。
   ------------------------------------------------------------ */
/*
SELECT m.MissionId, m.Content, mem.DisplayName AS CreatedByName,
       m.EffectType, m.EffectValue, m.EffectStationId,
       es.Name AS EffectStationName
FROM dbo.Mission m
JOIN dbo.Member mem ON mem.MemberId = m.MemberId
LEFT JOIN dbo.Station es ON es.StationId = m.EffectStationId
WHERE m.MissionSetId = @MissionSetId AND m.StationId = @LandingStationId;
*/

/* ------------------------------------------------------------
   10.5 ミッションの効果を適用した最終位置
   進む/戻るは区間の端でクランプする。ジャンプは指定駅そのもの。
   ------------------------------------------------------------ */
/*
DECLARE @LandingOrder INT = ...;   -- 着地駅の OrderNo
DECLARE @EffectType TINYINT, @EffectValue TINYINT, @EffectStationId INT;

DECLARE @EndOrder INT =
  CASE @EffectType
    WHEN 1 THEN  -- 進む（ゴール方向）
      CASE WHEN @Dir = 1
        THEN (CASE WHEN @LandingOrder + @EffectValue > @GoalOrder THEN @GoalOrder ELSE @LandingOrder + @EffectValue END)
        ELSE (CASE WHEN @LandingOrder - @EffectValue < @GoalOrder THEN @GoalOrder ELSE @LandingOrder - @EffectValue END) END
    WHEN 2 THEN  -- 戻る（スタート方向）
      CASE WHEN @Dir = 1
        THEN (CASE WHEN @LandingOrder - @EffectValue < @StartOrder THEN @StartOrder ELSE @LandingOrder - @EffectValue END)
        ELSE (CASE WHEN @LandingOrder + @EffectValue > @StartOrder THEN @StartOrder ELSE @LandingOrder + @EffectValue END) END
    WHEN 4 THEN  -- 指定駅へ移動
      (SELECT OrderNo FROM dbo.Station WHERE StationId = @EffectStationId)
    ELSE @LandingOrder   -- 0 = なし / 3 = もう一度振る（位置は動かない）
  END;

-- ターンを完了させる
UPDATE dbo.Turn
SET SelectedMissionId = @MissionId,
    MissionDone       = @Done,
    AppliedEffectType = @EffectType,
    EndStationId      = (SELECT StationId FROM dbo.Station WHERE CourseId=@CourseId AND OrderNo=@EndOrder),
    CompletedAt       = SYSUTCDATETIME()
WHERE TurnId = @TurnId;
*/

/* ------------------------------------------------------------
   10.6 盤面の表示
   区間内の駅だけを、進む向きに並べる。訪問回数も返す。
   ------------------------------------------------------------ */
/*
SELECT s.OrderNo, s.StationId, s.Name, s.Latitude, s.Longitude,
       vs.VisitCount,
       CAST(CASE WHEN vs.LandingCount > 0 THEN 1 ELSE 0 END AS BIT) AS EverLanded,
       (SELECT COUNT(*) FROM dbo.Mission m
         WHERE m.MissionSetId = @MissionSetId AND m.StationId = s.StationId) AS MissionCount
FROM dbo.Station s
OUTER APPLY (
    SELECT COUNT(*) AS VisitCount,
           SUM(CASE WHEN v.VisitKind = 2 THEN 1 ELSE 0 END) AS LandingCount
    FROM dbo.Visit v
    WHERE v.MissionSetId = @MissionSetId AND v.StationId = s.StationId
) vs
WHERE s.CourseId = @CourseId
  AND s.OrderNo BETWEEN (CASE WHEN @Dir=1 THEN @StartOrder ELSE @GoalOrder  END)
                    AND (CASE WHEN @Dir=1 THEN @GoalOrder  ELSE @StartOrder END)
ORDER BY s.OrderNo * @Dir;
*/

/* ------------------------------------------------------------
   10.7 達成率
   踏破率の分母は「区間内の駅数」。分子は重複を除いた訪問駅数。
   ------------------------------------------------------------ */
/*
SELECT
    (SELECT COUNT(*) FROM dbo.Station
      WHERE CourseId = @CourseId
        AND OrderNo BETWEEN (CASE WHEN @Dir=1 THEN @StartOrder ELSE @GoalOrder  END)
                        AND (CASE WHEN @Dir=1 THEN @GoalOrder  ELSE @StartOrder END))  AS RangeStations,
    (SELECT COUNT(DISTINCT StationId) FROM dbo.Visit
      WHERE MissionSetId = @MissionSetId)                                              AS VisitedStations,
    (SELECT COUNT(*) FROM dbo.Turn WHERE MissionSetId = @MissionSetId
        AND EndStationId IS NOT NULL)                                                  AS TurnCount,
    (SELECT COUNT(*) FROM dbo.Turn WHERE MissionSetId = @MissionSetId
        AND SelectedMissionId IS NOT NULL)                                             AS MissionPlayedCount,
    (SELECT COUNT(*) FROM dbo.Turn WHERE MissionSetId = @MissionSetId
        AND MissionDone = 1)                                                           AS MissionDoneCount;
*/

/* ------------------------------------------------------------
   10.8 準備状況 ── 区間内の駅ごとのミッション数と効果の内訳
   0件の駅は「着地しても何も起きない駅」になる
   ------------------------------------------------------------ */
/*
SELECT s.OrderNo, s.Name,
       COUNT(m.MissionId) AS MissionCount,
       SUM(CASE WHEN m.EffectType <> 0 THEN 1 ELSE 0 END) AS EffectCount
FROM dbo.Station s
LEFT JOIN dbo.Mission m ON m.StationId = s.StationId AND m.MissionSetId = @MissionSetId
WHERE s.CourseId = @CourseId
  AND s.OrderNo BETWEEN (CASE WHEN @Dir=1 THEN @StartOrder ELSE @GoalOrder  END)
                    AND (CASE WHEN @Dir=1 THEN @GoalOrder  ELSE @StartOrder END)
GROUP BY s.OrderNo, s.Name
ORDER BY s.OrderNo * @Dir;
*/

/* ------------------------------------------------------------
   10.9 クリア判定
   現在位置がゴール駅に達したか
   ------------------------------------------------------------ */
/*
SELECT CAST(CASE WHEN @CurrentStationId = @GoalStationId THEN 1 ELSE 0 END AS BIT) AS IsCleared;
*/


/* ============================================================
   11. 削除 / リセット
   MissionSet に CASCADE を張れないため、順序を決めて消す。
   ============================================================ */

/* ------------------------------------------------------------
   11.1 記録リセット（再挑戦）
   Photo は Visit の CASCADE で消える。Visit が Turn を参照するので Visit が先。
   ------------------------------------------------------------ */
/*
BEGIN TRAN;
    DELETE FROM dbo.Visit WHERE MissionSetId = @MissionSetId;   -- → Photo も消える
    DELETE FROM dbo.Turn  WHERE MissionSetId = @MissionSetId;
COMMIT;
*/

/* ------------------------------------------------------------
   11.2 ルームごと削除
   ------------------------------------------------------------ */
/*
BEGIN TRAN;
    DELETE FROM dbo.Visit    WHERE MissionSetId = @MissionSetId;   -- → Photo も消える
    DELETE FROM dbo.Turn     WHERE MissionSetId = @MissionSetId;   -- Mission より先（FK参照のため）
    DELETE FROM dbo.Schedule WHERE MissionSetId = @MissionSetId;   -- → ScheduleAttendee も消える
    DELETE FROM dbo.Mission  WHERE MissionSetId = @MissionSetId;
    UPDATE dbo.MissionSet SET CreatedBy = NULL WHERE MissionSetId = @MissionSetId;
    DELETE FROM dbo.Member     WHERE MissionSetId = @MissionSetId;
    DELETE FROM dbo.MissionSet WHERE MissionSetId = @MissionSetId;
COMMIT;
*/
