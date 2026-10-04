-- 0040_party_boss の検証シナリオ。失敗すると assert で止まる（ON_ERROR_STOP）。
grant usage on schema public, auth, net to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on function auth.uid() to authenticated;
insert into auth.users select ('00000000-0000-0000-0000-00000000000'||i)::uuid from generate_series(1,8) i;
insert into public.profiles(id, display_name) select id, 'U'||right(id::text,1) from auth.users;

create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('test.uid', '00000000-0000-0000-0000-00000000000'||n, false)
$$;
create function pg_temp.complete(n int) returns void language sql as $$
  insert into public.workouts(user_id, completed_at) values (('00000000-0000-0000-0000-00000000000'||n)::uuid, now())
$$;

do $$
declare pid uuid; pid_c uuid; s json; calls int; r json; failed boolean;
begin
  -- 1. A がパーティを作り、B が参加。C は別の1人パーティ
  perform pg_temp.as_user(1); pid := public.ensure_my_party(3);
  perform pg_temp.as_user(2); assert public.join_party(pid, 2) = pid, 'B が参加できない';
  perform pg_temp.as_user(3); pid_c := public.ensure_my_party(3);
  assert pid_c <> pid, 'C は別パーティのはず';

  -- 2. A が5回完了しても上限は 3+1=4。HP は 3+2=5 なので倒れない
  perform pg_temp.as_user(1);
  for i in 1..5 loop perform pg_temp.complete(1); end loop;
  s := public.party_status();
  assert (s->>'hp')::int = 5 and (s->>'damage')::int = 4 and not (s->>'defeated')::bool, '上限・HP の計算が違う: '||s;
  assert (select count(*) from net.calls) = 0, 'まだ通知しない';

  -- 3. B の1撃で撃破。通知はちょうど1回、B の2撃目・A の追加では鳴らない
  perform pg_temp.complete(2);
  assert (select count(*) from net.calls where body->>'event' = 'boss_defeated') = 1, '撃破通知が1回でない';
  perform pg_temp.complete(2); perform pg_temp.complete(1);
  assert (select count(*) from net.calls) = 1, '撃破後に再通知した';
  s := public.party_status();
  assert (s->>'defeated')::bool and not (s->>'claimed')::bool, '撃破済み・未受け取りのはず';

  -- 4. 報酬: A が受け取る。二度目は同じ結果で行は増えない
  r := public.claim_boss_reward(now());
  assert (r->>'energy')::int = 60, '報酬が違う';
  perform public.claim_boss_reward(now());
  assert (select count(*) from public.party_boss_rewards) = 1, '二重に受け取れた';
  assert (public.party_status()->>'claimed')::bool, '受け取り済みにならない';

  -- 5. 期限外の週・撃破していない C は受け取れない
  failed := false; begin perform public.claim_boss_reward(now() - interval '21 days'); exception when others then failed := true; end;
  assert failed, '期限外の週を受け取れた';
  perform pg_temp.as_user(3);
  failed := false; begin perform public.claim_boss_reward(now()); exception when others then failed := true; end;
  assert failed, '撃破していないのに受け取れた';

  -- 6. 撃破後に D が参加して HP が増えても、その週は撃破済みのまま。D も受け取れる
  perform pg_temp.as_user(4); perform public.join_party(pid, 7);
  s := public.party_status();
  assert (s->>'hp')::int = 12 and (s->>'defeated')::bool, '撃破後の参加で撃破が取り消された: '||s;
  assert (public.claim_boss_reward(now())->>'energy')::int = 60, 'D が受け取れない';

  -- 7. 満員: A・B・D に E・F が入って5人、H（8）は拒否
  perform pg_temp.as_user(5); perform public.join_party(pid, 3);
  perform pg_temp.as_user(6); perform public.join_party(pid, 3);
  perform pg_temp.as_user(8);
  failed := false; begin perform public.join_party(pid, 3); exception when others then failed := true; end;
  assert failed, '6人目が入れた';
  assert not exists (select 1 from public.party_members where user_id = '00000000-0000-0000-0000-000000000008'), '拒否された人が残った';

  -- 8. 脱退すると空のパーティは消える。目標の写し
  perform pg_temp.as_user(3); perform public.leave_party();
  assert not exists (select 1 from public.parties where id = pid_c), '空のパーティが残った';
  perform pg_temp.as_user(4); perform public.set_party_weekly_goal(9);
  assert (select weekly_goal from public.party_members where user_id = '00000000-0000-0000-0000-000000000004') = 7, '目標が 1〜7 に丸められない';

  -- 9. 1人パーティの撃破は記録するが通知しない。下書き → 完了の UPDATE 経路も数える
  perform pg_temp.as_user(7); pid_c := public.ensure_my_party(1);
  delete from net.calls;
  insert into public.workouts(id, user_id, completed_at) values ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000007', null);
  update public.workouts set completed_at = now() where id = '11111111-1111-1111-1111-111111111111';
  update public.workouts set completed_at = now() where id = '11111111-1111-1111-1111-111111111111';
  assert (select count(*) from net.calls) = 0, '1人パーティで通知した';
  assert exists (select 1 from public.party_defeats where party_id = pid_c), '1人パーティの撃破が記録されない';

  -- 10. 週の境界とボスの並び（アプリの PartyBoss と同じ値）
  assert public.party_week_start('2026-10-05 00:30+09') = '2026-10-05 00:00+09', '月曜の境界';
  assert public.party_week_start('2026-10-04 23:30+09') = '2026-09-28 00:00+09', '日曜は前の週';
  assert public.party_boss_id('2026-01-05 00:00+09') = 'sloth_slime';
  assert public.party_boss_id('2026-01-12 00:00+09') = 'couch_golem';
  assert public.party_boss_id('2025-12-29 00:00+09') = 'junk_kraken';
  assert public.party_boss_id('2026-10-05 00:00+09') = 'junk_kraken';
  raise notice 'party_boss_test: ALL PASSED';
end $$;

-- 11. RLS と権限（authenticated として）
select pg_temp.as_user(8);
set role authenticated;
do $$ begin
  assert (select count(*) from public.party_members) = 0, '他人のパーティが見えた';
  assert (select count(*) from public.party_boss_rewards) = 0, '他人の報酬が見えた';
end $$;
do $$ declare failed boolean := false; begin
  begin perform public.party_member_hits('00000000-0000-0000-0000-000000000001', now()); exception when insufficient_privilege then failed := true; end;
  assert failed, '内部の集計関数を呼べた';
  raise notice 'party_boss_test RLS: ALL PASSED';
end $$;
reset role;
