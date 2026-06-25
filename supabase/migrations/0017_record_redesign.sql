-- 0017_record_redesign.sql
-- 記録リデザイン（タップ式）。種目の計測タイプと、時間種目の継続秒数を追加する。
-- 旧列 rpe/rir/type/weight_mode_override/superset_group はアプリから書き込まれなくなるが、
-- 互換のため残置する（exercise_sets.type は NOT NULL default 'normal' のまま）。
-- 適用: supabase db push（または supabase db query でこのファイルを実行）。

alter table public.exercises
  add column if not exists measurement_type text not null default 'weight';

alter table public.exercise_sets
  add column if not exists duration_seconds integer;
