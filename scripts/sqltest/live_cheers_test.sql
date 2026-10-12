-- ライブ中の応援を投稿の応援へ引き継ぐ（0044・issue #148）の検証シナリオ。
-- 使い方: bash scripts/sqltest/run.sh supabase/migrations/0013_push_on_reaction.sql supabase/migrations/0044_live_cheers_to_post.sql scripts/sqltest/live_cheers_test.sql
create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
insert into auth.users select pg_temp.u(i) from generate_series(1, 9) i;

create function pg_temp.reactions(item uuid) returns text language sql as $$
  select coalesce(string_agg(right(user_id::text, 1) || ':' || kind, ',' order by user_id), '')
  from public.post_reactions where feed_item_id = item
$$;
create function pg_temp.reaction_pushes() returns int language sql as $$
  select count(*)::int from net.calls where body->>'event' = 'reaction'
$$;

do $$
declare
  w1 uuid := gen_random_uuid();  -- ライブ中に記録していたワークアウト
  w2 uuid := gen_random_uuid();  -- 別のワークアウト
  s1 uuid; s2 uuid; s0 uuid; f1 uuid; fpr uuid; pushes int;
begin
  insert into public.live_sessions(user_id, workout_id) values (pg_temp.u(1), w1) returning id into s1;
  insert into public.live_sessions(user_id, workout_id) values (pg_temp.u(1), w2) returning id into s2;
  insert into public.live_sessions(user_id) values (pg_temp.u(1)) returning id into s0;  -- 古いアプリ（workout_id 無し）
  insert into public.blocks(blocker_id, blocked_id) values (pg_temp.u(1), pg_temp.u(5));

  -- 投稿前のライブ中の応援。2 は2種類（最後の clap を写す）、5 はブロック、4 は別のワークアウト、6 は workout_id 無し。
  insert into public.session_cheers(session_id, user_id, kind, created_at) values
    (s1, pg_temp.u(2), 'fire', now() - interval '30 minutes'),
    (s1, pg_temp.u(2), 'clap', now() - interval '20 minutes'),
    (s1, pg_temp.u(3), 'strong', now() - interval '25 minutes'),
    (s1, pg_temp.u(5), 'fire', now() - interval '15 minutes'),
    (s2, pg_temp.u(4), 'fire', now() - interval '10 minutes'),
    (s0, pg_temp.u(6), 'fire', now() - interval '5 minutes');
  assert (select count(*) from public.post_reactions) = 0, '投稿前に応援ができた';

  -- 1. 投稿（feed_item）ができたら、そのワークアウトのライブ中の応援を写す。
  pushes := pg_temp.reaction_pushes();
  insert into public.feed_items(user_id, type, ref_id) values (pg_temp.u(1), 'workout', w1) returning id into f1;
  assert pg_temp.reactions(f1) = '2:clap,3:strong', '写した応援が違う: ' || pg_temp.reactions(f1);
  assert pg_temp.reaction_pushes() = pushes, '写した応援で通知が飛んだ';
  assert (select bool_and(updated_at > now() - interval '1 minute') from public.post_reactions where feed_item_id = f1),
    'updated_at が写した時刻でない（他の端末に届かない）';
  assert (select created_at from public.post_reactions where feed_item_id = f1 and user_id = pg_temp.u(3))
    < now() - interval '24 minutes', 'created_at が応援した時刻でない';

  -- 2. 自分で応援するのは今までどおり通知される（写し終えたあとは印が戻っている）。
  insert into public.post_reactions(user_id, feed_item_id, kind) values (pg_temp.u(7), f1, 'like');
  assert pg_temp.reaction_pushes() = pushes + 1, '普通の応援の通知が飛ばない';

  -- 3. 投稿のあとに届いたライブの応援も写す。すでに投稿へ応援している人（7）には写さない。
  insert into public.session_cheers(session_id, user_id, kind) values (s1, pg_temp.u(8), 'strong');
  insert into public.session_cheers(session_id, user_id, kind) values (s1, pg_temp.u(7), 'fire');
  assert pg_temp.reactions(f1) = '2:clap,3:strong,7:like,8:strong', '投稿後の応援の写し方が違う: ' || pg_temp.reactions(f1);
  assert pg_temp.reaction_pushes() = pushes + 1, '投稿後に写した応援で通知が飛んだ';

  -- 4. 記録の投稿だけが対象。同じワークアウトの自己ベスト投稿（type='pr'）には写さない。
  insert into public.feed_items(user_id, type, ref_id) values (pg_temp.u(1), 'pr', w1) returning id into fpr;
  assert pg_temp.reactions(fpr) = '', '自己ベストの投稿に写った';

  -- 5. 非公開にして（feed_item を消して）また公開しても、もう一度写る。
  delete from public.feed_items where id = f1;
  insert into public.feed_items(id, user_id, type, ref_id) values (f1, pg_temp.u(1), 'workout', w1);
  assert pg_temp.reactions(f1) = '2:clap,3:strong,7:fire,8:strong', '公開し直したときの写し方が違う: ' || pg_temp.reactions(f1);

  -- 6. 写す関数はアプリから呼べない（投稿の応援を作れてしまう）。
  assert not has_function_privilege('authenticated', 'public.copy_live_cheers_to_post(uuid, uuid, uuid)', 'execute'),
    'copy_live_cheers_to_post をアプリから呼べる';

  raise notice 'live_cheers_test: ALL PASSED';
end $$;
