-- プリセット種目のサーバーマスタ化（created_by IS NULL・決定的id）。
--
-- 背景: クライアントの起動時 backfill が全プリセットを created_by=自分 で push していたため、
-- 最初のユーザーがプリセット43件を「所有」し、2人目以降の同 id upsert（決定的idで全端末同一）が
-- RLS(exercises_update_own) で拒否（42501）→ outbox に永久滞留していた。
-- 本migrationでプリセットをマスタ行（created_by IS NULL）へ収束し、クライアント側は
-- is_custom=true のみ push する（SwiftDataSyncStore.payload / AppEnvironment.backfill）。
--
-- 内容:
--   (1) 43プリセットを決定的id（uuid_generate_v5・SeedData.presetId と同値）で upsert。
--       既存の所有付き同id行は in-place でマスタへ収束（created_by=null / 属性を正準値へ）。
--   (2) 同名の非マスタ・プリセット行（旧ランダムid）から参照を付け替えて削除（0029と同パターン）。
--       ユーザー作成（is_custom=true）の同名行には触れない。
-- 冪等: 再実行しても (1) の updated_at が進む以外は無影響。

create extension if not exists "uuid-ossp";

do $$
declare
  ns constant uuid := '1b671a64-40d5-491e-99b0-da01ff1f3341';
  cid uuid;
  p record;
begin
  for p in
    select * from (values
      -- 胸
      ('ベンチプレス',             'chest',     'barbell',    'weight',     'both',    'none'),
      ('インクラインベンチプレス', 'chest',     'barbell',    'weight',     'both',    'none'),
      ('ダンベルプレス',           'chest',     'dumbbell',   'weight',     'perSide', 'none'),
      ('チェストプレス',           'chest',     'machine',    'weight',     'none',    'none'),
      ('ペックフライ',             'chest',     'machine',    'weight',     'none',    'none'),
      ('スミスマシンベンチプレス', 'chest',     'machine',    'weight',     'both',    'none'),
      ('ディップス',               'chest',     'bodyweight', 'bodyweight', 'none',    'assisted'),
      -- 背中
      ('デッドリフト',             'back',      'barbell',    'weight',     'both',    'none'),
      ('ベントオーバーロウ',       'back',      'barbell',    'weight',     'both',    'none'),
      ('ラットプルダウン',         'back',      'cable',      'weight',     'none',    'none'),
      ('シーテッドロウ',           'back',      'cable',      'weight',     'none',    'none'),
      ('懸垂',                     'back',      'bodyweight', 'bodyweight', 'none',    'assisted'),
      -- 脚
      ('スクワット',               'legs',      'barbell',    'weight',     'both',    'none'),
      ('スミスマシンスクワット',   'legs',      'machine',    'weight',     'both',    'none'),
      ('レッグプレス',             'legs',      'machine',    'weight',     'none',    'none'),
      ('レッグエクステンション',   'legs',      'machine',    'weight',     'none',    'none'),
      ('レッグカール',             'legs',      'machine',    'weight',     'none',    'none'),
      ('ルーマニアンデッドリフト', 'legs',      'barbell',    'weight',     'both',    'none'),
      ('カーフレイズ',             'legs',      'machine',    'weight',     'none',    'none'),
      -- 肩
      ('ショルダープレス',         'shoulders', 'machine',    'weight',     'none',    'none'),
      ('ダンベルショルダープレス', 'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('スミスマシンショルダープレス', 'shoulders', 'machine', 'weight',    'both',    'none'),
      ('サイドレイズ',             'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('リアレイズ',               'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('アップライトロウ',         'shoulders', 'barbell',    'weight',     'both',    'none'),
      -- 腕
      ('バーベルカール',           'arms',      'barbell',    'weight',     'both',    'none'),
      ('ダンベルカール',           'arms',      'dumbbell',   'weight',     'perSide', 'none'),
      ('ハンマーカール',           'arms',      'dumbbell',   'weight',     'perSide', 'none'),
      ('トライセプスプレスダウン', 'arms',      'cable',      'weight',     'none',    'none'),
      ('スカルクラッシャー',       'arms',      'barbell',    'weight',     'both',    'none'),
      -- 腹
      ('クランチ',                 'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('シットアップ',             'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('レッグレイズ',             'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('ケーブルクランチ',         'abs',       'cable',      'weight',     'none',    'none'),
      ('アブローラー',             'abs',       'other',      'bodyweight', 'none',    'none'),
      -- 体幹
      ('プランク',                 'core',      'bodyweight', 'time',       'none',    'none'),
      -- 臀部
      ('ヒップスラスト',           'glutes',    'barbell',    'weight',     'none',    'none'),
      -- 全身
      ('バーピー',                 'full_body', 'bodyweight', 'bodyweight', 'none',    'none'),
      ('ケトルベルスイング',       'full_body', 'kettlebell', 'weight',     'none',    'none'),
      ('クリーン&ジャーク',        'full_body', 'barbell',    'weight',     'both',    'none'),
      -- 有酸素
      ('ウォーキング',             'cardio',    'other',      'cardio',     'none',    'none'),
      ('ランニング',               'cardio',    'other',      'cardio',     'none',    'none'),
      ('バイシクル',               'cardio',    'other',      'cardio',     'none',    'none')
    ) as v(name, muscle_group, equipment, measurement_type, weight_mode, load_mode)
  loop
    cid := uuid_generate_v5(ns, p.name);

    -- (1) マスタ行を upsert。既存の所有付き同id行も in-place でマスタへ収束する。
    insert into public.exercises
      (id, name, muscle_group, equipment, is_custom, created_by,
       weight_mode, measurement_type, load_mode, updated_at)
    values
      (cid, p.name, p.muscle_group, p.equipment, false, null,
       p.weight_mode, p.measurement_type, p.load_mode, now())
    on conflict (id) do update
      set created_by       = null,
          is_custom        = false,
          name             = excluded.name,
          muscle_group     = excluded.muscle_group,
          equipment        = excluded.equipment,
          weight_mode      = excluded.weight_mode,
          measurement_type = excluded.measurement_type,
          load_mode        = excluded.load_mode,
          updated_at       = now();

    -- (2) 同名の非マスタ・プリセット行（旧ランダムid）→ 参照を付け替えて削除。
    --     ユーザー作成（is_custom=true）は対象外。
    update public.workout_exercises w set exercise_id = cid
      from public.exercises e
      where w.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    update public.personal_records pr set exercise_id = cid
      from public.exercises e
      where pr.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    update public.routine_exercises rr set exercise_id = cid
      from public.exercises e
      where rr.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    delete from public.exercises e
      where e.name = p.name and e.id <> cid and e.is_custom = false;
  end loop;
end $$;
