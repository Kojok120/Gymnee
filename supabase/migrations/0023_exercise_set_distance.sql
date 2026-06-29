-- 0023: 有酸素種目（cardio）の距離km を exercise_sets に追加
-- ランニング/ウォーキング/バイシクル等は「距離km ＋ 時間（duration_seconds に分×60で保存）」で記録する。
alter table public.exercise_sets add column if not exists distance_km double precision;
