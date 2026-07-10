-- 匿名（is_anonymous）ユーザーの公開系書き込みを RLS で禁止する。
--
-- 背景: 匿名認証（Phase 2・docs/identity-environment-design.md）でゲストにも安定 uid を発行し
-- 記録を同期するが、公開フィード・ソーシャル操作は本人性のあるアカウント限定とする。
--   - ゲスト/デモ由来のデータが公開フィードへ露出する事故（2026-07-10 の dev データ混入と同種）の二重防御
--   - 匿名の使い捨てアカウントによるスパム・荒らしの抑止
--
-- restrictive policy は既存の permissive policy と AND 結合されるため、既存の所有チェックは
-- そのまま生きる。select は制限しない（匿名でも公開フィードの閲覧は可）。
-- JWT の is_anonymous claim で判定する（クレームが無い旧トークンは非匿名として扱う）。

create or replace function public.is_anonymous_user()
returns boolean
language sql stable as $$
    select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
$$;

-- 公開フィードへの投稿は本登録のみ（friends/private の同期は匿名でも可）。
drop policy if exists feed_items_no_anonymous_public on public.feed_items;
create policy feed_items_no_anonymous_public on public.feed_items
    as restrictive for insert to authenticated
    with check (not (public.is_anonymous_user() and visibility = 'public'));
drop policy if exists feed_items_no_anonymous_public_update on public.feed_items;
create policy feed_items_no_anonymous_public_update on public.feed_items
    as restrictive for update to authenticated
    with check (not (public.is_anonymous_user() and visibility = 'public'));

-- フォロー・リアクション・コメントは本登録のみ。
drop policy if exists follows_no_anonymous on public.follows;
create policy follows_no_anonymous on public.follows
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
drop policy if exists post_reactions_no_anonymous on public.post_reactions;
create policy post_reactions_no_anonymous on public.post_reactions
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
drop policy if exists comments_no_anonymous on public.comments;
create policy comments_no_anonymous on public.comments
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
