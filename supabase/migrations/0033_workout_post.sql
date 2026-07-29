-- 0033: チェックイン廃止に伴い、投稿の写真とコメントを workouts に持たせる
-- 旧: チェックイン(visits)が写真を持ち、ワークアウトは数値だけだった。
-- 新: 記録が唯一の活動単位なので、投稿に添える写真(photo_url)とコメント(caption)を workouts に置く。
-- photo_url は "workout-photos/<uid>/<file>" 形式のストレージ参照（0034 でバケットを作る）。
-- caption は公開コメント（note は自分用メモで別列）。comments と同じ 500 文字上限に揃える。
alter table public.workouts add column if not exists photo_url text;
alter table public.workouts add column if not exists caption text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'workouts_caption_length'
  ) then
    alter table public.workouts
      add constraint workouts_caption_length
      check (caption is null or char_length(caption) <= 500);
  end if;
end $$;
