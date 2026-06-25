-- ③ マルチリアクション（筋トレ絵文字）＋ 公開コメント
-- 公開投稿(feed_items)への反応/コメント。1対1の私信(DM)ではない＝「オープンな場」。

-- 1) リアクション種別を like のみ → like/strong/fire/clap に拡張（0015 の制約を付け替え）。
--    クライアントは 1ユーザー1投稿1種別（付け替えは旧削除＋新規）なので unique(user,feed,kind) は維持で衝突しない。
alter table public.post_reactions drop constraint if exists post_reactions_kind_check;
alter table public.post_reactions add constraint post_reactions_kind_check
  check (kind in ('like','strong','fire','clap'));

-- 2) 公開コメント。可視な feed_item にのみ付与でき、参照可否は post_reactions と同条件
--    （本人 / public / friends かつフォロー中）。書込は本人のみ。
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_item_id uuid not null references public.feed_items(id) on delete cascade,
  author_display_name text,
  text text not null check (char_length(text) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists comments_feed_idx on public.comments(feed_item_id, created_at);

alter table public.comments enable row level security;

create policy comments_select on public.comments for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.feed_items f
      where f.id = feed_item_id
        and (f.user_id = auth.uid()
             or f.visibility = 'public'
             or (f.visibility = 'friends' and public.is_following(f.user_id)))
    )
  );

create policy comments_modify_own on public.comments for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
