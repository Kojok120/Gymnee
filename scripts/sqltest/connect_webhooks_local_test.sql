-- 外部連携の送り先と知らせ（0047・#171）の検証。ローカル Supabase（全 migration 済み）に対して流す。
-- 使い方: /opt/homebrew/opt/postgresql@16/bin/psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f scripts/sqltest/connect_webhooks_local_test.sql
-- 全体を begin / rollback で包むので、ローカルの DB にも何も残らない。
begin;

create function pg_temp.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;

insert into auth.users (id, instance_id, aud, role, email)
select pg_temp.u(i), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hook' || i || '@test.local'
from generate_series(1, 3) i;

do $$
declare
  n int;
begin
  -- U1: 送り先 2 つ（Slack は両方、Webhook は記録だけ）/ U2: 送り先なし / U3: 止まった送り先だけ
  insert into public.connect_destinations (id, user_id, kind, label, target_ciphertext, events)
  values (pg_temp.u(501), pg_temp.u(1), 'slack', '#gym', 'v1.x.y', array['workout.completed', 'weekly.summary']),
         (pg_temp.u(502), pg_temp.u(1), 'webhook', 'example.com', 'v1.x.y', array['workout.completed']);
  insert into public.connect_destinations (id, user_id, kind, label, target_ciphertext, disabled_at)
  values (pg_temp.u(503), pg_temp.u(3), 'discord', 'Discord', 'v1.x.y', now());

  -- 完了した記録 → 知らせが積まれる
  insert into public.workouts (id, user_id, date, name, completed_at) values (pg_temp.u(101), pg_temp.u(1), now(), '胸', now());
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(101);
  assert n = 1, '完了した記録で知らせが 1 件積まれる';

  -- 下書き（未完了）→ 積まれない。あとで完了したら積まれる（アプリの upsert は UPDATE で来る）
  insert into public.workouts (id, user_id, date, name) values (pg_temp.u(102), pg_temp.u(1), now(), '下書き');
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(102);
  assert n = 0, '下書きでは積まない';
  update public.workouts set completed_at = now() where id = pg_temp.u(102);
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(102);
  assert n = 1, '完了にしたら積む';

  -- 完了済みの記録を直しただけ → 積み増さない
  update public.workouts set completed_at = now() + interval '1 minute', name = '直した' where id = pg_temp.u(101);
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(101);
  assert n = 1, '完了済みを直しても 2 件目は積まない';

  -- 2 日前に完了した記録（初回サインインでまとめて上がった過去分）→ 積まない
  insert into public.workouts (id, user_id, date, name, completed_at) values (pg_temp.u(103), pg_temp.u(1), now() - interval '2 days', '昔', now() - interval '2 days');
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(103);
  assert n = 0, '24 時間より前の完了は積まない';

  -- 計画（is_planned）→ 積まない
  insert into public.workouts (id, user_id, date, name, completed_at, is_planned) values (pg_temp.u(104), pg_temp.u(1), now(), '計画', now(), true);
  select count(*) into n from public.connect_events where subject_id = pg_temp.u(104);
  assert n = 0, '計画は積まない';

  -- 送り先の無い人・止まった送り先しか無い人 → 積まない
  insert into public.workouts (id, user_id, date, name, completed_at) values (pg_temp.u(105), pg_temp.u(2), now(), 'U2', now());
  insert into public.workouts (id, user_id, date, name, completed_at) values (pg_temp.u(106), pg_temp.u(3), now(), 'U3', now());
  select count(*) into n from public.connect_events where subject_id in (pg_temp.u(105), pg_temp.u(106));
  assert n = 0, '送り先が無い人は積まない';

  -- 待ち時間の前は展開しない
  assert public.connect_fanout_events(50) = 0, '待ち時間の前は展開しない';
  update public.connect_events set process_after = now() - interval '1 second';
  -- 展開: 知らせ 2 件 × U1 の送り先 2 つ = 4 件
  assert public.connect_fanout_events(50) = 4, '送り先ごとに展開する';
  assert public.connect_fanout_events(50) = 0, '展開済みの知らせはもう取り出さない';

  -- 週のふりかえり: weekly.summary を受け取る送り先（Slack）だけ。2 回呼んでも 1 回分
  assert public.connect_enqueue_weekly(public.party_week_start(now() - interval '7 days')) = 1, '週のふりかえりは受け取る送り先だけ';
  assert public.connect_enqueue_weekly(public.party_week_start(now() - interval '7 days')) = 0, '同じ週は 2 回積まない';

  -- 取り出すと 2 分間ほかから見えない
  select count(*) into n from public.connect_claim_deliveries(100);
  assert n = 5, '送る順番の来た配信を全部取り出す';
  select count(*) into n from public.connect_claim_deliveries(100);
  assert n = 0, '取り出し中の配信は 2 回取り出さない';
  select min(attempts) into n from public.connect_deliveries;
  assert n = 1, '取り出すと試行回数が 1 増える';

  -- 退会したら送り先・知らせ・配信も消える
  delete from auth.users where id = pg_temp.u(1);
  select count(*) into n from public.connect_deliveries;
  assert n = 0, '退会で配信も消える';
  select count(*) into n from public.connect_destinations where user_id = pg_temp.u(1);
  assert n = 0, '退会で送り先も消える';

  perform public.connect_purge();
  raise notice 'connect webhooks: PASSED';
end $$;

do $$
begin
  assert not has_function_privilege('authenticated', 'public.connect_fanout_events(int)', 'execute'), 'authenticated は呼べない';
  assert not has_function_privilege('anon', 'public.connect_claim_deliveries(int)', 'execute'), 'anon は呼べない';
  assert has_function_privilege('service_role', 'public.connect_claim_deliveries(int)', 'execute'), 'service_role は呼べる';
  assert not has_table_privilege('authenticated', 'public.connect_destinations', 'select'), '送り先の表は読めない';
  raise notice 'connect webhooks privileges: PASSED';
end $$;

rollback;
