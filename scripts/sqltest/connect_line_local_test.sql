-- LINE のコーチと通知（0048・#171）の検証。ローカル Supabase（全 migration 済み）に対して流す。
-- 使い方: /opt/homebrew/opt/postgresql@16/bin/psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f scripts/sqltest/connect_line_local_test.sql
-- 全体を begin / rollback で包むので、ローカルの DB にも何も残らない。
begin;

create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;

insert into auth.users (id, instance_id, aud, role, email)
select pg_temp.u(i), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'line' || i || '@test.local'
from generate_series(1, 4) i;

do $$
declare
  n int;
  ok boolean;
begin
  -- AI の上限: 3 回までは true、4 回目は false
  for i in 1..3 loop
    ok := public.connect_take_ai_quota(pg_temp.u(1), '2026-11-06', 3);
    assert ok, 'AI の上限の内は通す';
  end loop;
  assert not public.connect_take_ai_quota(pg_temp.u(1), '2026-11-06', 3), '上限を超えたら断る';
  assert public.connect_take_ai_quota(pg_temp.u(1), '2026-11-07', 3), '日が変われば戻る';
  select count into n from public.connect_ai_usage where user_id = pg_temp.u(1) and day = '2026-11-06';
  assert n = 3, '上限を超えても数は増やさない';

  -- 毎日の通知: 7 時の人だけ、今日まだの人だけ、オフの人は除く
  insert into public.line_links (user_id, line_user_id, notify_mode, notify_hour, last_notified_on) values
    (pg_temp.u(1), 'U1', 'daily', 7, null),
    (pg_temp.u(2), 'U2', 'daily_menu', 7, '2026-11-05'),
    (pg_temp.u(3), 'U3', 'off', 7, null),
    (pg_temp.u(4), 'U4', 'lapse', 19, null);
  select count(*) into n from public.connect_claim_line_notifications(7, '2026-11-06', 20);
  assert n = 2, '7 時の、オフでない人だけを取り出す';
  select count(*) into n from public.connect_claim_line_notifications(7, '2026-11-06', 20);
  assert n = 0, '同じ日に 2 回は取り出さない';
  select count(*) into n from public.connect_claim_line_notifications(19, '2026-11-06', 20);
  assert n = 1, '時刻ごとに取り出す';

  -- 同じ LINE の利用者を 2 つのアカウントに紐付けない
  begin
    insert into public.line_links (user_id, line_user_id) values (pg_temp.u(3), 'U1');
    assert false, '同じ LINE の利用者は 1 アカウントだけ';
  exception when unique_violation then null;
  end;

  -- 連携コードは 6 桁だけ
  begin
    insert into public.line_link_codes (code, user_id) values ('12ab56', pg_temp.u(1));
    assert false, '数字 6 桁以外は入れない';
  exception when check_violation then null;
  end;

  -- コーチの会話の出どころ: 既定は app、知らない値は入れない
  insert into public.coach_messages (id, user_id, is_from_coach, body) values (pg_temp.u(801), pg_temp.u(1), true, 'やあ');
  assert (select channel from public.coach_messages where id = pg_temp.u(801)) = 'app', '既定は app';
  begin
    insert into public.coach_messages (id, user_id, is_from_coach, body, channel) values (pg_temp.u(802), pg_temp.u(1), true, 'x', 'sms');
    assert false, '知らない出どころは入れない';
  exception when check_violation then null;
  end;

  -- 退会で LINE の紐付けも消える
  delete from auth.users where id = pg_temp.u(1);
  assert not exists (select 1 from public.line_links where line_user_id = 'U1'), '退会で紐付けも消える';

  perform public.connect_purge();
  raise notice 'connect line: PASSED';
end $$;

do $$
begin
  assert not has_function_privilege('authenticated', 'public.connect_take_ai_quota(uuid, date, int)', 'execute'), 'authenticated は呼べない';
  assert not has_function_privilege('anon', 'public.connect_claim_line_notifications(int, date, int)', 'execute'), 'anon は呼べない';
  assert has_function_privilege('service_role', 'public.connect_claim_line_notifications(int, date, int)', 'execute'), 'service_role は呼べる';
  assert not has_table_privilege('authenticated', 'public.line_links', 'select'), 'LINE の紐付けは読めない';
  raise notice 'connect line privileges: PASSED';
end $$;

rollback;
