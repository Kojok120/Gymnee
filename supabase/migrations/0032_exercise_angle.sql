-- 0032: セット単位の角度記録（issue #44）
--
-- 角度は重量と同じく「セットごとの変数」として扱う（デクラインシットアップ等を別種目に
-- しない）。角度軸の表示は履歴ベースではなく「種目で決まる軸」にするため、種目に has_angle
-- 属性を持たせ、対象種目では記録画面に角度ルーラー（0〜60°・5°刻み）を常時表示する。
--
-- 内容:
--   (1) exercises.has_angle boolean（既定 false）を追加。
--   (2) exercise_sets.angle_degrees smallint（nullable・0〜60 の check）を追加。
--   (3) プリセットマスタ（created_by IS NULL）の シットアップ/クランチ/レッグレイズ を has_angle=true に。
-- 冪等: 列追加は if not exists、(3) は has_angle=false の行だけ更新する。
alter table public.exercises add column if not exists has_angle boolean not null default false;
alter table public.exercise_sets add column if not exists angle_degrees smallint;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'exercise_sets_angle_degrees_range'
  ) then
    alter table public.exercise_sets
      add constraint exercise_sets_angle_degrees_range
      check (angle_degrees is null or (angle_degrees >= 0 and angle_degrees <= 60));
  end if;
end $$;

update public.exercises
  set has_angle = true, updated_at = now()
  where is_custom = false and created_by is null
    and name in ('シットアップ', 'クランチ', 'レッグレイズ')
    and has_angle = false;
