-- 必殺技（0045・issue #150）の検証シナリオ。
-- 使い方: bash scripts/sqltest/run.sh supabase/migrations/004{0,1,2,3}_*.sql supabase/migrations/0045_special_attack.sql scripts/sqltest/special_attack_test.sql
grant usage on schema public, auth, net to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated;

create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
insert into auth.users select pg_temp.u(i) from generate_series(1, 8) i;
insert into public.profiles(id, display_name) select pg_temp.u(i), 'U' || i from generate_series(1, 8) i;
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('test.uid', pg_temp.u(n)::text, false)
$$;
create function pg_temp.fails(p uuid) returns text language plpgsql as $$
begin
  perform public.party_special_attack(p);
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

do $$
declare
  p uuid; q uuid; r uuid; w1 uuid; s json; atk json; special json;
begin
  delete from net.calls;
  -- パーティ P: U1（目標3）・U2（目標3）。HP = 6（中くらい）
  perform pg_temp.as_user(1); p := public.create_party(3);
  perform pg_temp.as_user(2); perform public.join_party(p, 3);
  assert public.party_special_attack_cost() = 100, '必殺技のパワーは 100';

  -- U1 が2回・U2 が1回（連携つき）: 基本3 + 連携1 = 4（残り2）
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(1), now()) returning id into w1;
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(1), now());
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(2), now());
  assert public.party_damage(p, public.party_week_start(now())) = 4, '必殺技の前のダメージ';
  assert (select count(*) from net.calls) = 0, 'まだ何も送らない';

  -- 1. U1 の必殺技: 5（残り1）→ あと1撃を送る。状況が返る
  perform pg_temp.as_user(1);
  s := public.party_special_attack(p);
  assert (s->>'damage')::int = 5 and not (s->>'defeated')::bool, '必殺技で1撃: ' || (s->>'damage');
  atk := s->'attacks';
  assert json_array_length(atk) = 4, '攻撃の一覧に必殺技が入る: ' || atk;
  select a into special from json_array_elements(atk) a where a->>'category' = 'special';
  assert special->>'category' = 'special' and (special->>'user_id')::uuid = pg_temp.u(1)
     and (special->>'base')::int = 1 and (special->>'skill')::int = 0 and (special->>'combo')::int = 0,
     '必殺技は 1撃だけ: ' || special;
  assert special->>'id' = md5((select id from public.party_special_attacks where user_id = pg_temp.u(1))::text), '必殺技の id';
  -- 同じトランザクションの now() は同時刻なので並びは id 順。入っていることだけ見る。
  assert exists (select 1 from json_array_elements(atk) a where a->>'id' = md5(w1::text)), 'ワークアウトの攻撃の id は 0043 のまま';
  assert (select energy_spent from public.party_special_attacks where user_id = pg_temp.u(1)) = 100, '使ったパワーの記録';
  assert (select count(*) from net.calls where body->>'event' = 'boss_reach' and body->>'attackerId' = pg_temp.u(1)::text) = 1,
     'あと1撃が送られない';

  -- 2. 同じ週に二度は出せない
  assert pg_temp.fails(p) = 'already used', '二度目が出せた';

  -- 3. パーティの外の人は出せない
  perform pg_temp.as_user(3);
  assert pg_temp.fails(p) = 'not a member', 'パーティの外から出せた';

  -- 4. U2 の必殺技でとどめ: 6 → 撃破を送る（倒したのは U2）
  perform pg_temp.as_user(2);
  s := public.party_special_attack(p);
  assert (s->>'damage')::int = 6 and (s->>'defeated')::bool, '必殺技で撃破: ' || (s->>'damage');
  assert (select defeated_by from public.party_defeats where party_id = p) = pg_temp.u(2), '倒した人の記録';
  assert (select count(*) from net.calls where body->>'event' = 'boss_defeated' and body->>'defeatedBy' = pg_temp.u(2)::text) = 1,
     '撃破が送られない';

  -- 5. 撃破したあとは出せない（1人パーティ Q: 目標1 → HP1。ワークアウトで撃破）
  perform pg_temp.as_user(4); q := public.create_party(1);
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(4), now());
  assert pg_temp.fails(q) = 'already defeated', '撃破後に出せた';

  -- 6. 1人パーティ R（目標2 → HP2）: 1回 + 必殺技で撃破。知らせる相手がいないので送らない
  delete from net.calls;
  perform pg_temp.as_user(5); r := public.create_party(2);
  insert into public.workouts(user_id, completed_at) values (pg_temp.u(5), now());
  s := public.party_special_attack(r);
  assert (s->>'defeated')::bool, '1人パーティで撃破できない';
  assert exists (select 1 from public.party_defeats where party_id = r and defeated_by = pg_temp.u(5)), '撃破の記録';
  assert (select count(*) from net.calls) = 0, '1人パーティに送った';

  -- 7. ほかの関数のダメージにも入る（「この1回の前」の計算でも必殺技は数える）
  assert public.party_damage(p, public.party_week_start(now()), w1) = 5, 'ワークアウトを除いた計算: ' || public.party_damage(p, public.party_week_start(now()), w1);
  raise notice 'special_attack_test: ALL PASSED';
end $$;

-- 8. 権限: 読めるのは自分の記録だけ。直接は書けない。RPC は authenticated だけ
do $$
declare failed boolean := false;
begin
  assert has_function_privilege('authenticated', 'public.party_special_attack(uuid)', 'execute'), 'アプリから出せない';
  assert not has_function_privilege('anon', 'public.party_special_attack(uuid)', 'execute'), '未サインインで出せる';
  assert not has_function_privilege('authenticated', 'public.party_damage(uuid, timestamptz, uuid)', 'execute'), '集計を直接呼べる';
end $$;
select set_config('test.uid', pg_temp.u(1)::text, false);
set role authenticated;
do $$
declare failed boolean := false;
begin
  assert (select count(*) from public.party_special_attacks) = 1, '自分以外の記録が見えた';
  begin
    insert into public.party_special_attacks(party_id, week_start, energy_spent)
      values ((select party_id from public.party_members limit 1), now(), 1);
  exception when insufficient_privilege then failed := true; end;
  assert failed, '必殺技の記録を直接書けた';
  raise notice 'special_attack_test RLS: ALL PASSED';
end $$;
reset role;
