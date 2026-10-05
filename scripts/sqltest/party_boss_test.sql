-- 週ボス（0040 + 0041 複数パーティ）の検証シナリオ。失敗すると assert で止まる（ON_ERROR_STOP）。
grant usage on schema public, auth, net to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated;
insert into auth.users select ('00000000-0000-0000-0000-00000000000'||i)::uuid from generate_series(1,9) i;
insert into public.profiles(id, display_name) select id, 'U'||right(id::text,1) from auth.users;

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('test.uid', '00000000-0000-0000-0000-00000000000'||n, false)
$$;
create function pg_temp.complete(n int) returns void language sql as $$
  insert into public.workouts(user_id, completed_at) values (('00000000-0000-0000-0000-00000000000'||n)::uuid, now())
$$;

do $$
declare p1 uuid; p2 uuid; px uuid; s json; r json; failed boolean; arr json;
begin
  -- 1. A の初回は1人パーティができる。2回目の ensure は増やさない
  perform pg_temp.as_user(1); p1 := public.ensure_my_party(3);
  assert public.ensure_my_party(3) = p1, 'ensure が2つ目を作った';
  -- 2. A が別グループ用に2つ目を作る（名前つき）。B は p1、C は p2 に参加
  p2 := public.create_party(3, '  職場  ');
  assert (select name from public.parties where id = p2) = '職場', '名前の前後空白を落とす';
  perform pg_temp.as_user(2); assert public.join_party(p1, 2) = p1;
  perform pg_temp.as_user(3); perform public.join_party(p2, 1);
  -- B は自分の1人パーティを持っていても、参加で抜けない
  perform pg_temp.as_user(2); px := public.create_party(3);
  perform public.join_party(p1, 2);
  assert (select count(*) from public.party_members where user_id = '00000000-0000-0000-0000-000000000002') = 2, '参加で既存パーティを抜けた';

  -- 3. A の1回のワークアウトは p1 と p2 の両方に1撃
  perform pg_temp.as_user(1); perform pg_temp.complete(1);
  arr := public.my_parties();
  assert json_array_length(arr) = 2, 'A の全パーティが返らない';
  assert ((arr->0)->>'damage')::int = 1 and ((arr->1)->>'damage')::int = 1, '両方に1撃入らない: '||arr;
  assert (arr->1)->>'name' = '職場';

  -- 4. p2（A:3 + C:1 = HP4）: A がもう3回で A の上限4に達し撃破 → 通知1回
  perform pg_temp.complete(1); perform pg_temp.complete(1);
  assert (select count(*) from net.calls) = 0, 'まだ撃破していない';
  perform pg_temp.complete(1);
  s := public.party_status(p2);
  assert (s->>'defeated')::bool, 'p2 が撃破されていない: '||s;
  assert (select count(*) from net.calls where body->>'partyId' = p2::text) = 1, 'p2 の撃破通知が1回でない';
  -- p1（A:3 + B:2 = HP5）は A の上限4で、まだ倒れない
  assert not (public.party_status(p1)->>'defeated')::bool, 'p1 は B の1撃が要る';
  perform pg_temp.as_user(2); perform pg_temp.complete(2);
  assert (public.party_status(p1)->>'defeated')::bool, 'p1 が撃破されていない';
  assert (select count(*) from net.calls) = 2, '撃破通知の合計が2でない';
  -- B の1撃は B の1人パーティ px（HP3）には撃破にならない
  assert not (public.party_status(px)->>'defeated')::bool;

  -- 5. 宝箱はパーティごと。A は p1 と p2 の2つ。二重受け取りは不可
  perform pg_temp.as_user(1);
  r := public.claim_boss_reward(p1, now()); assert (r->>'energy')::int = 60;
  perform public.claim_boss_reward(p2, now());
  perform public.claim_boss_reward(p2, now());
  assert (select count(*) from public.party_boss_rewards where user_id = '00000000-0000-0000-0000-000000000001') = 2, 'パーティごとに1つでない';
  assert (public.party_status(p1)->>'claimed')::bool;
  -- 撃破していない px は B でも受け取れない。メンバーでない D は p1 を受け取れない
  perform pg_temp.as_user(2);
  failed := false; begin perform public.claim_boss_reward(px, now()); exception when others then failed := true; end;
  assert failed, '未撃破のパーティで受け取れた';
  perform pg_temp.as_user(4);
  failed := false; begin perform public.claim_boss_reward(p1, now()); exception when others then failed := true; end;
  assert failed, 'メンバーでないのに受け取れた';
  assert public.party_status(p1) is null, 'メンバーでないのに状況が見えた';
  failed := false; begin perform public.claim_boss_reward(p1, now() - interval '21 days'); exception when others then failed := true; end;
  assert failed, '期限外の週を受け取れた';

  -- 6. 撃破後に D が p1 に入って HP が増えても撃破済みのまま。D も受け取れる
  perform public.join_party(p1, 7);
  s := public.party_status(p1);
  assert (s->>'hp')::int = 12 and (s->>'defeated')::bool, '撃破後の参加で撃破が取り消された: '||s;
  assert (public.claim_boss_reward(p1, now())->>'energy')::int = 60;

  -- 7. 1パーティ5人まで: p1 は A,B,D + E,F で満員、G は拒否
  perform pg_temp.as_user(5); perform public.join_party(p1, 3);
  perform pg_temp.as_user(6); perform public.join_party(p1, 3);
  perform pg_temp.as_user(7);
  failed := false; begin perform public.join_party(p1, 3); exception when others then failed := true; end;
  assert failed, '6人目が入れた';

  -- 8. 1人5パーティまで: H が5つ作ると6つ目は作れず、参加もできない
  perform pg_temp.as_user(8);
  for i in 1..5 loop perform public.create_party(3); end loop;
  failed := false; begin perform public.create_party(3); exception when others then failed := true; end;
  assert failed, '6つ目のパーティを作れた';
  failed := false; begin perform public.join_party(p2, 3); exception when others then failed := true; end;
  assert failed, '上限を超えて参加できた';

  -- 9. 名前の変更（メンバーのみ）・脱退（空なら消える、報酬は残る）・週目標は全所属に写す
  perform pg_temp.as_user(3); perform public.rename_party(p2, 'ジム');
  assert (select name from public.parties where id = p2) = 'ジム';
  perform public.rename_party(p2, '   ');
  assert (select name from public.parties where id = p2) is null, '空白だけの名前は未設定に戻す';
  perform pg_temp.as_user(9);
  failed := false; begin perform public.rename_party(p2, 'x'); exception when others then failed := true; end;
  assert failed, 'メンバーでないのに名前を変えられた';
  perform pg_temp.as_user(3); perform public.leave_party(p2);
  perform pg_temp.as_user(1); perform public.leave_party(p2);
  assert not exists (select 1 from public.parties where id = p2), '空のパーティが残った';
  assert exists (select 1 from public.party_boss_rewards where party_id is null), 'パーティが消えて報酬も消えた';
  perform public.set_party_weekly_goal(9);
  assert (select bool_and(weekly_goal = 7) from public.party_members where user_id = '00000000-0000-0000-0000-000000000001'), '目標が全所属に写らない';

  -- 10. 週の境界とボスの並び（アプリの PartyBoss と同じ値）
  assert public.party_week_start('2026-10-05 00:30+09') = '2026-10-05 00:00+09', '月曜の境界';
  assert public.party_week_start('2026-10-04 23:30+09') = '2026-09-28 00:00+09', '日曜は前の週';
  assert public.party_boss_id('2026-01-05 00:00+09') = 'sloth_slime';
  assert public.party_boss_id('2026-01-12 00:00+09') = 'couch_golem';
  assert public.party_boss_id('2025-12-29 00:00+09') = 'junk_kraken';
  assert public.party_boss_id('2026-10-05 00:00+09') = 'junk_kraken';
  raise notice 'party_boss_test: ALL PASSED';
end $$;

-- 12. ボスのランク（0042）。新しい利用者 J,K,L（10〜12）で1つのパーティを組む
insert into auth.users select ('00000000-0000-0000-0000-0000000000'||i)::uuid from generate_series(10,12) i;
insert into public.profiles(id) select ('00000000-0000-0000-0000-0000000000'||i)::uuid from generate_series(10,12) i;
create function pg_temp.as_user2(n int) returns void language sql as $$
  select set_config('test.uid', '00000000-0000-0000-0000-0000000000'||n, false)
$$;
do $$
declare pid uuid; ws timestamptz := public.party_week_start(now()); s json; r json; failed boolean;
begin
  if to_regproc('public.vote_boss_tier') is null then
    raise notice 'party_boss_test tier: skipped (0042 未適用)';
    return;
  end if;
  perform pg_temp.as_user2(10); pid := public.create_party(3);     -- J 目標3
  perform pg_temp.as_user2(11); perform public.join_party(pid, 2);  -- K 目標2
  perform pg_temp.as_user2(12); perform public.join_party(pid, 2);  -- L 目標2（合計7・3人）

  -- 票がゼロなら中: HP = 合計 7
  s := public.party_status(pid);
  assert s->>'tier' = 'medium' and (s->>'hp')::int = 7 and (s->>'reward_exp')::int = 200, '既定は中: '||s;

  -- 今週ぶんの票（先週のうちに入った想定）を直接入れる: 強い2・弱い1 → 強い。HP = 7 + 3人 = 10
  insert into public.party_tier_votes(party_id, week_start, user_id, tier) values
    (pid, ws, '00000000-0000-0000-0000-000000000010', 'strong'),
    (pid, ws, '00000000-0000-0000-0000-000000000011', 'strong'),
    (pid, ws, '00000000-0000-0000-0000-000000000012', 'weak');
  s := public.party_status(pid);
  assert s->>'tier' = 'strong' and (s->>'hp')::int = 10 and (s->>'reward_exp')::int = 400, '多数決で強い: '||s;

  -- 同票（弱い1・強い1・中0）は弱い方。HP = ceil(7 × 0.6) = 5
  update public.party_tier_votes set tier = 'weak' where user_id = '00000000-0000-0000-0000-000000000011' and party_id = pid;
  delete from public.party_tier_votes where user_id = '00000000-0000-0000-0000-000000000012' and party_id = pid;
  -- J 強い・K 弱い の1対1
  s := public.party_status(pid);
  assert s->>'tier' = 'weak' and (s->>'hp')::int = 5, '同票は弱い方: '||s;

  -- 抜けた人の票は数えない: L が強いに投票してから抜ける → 弱い1・強い1のまま（弱い）
  insert into public.party_tier_votes(party_id, week_start, user_id, tier) values (pid, ws, '00000000-0000-0000-0000-000000000012', 'strong');
  perform pg_temp.as_user2(12); perform public.leave_party(pid);
  perform pg_temp.as_user2(10);
  assert public.party_status(pid)->>'tier' = 'weak', '抜けた人の票を数えた';
  delete from public.party_tier_votes where user_id = '00000000-0000-0000-0000-000000000012' and party_id = pid;
  perform pg_temp.as_user2(12); perform public.join_party(pid, 2);

  -- 投票 RPC は翌週に入る。自分の票と件数が返る。メンバー以外・不正なランクは拒否
  perform pg_temp.as_user2(10); perform public.vote_boss_tier(pid, 'strong');
  perform public.vote_boss_tier(pid, 'medium');  -- 変更できる
  perform pg_temp.as_user2(11); perform public.vote_boss_tier(pid, 'medium');
  perform pg_temp.as_user2(10);
  s := public.party_status(pid);
  assert s->>'my_next_vote' = 'medium' and ((s->'next_votes')->>'medium')::int = 2 and ((s->'next_votes')->>'strong')::int = 0, '翌週の票: '||s;
  assert exists (select 1 from public.party_tier_votes where party_id = pid and week_start = ws + interval '7 days'), '翌週に入っていない';
  assert s->>'tier' = 'weak', '今週のランクは投票で変わらない';
  failed := false; begin perform public.vote_boss_tier(pid, 'huge'); exception when others then failed := true; end;
  assert failed, '不正なランクを受け付けた';
  perform pg_temp.as_user(1);
  failed := false; begin perform public.vote_boss_tier(pid, 'weak'); exception when others then failed := true; end;
  assert failed, 'メンバー以外が投票できた';

  -- 弱いボス（HP 5）を J・K・L で倒すと、宝箱の EXP は 100、ランクは weak
  perform pg_temp.as_user2(10);
  for i in 1..3 loop
    insert into public.workouts(user_id, completed_at) values ('00000000-0000-0000-0000-000000000010', now());
  end loop;
  insert into public.workouts(user_id, completed_at) values ('00000000-0000-0000-0000-000000000011', now());
  insert into public.workouts(user_id, completed_at) values ('00000000-0000-0000-0000-000000000012', now());
  s := public.party_status(pid);
  assert (s->>'defeated')::bool, '弱いボスが倒れていない: '||s;
  assert (select tier from public.party_defeats where party_id = pid and week_start = ws) = 'weak', '撃破時のランクが記録されない';
  r := public.claim_boss_reward(pid, now());
  assert (r->>'exp')::int = 100 and r->>'tier' = 'weak' and (r->>'energy')::int = 60, '弱いの報酬: '||r;
  raise notice 'party_boss_test tier: ALL PASSED';
end $$;

-- 11. RLS と権限（authenticated として。I は1つもパーティに入っていない）
select pg_temp.as_user(9);
set role authenticated;
do $$ begin
  assert (select count(*) from public.party_members) = 0, '他人のパーティが見えた';
  assert (select count(*) from public.party_boss_rewards) = 0, '他人の報酬が見えた';
  assert (select count(*) from public.parties) = 0, '他人のパーティ名が見えた';
end $$;
do $$ declare failed boolean := false; begin
  begin perform public.party_member_hits('00000000-0000-0000-0000-000000000001', now()); exception when insufficient_privilege then failed := true; end;
  assert failed, '内部の集計関数を呼べた';
  raise notice 'party_boss_test RLS: ALL PASSED';
end $$;
reset role;
