-- 応援(cheer)を廃止し、いいね(like)のみにする（ユーザー要望）。
-- 既存の cheer 行を削除し、CHECK 制約を like のみに付け替える。
delete from public.post_reactions where kind = 'cheer';

alter table public.post_reactions drop constraint if exists post_reactions_kind_check;
alter table public.post_reactions add constraint post_reactions_kind_check check (kind in ('like'));
