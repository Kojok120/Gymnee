-- 0027: ワークアウト総合時間（秒）を workouts に追加
-- 完了時にライブ経過から確定、またはユーザーが手動で登録/修正する。
-- null は未計測（過去日の後追い記録など）。負値が同期 payload 経由で複製されるのを防ぐ。
alter table public.workouts add column if not exists duration_seconds integer;
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'workouts_duration_seconds_non_negative'
  ) then
    alter table public.workouts
      add constraint workouts_duration_seconds_non_negative
      check (duration_seconds is null or duration_seconds >= 0);
  end if;
end $$;
