-- 週ボスの戦闘（0043: 連携・ジョブ・攻撃の一覧・見た目・トレ中・あと1撃）の検証シナリオ。
-- 使い方: bash scripts/sqltest/run.sh supabase/migrations/004{0,1,2,3}_*.sql scripts/sqltest/boss_battle_test.sql
-- 期待値はアプリの PartyBossBattleTests（同じシナリオ）と揃える。
grant usage on schema public, auth, net to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated;

create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
insert into auth.users select pg_temp.u(i) from generate_series(1, 12) i;
insert into public.profiles(id, display_name) select pg_temp.u(i), 'U' || i from generate_series(1, 12) i;

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('test.uid', pg_temp.u(n)::text, false)
$$;
-- 状況のメンバーを ID で引く（同じトランザクションで参加すると joined_at が揃い、並びが決まらない）。
create function pg_temp.member(s json, n int) returns json language sql as $$
  select m from json_array_elements(s->'members') m where m->>'user_id' = pg_temp.u(n)::text
$$;
-- 系統つきのワークアウトを1回完了したことにする（系統ごとに完了セットを2つ）。
create function pg_temp.workout(n int, at timestamptz, groups text[] default '{}') returns uuid language plpgsql as $$
declare wid uuid; g text; ex uuid; we uuid;
begin
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(n), at) returning id into wid;
  foreach g in array groups loop
    insert into public.exercises(muscle_group) values (g) returning id into ex;
    insert into public.workout_exercises(workout_id, exercise_id) values (wid, ex) returning id into we;
    insert into public.exercise_sets(workout_exercise_id, is_completed) values (we, true), (we, true);
  end loop;
  return wid;
end $$;

do $$
declare
  ws timestamptz := '2026-09-28 00:00+09';  -- 月曜
  p uuid; q uuid; r uuid; w uuid; b_mon uuid; s json; atk json; failed boolean;
begin
  -- 1. 系統: 完了セットが一番多い系統。種目が無ければ全身。セットが無ければ種目の数
  w := pg_temp.workout(12, '2026-09-01 10:00+09', array['chest', 'chest', 'legs']);
  assert public.party_workout_category(w) = 'upper', '胸2種目 > 脚1種目なら上半身';
  w := pg_temp.workout(12, '2026-09-01 11:00+09');
  assert public.party_workout_category(w) = 'full', '種目が無ければ全身';
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(12), '2026-09-01 12:00+09') returning id into w;
  insert into public.exercises(muscle_group) values ('cardio');
  insert into public.workout_exercises(workout_id, exercise_id)
    select w, id from public.exercises where muscle_group = 'cardio' limit 1;
  insert into public.workout_exercises(workout_id, exercise_id)
    select w, id from public.exercises where muscle_group = 'cardio' limit 1;
  insert into public.workout_exercises(workout_id, exercise_id)
    select w, id from public.exercises where muscle_group = 'legs' limit 1;
  assert public.party_workout_category(w) = 'cardio', 'セットが無ければ種目の数で決める';
  delete from public.workouts where user_id = pg_temp.u(12);

  -- 2. ジョブ: 週の頭より前の28日間で半分を超える系統。無ければ勇者
  perform pg_temp.workout(1, '2026-09-10 10:00+09', array['chest']);
  perform pg_temp.workout(1, '2026-09-15 10:00+09', array['back']);
  perform pg_temp.workout(1, '2026-09-20 10:00+09', array['arms']);
  perform pg_temp.workout(2, '2026-09-10 10:00+09', array['legs']);
  perform pg_temp.workout(2, '2026-09-12 10:00+09', array['glutes']);
  perform pg_temp.workout(2, '2026-09-14 10:00+09', array['chest']);
  perform pg_temp.workout(3, '2026-09-10 10:00+09', array['cardio']);
  perform pg_temp.workout(3, '2026-09-11 10:00+09', array['cardio']);
  perform pg_temp.workout(3, '2026-09-12 10:00+09', array['abs']);
  perform pg_temp.workout(3, '2026-09-13 10:00+09', array['core']);
  perform pg_temp.workout(5, '2026-09-21 10:00+09', array['cardio']);
  perform pg_temp.workout(6, '2026-09-21 10:00+09', array['abs']);
  perform pg_temp.workout(6, '2026-09-22 10:00+09', array['core']);
  perform pg_temp.workout(6, '2026-09-23 10:00+09', array['chest']);
  -- 28日より前と、週に入ってからの記録はジョブに数えない
  perform pg_temp.workout(5, '2026-08-01 10:00+09', array['legs']);
  perform pg_temp.workout(5, '2026-08-02 10:00+09', array['legs']);
  assert public.party_member_job(pg_temp.u(1), ws) = 'warrior', 'A は上半身3/3で戦士';
  assert public.party_member_job(pg_temp.u(2), ws) = 'monk', 'B は下半身2/3で武闘家';
  assert public.party_member_job(pg_temp.u(3), ws) = 'hero', 'C は有酸素2・体幹2で半分を超えないので勇者';
  assert public.party_member_job(pg_temp.u(4), ws) = 'hero', '記録が無ければ勇者';
  assert public.party_member_job(pg_temp.u(5), ws) = 'thief', 'E は有酸素1/1で盗賊（28日より前の脚は数えない）';
  assert public.party_member_job(pg_temp.u(6), ws) = 'priest', 'F は体幹2/3で僧侶';

  -- 3. パーティ P: A（戦士・目標2）・B（武闘家・目標2）・C（勇者・目標3）。HP = 7
  perform pg_temp.as_user(1); p := public.create_party(2);
  perform pg_temp.as_user(2); perform public.join_party(p, 2);
  perform pg_temp.as_user(3); perform public.join_party(p, 3);
  perform pg_temp.workout(1, '2026-09-28 08:00+09', array['chest']);        -- A 月
  b_mon := pg_temp.workout(2, '2026-09-28 20:00+09', array['legs']);        -- B 月 → 連携
  perform pg_temp.workout(2, '2026-09-29 07:00+09', array['legs']);         -- B 火 → 連撃
  perform pg_temp.workout(3, '2026-09-30 12:00+09', array['cardio']);       -- C 水
  perform pg_temp.workout(1, '2026-10-03 10:00+09', array['back']);         -- A 土 → 底力
  perform pg_temp.workout(1, '2026-10-04 10:00+09', array['arms']);         -- A 日（3回目＝上限）
  perform pg_temp.workout(1, '2026-10-04 11:00+09', array['arms']);         -- A 日（4回目＝上限超え）

  perform pg_temp.as_user(1);
  s := public.party_status(p, ws);
  atk := s->'attacks';
  assert json_array_length(atk) = 7, '攻撃は7回: ' || atk;
  -- 並びは完了順。時刻は返さない（日付だけ）
  assert (atk->0)->>'day' = '2026-09-28' and (atk->0)->>'completed_at' is null, '日付だけを返す: ' || (atk->0);
  assert (atk->0)->>'category' = 'upper' and (atk->1)->>'category' = 'lower' and (atk->3)->>'category' = 'cardio', '系統';
  assert (atk->1)->>'id' = md5(b_mon::text), 'id はワークアウトの md5';
  -- 内訳: [A月 base] [B月 base+combo] [B火 base+skill] [C水 base] [A土 base+skill] [A日 base] [A日 上限超え]
  assert ((atk->0)->>'base')::int = 1 and ((atk->0)->>'combo')::int = 0 and ((atk->0)->>'skill')::int = 0, 'A月: ' || (atk->0);
  assert ((atk->1)->>'combo')::int = 1 and ((atk->1)->>'skill')::int = 0, 'B月は連携: ' || (atk->1);
  assert ((atk->2)->>'skill')::int = 1 and ((atk->2)->>'combo')::int = 0, 'B火は連撃: ' || (atk->2);
  assert ((atk->3)->>'skill')::int = 0, 'C は目標3に届かないので勇気なし';
  assert ((atk->4)->>'skill')::int = 1, 'A土は底力: ' || (atk->4);
  assert ((atk->5)->>'skill')::int = 0 and ((atk->5)->>'base')::int = 1, 'A日はスキル済み・上限内';
  assert ((atk->6)->>'base')::int = 0, 'A の4回目は上限超え: ' || (atk->6);
  -- 合計: 基本 6 + 連携 1 + スキル 2 = 9 ≥ HP 7
  assert (s->>'hp')::int = 7 and (s->>'damage')::int = 9 and (s->>'defeated')::bool, '合計9で撃破: ' || s;
  assert pg_temp.member(s, 1)->>'job' = 'warrior' and pg_temp.member(s, 2)->>'job' = 'monk'
     and pg_temp.member(s, 3)->>'job' = 'hero', 'メンバーのジョブ';
  assert (pg_temp.member(s, 1)->>'hits')::int = 4, 'hits は生の回数のまま';
  -- 「この1回の前」: B の月曜を除くと、連携も B の連撃も消える（基本 5 + 底力 1）
  assert public.party_damage(p, ws, b_mon) = 6, 'B月を除いたダメージ: ' || public.party_damage(p, ws, b_mon);

  -- 4. パーティ Q: E（盗賊・目標1）・F（僧侶・目標1）。HP = 2
  perform pg_temp.as_user(5); q := public.create_party(1);
  perform pg_temp.as_user(6); perform public.join_party(q, 1);
  perform pg_temp.workout(5, '2026-09-29 09:00+09', array['cardio']);  -- E 火 → 先制
  perform pg_temp.workout(5, '2026-10-01 09:00+09', array['cardio']);  -- E 木（2回目＝上限）
  perform pg_temp.workout(6, '2026-10-01 18:00+09', array['abs']);     -- F 木 → 連携 + 祈り
  s := public.party_status(q, ws);
  atk := s->'attacks';
  assert ((atk->0)->>'skill')::int = 1, 'E火は先制: ' || atk;
  assert ((atk->1)->>'skill')::int = 0 and ((atk->1)->>'combo')::int = 0, 'E木は先に来たので連携は F に付く';
  assert ((atk->2)->>'combo')::int = 1 and ((atk->2)->>'skill')::int = 1, 'F木は連携 + 祈り: ' || (atk->2);
  assert (s->>'damage')::int = 6, 'Q の合計（基本3 + 先制1 + 連携1 + 祈り1）: ' || s;

  -- 5. ソロの R: D（勇者・目標2）。2回目で勇気。僧侶の祈りは仲間がいないと起きない
  perform pg_temp.as_user(4); r := public.create_party(2);
  perform pg_temp.workout(4, '2026-09-28 09:00+09');
  perform pg_temp.workout(4, '2026-09-28 19:00+09');
  s := public.party_status(r, ws);
  assert (s->>'damage')::int = 3 and (((s->'attacks')->1)->>'skill')::int = 1, '勇者は目標の回数目で +1: ' || s;

  -- 6. 見た目: 本人だけが載せられ、形と大きさを検証する。仲間の状況に載る
  perform pg_temp.as_user(1);
  perform public.set_character_look('{"v":1,"skin":"sunset","stage":2}'::jsonb);
  s := public.party_status(p, ws);
  assert (pg_temp.member(s, 1)->'look')->>'skin' = 'sunset', '見た目が載らない: ' || s;
  failed := false; begin perform public.set_character_look('[1,2]'::jsonb); exception when others then failed := true; end;
  assert failed, '配列の見た目を受け付けた';
  failed := false;
  begin perform public.set_character_look(jsonb_build_object('pad', repeat('x', 2000))); exception when others then failed := true; end;
  assert failed, '大きすぎる見た目を受け付けた';
  failed := false;
  begin update public.profiles set character_look = '"x"'::jsonb where id = pg_temp.u(2); exception when others then failed := true; end;
  assert failed, '列の制約が効いていない';
  perform public.set_character_look(null);
  assert (select character_look from public.profiles where id = pg_temp.u(1)) is null, 'null で消せない';

  -- 7. トレ中: 本人か、フォローしている相手の生きている配信だけ見える
  insert into public.live_sessions(user_id) values (pg_temp.u(2));
  insert into public.live_sessions(user_id, started_at) values (pg_temp.u(3), now() - interval '4 hours');
  insert into public.follows values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(1), pg_temp.u(3));
  perform pg_temp.as_user(1);
  s := public.party_status(p, ws);
  assert pg_temp.member(s, 2)->>'live_session_id' is not null, 'フォロー中の B のトレ中が見えない: ' || s;
  assert pg_temp.member(s, 3)->>'live_session_id' is null, '期限切れの配信が見えた';
  perform pg_temp.as_user(3);
  s := public.party_status(p, ws);
  assert pg_temp.member(s, 2)->>'live_session_id' is null, 'フォローしていない B のトレ中が見えた';
  perform pg_temp.as_user(2);
  s := public.party_status(p, ws);
  assert pg_temp.member(s, 2)->>'live_session_id' is not null, '自分のトレ中が見えない';
  update public.live_sessions set ended_at = now() where user_id = pg_temp.u(2);
  perform pg_temp.as_user(1);
  assert pg_temp.member(public.party_status(p, ws), 2)->>'live_session_id' is null, '終わった配信が見えた';

  raise notice 'boss_battle_test: ALL PASSED';
end $$;

-- 8. 通知（いまの週）。G（目標3）・H（目標4）は記録が無いので勇者。HP = 7
do $$
declare pid uuid; solo uuid;
begin
  perform pg_temp.as_user(7); pid := public.create_party(3);
  perform pg_temp.as_user(8); perform public.join_party(pid, 4);
  perform pg_temp.as_user(9); solo := public.create_party(1);
  delete from net.calls;
  -- G が3回: 基本3 + 勇気1 = 4（残り3）
  for i in 1..3 loop insert into public.workouts(user_id, completed_at) values (pg_temp.u(7), now()); end loop;
  assert (select count(*) from net.calls) = 0, 'まだ何も送らない';
  -- H の1回: 基本1 + 連携1 = 6（残り1）→ あと1撃を G へ
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(8), now());
  assert (select count(*) from net.calls where body->>'event' = 'boss_reach') = 1, 'あと1撃が送られない';
  assert (select body->>'attackerId' from net.calls where body->>'event' = 'boss_reach') = pg_temp.u(8)::text;
  assert exists (select 1 from public.party_reach_notices where party_id = pid), '送った記録が無い';
  -- H の2回目で撃破。あと1撃は二度送らない
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(8), now());
  assert (select count(*) from net.calls where body->>'event' = 'boss_defeated' and body->>'partyId' = pid::text) = 1, '撃破が送られない';
  assert (select count(*) from net.calls where body->>'event' = 'boss_reach') = 1, 'あと1撃を二度送った';
  -- 撃破後の攻撃では何も送らない
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(7), now());
  assert (select count(*) from net.calls) = 2, '撃破後に送った';
  -- 1人パーティ（目標1 → HP1）は撃破も、あと1撃も送らない
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(9), now());
  assert (select count(*) from net.calls) = 2, '1人パーティに送った';
  raise notice 'boss_battle_test notify: ALL PASSED';
end $$;

-- 9. 権限（authenticated として）。内部の集計関数は呼べない。見た目は自分で載せられる
select pg_temp.as_user(1);
set role authenticated;
do $$ declare failed boolean; begin
  failed := false;
  begin perform public.party_attacks('00000000-0000-0000-0000-000000000001'::uuid, now()); exception when insufficient_privilege then failed := true; end;
  assert failed, 'party_attacks を呼べた';
  failed := false;
  begin perform public.party_member_job('00000000-0000-0000-0000-000000000001'::uuid, now()); exception when insufficient_privilege then failed := true; end;
  assert failed, 'party_member_job を呼べた';
  failed := false;
  begin perform public.party_workout_category(gen_random_uuid()); exception when insufficient_privilege then failed := true; end;
  assert failed, 'party_workout_category を呼べた';
  assert (select count(*) from public.party_reach_notices) = 0, '通知の記録が見えた';
  raise notice 'boss_battle_test RLS: ALL PASSED';
end $$;
reset role;
