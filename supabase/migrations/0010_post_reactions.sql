-- ⑨ いいね/応援。投稿(feed_items)へのリアクション。本番には supabase db query で適用済み。
create table if not exists public.post_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_item_id uuid not null references public.feed_items(id) on delete cascade,
  kind text not null check (kind in ('like','cheer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, feed_item_id, kind)
);
create index if not exists post_reactions_feed_idx on public.post_reactions(feed_item_id);

alter table public.post_reactions enable row level security;
-- 参照: 見える投稿(本人/public/friends&フォロー)へのリアクションは見える。書込は本人のみ。
create policy post_reactions_select on public.post_reactions for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.feed_items f where f.id = feed_item_id
      and (f.user_id = auth.uid() or f.visibility = 'public'
           or (f.visibility = 'friends' and public.is_following(f.user_id))))
  );
create policy post_reactions_modify_own on public.post_reactions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
