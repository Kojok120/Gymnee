-- 0024: exercise_sets.distance_km に下限制約（負の距離を禁止）
-- 距離は 0 以上のみ許可する。負値が同期 payload 経由で全端末へ複製されるのを防ぐ。
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'exercise_sets_distance_km_non_negative'
  ) then
    alter table public.exercise_sets
      add constraint exercise_sets_distance_km_non_negative
      check (distance_km is null or distance_km >= 0);
  end if;
end $$;
