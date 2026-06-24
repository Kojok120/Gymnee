-- 監査S: ブロックを RLS に連動（クライアント除外依存をやめ、サーバ側で被ブロックを遮断）。
-- 本番には supabase db query で適用済み（ここは履歴）。
create or replace function public.is_blocked(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = auth.uid() and blocked_id = other)
       or (blocker_id = other and blocked_id = auth.uid())
  );
$$;

drop policy if exists feed_items_select on public.feed_items;
create policy feed_items_select on public.feed_items for select to authenticated using (
  user_id = auth.uid()
  or (not public.is_blocked(user_id) and (visibility = 'public' or (visibility = 'friends' and public.is_following(user_id))))
);

drop policy if exists progress_photos_select on public.progress_photos;
create policy progress_photos_select on public.progress_photos for select to authenticated using (
  user_id = auth.uid()
  or (not public.is_blocked(user_id) and (visibility = 'public' or (visibility = 'friends' and public.is_following(user_id))))
);

-- プロフィールはブロック相手には不可視（自分は常に可視）。
drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_all on public.profiles for select to authenticated using (
  id = auth.uid() or not public.is_blocked(id)
);
