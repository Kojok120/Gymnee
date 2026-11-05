-- 0048: LINE のコーチと通知（#171 の 3 段目）
-- Worker（connect/）が service role で使う。どの表も RLS を有効にし、ポリシーは置かない（アプリも Worker 経由）。
--
-- 紐付けは LINE ログインを使わず、アプリが出す 6 桁の連携コードを、利用者が LINE から公式アカウントに送る形にする
-- （アプリのボタンで LINE が開き、コードは入力済み。ブラウザもログインも挟まない）。

-- ------------------------------------------------------------
-- LINE の紐付けと通知の設定
-- ------------------------------------------------------------
create table if not exists public.line_links (
    user_id           uuid primary key references auth.users(id) on delete cascade,
    line_user_id      text not null unique,
    -- off: 送らない / lapse: 途切れそうなときだけ / daily: 毎日 / daily_menu: 毎日＋メニュー提案
    notify_mode       text not null default 'daily',
    -- 送る時刻（JST の時）
    notify_hour       smallint not null default 7,
    last_notified_on  date,
    linked_at         timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    constraint line_links_notify_mode check (notify_mode in ('off', 'lapse', 'daily', 'daily_menu')),
    constraint line_links_notify_hour check (notify_hour between 0 and 23)
);

create index if not exists line_links_notify_idx on public.line_links (notify_hour) where notify_mode <> 'off';

alter table public.line_links enable row level security;
revoke all on table public.line_links from anon, authenticated;

-- 連携コード（アプリが発行し、LINE から送られてきたら紐付ける）。10 分で切れる・1 回きり。
create table if not exists public.line_link_codes (
    code        text primary key,
    user_id     uuid not null references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now(),
    expires_at  timestamptz not null default now() + interval '10 minutes',
    constraint line_link_codes_format check (code ~ '^[0-9]{6}$')
);

create index if not exists line_link_codes_user_idx on public.line_link_codes (user_id);

alter table public.line_link_codes enable row level security;
revoke all on table public.line_link_codes from anon, authenticated;

-- 連携コードの総当たりを止める（LINE の利用者ごとに 1 時間 10 回まで）。
create table if not exists public.line_link_attempts (
    line_user_id  text not null,
    attempted_at  timestamptz not null default now()
);

create index if not exists line_link_attempts_idx on public.line_link_attempts (line_user_id, attempted_at desc);

alter table public.line_link_attempts enable row level security;
revoke all on table public.line_link_attempts from anon, authenticated;

-- LINE で「この内容で記録する？」と確かめている記録（確認ボタンを押したら記録する）。1 日で切れる。
create table if not exists public.line_pending_logs (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    -- LogWorkoutInput（connect/src/domain/workoutInput.ts）の形
    payload      jsonb not null,
    created_at   timestamptz not null default now(),
    expires_at   timestamptz not null default now() + interval '1 day',
    consumed_at  timestamptz
);

create index if not exists line_pending_logs_user_idx on public.line_pending_logs (user_id, created_at desc);

alter table public.line_pending_logs enable row level security;
revoke all on table public.line_pending_logs from anon, authenticated;

-- ------------------------------------------------------------
-- AI の呼び出し回数（サーバー側の上限。アプリの CoachQuota は端末だけなので、LINE からの分はここで数える）
-- ------------------------------------------------------------
create table if not exists public.connect_ai_usage (
    user_id  uuid not null references auth.users(id) on delete cascade,
    day      date not null,
    count    int not null default 0,
    primary key (user_id, day)
);

alter table public.connect_ai_usage enable row level security;
revoke all on table public.connect_ai_usage from anon, authenticated;

-- 上限の内なら 1 増やして true、超えていれば false（数えるのと確かめるのを 1 回で行い、競合しても超えない）。
create or replace function public.connect_take_ai_quota(p_user uuid, p_day date, p_limit int)
returns boolean language plpgsql security definer set search_path = public as $$
declare
    n int;
begin
    insert into public.connect_ai_usage (user_id, day, count) values (p_user, p_day, 1)
    on conflict (user_id, day) do update set count = public.connect_ai_usage.count + 1
        where public.connect_ai_usage.count < p_limit
    returning count into n;
    return n is not null;
end;
$$;

-- ------------------------------------------------------------
-- 毎日の通知: その時刻に送る人を、今日まだ送っていない人だけ取り出す（取り出した時点で今日は送った扱い）。
-- ------------------------------------------------------------
create or replace function public.connect_claim_line_notifications(p_hour int, p_day date, p_limit int default 20)
returns setof public.line_links language sql security definer set search_path = public as $$
    update public.line_links l
       set last_notified_on = p_day, updated_at = now()
     where l.user_id in (
        select user_id from public.line_links
         where notify_mode <> 'off' and notify_hour = p_hour
           and (last_notified_on is null or last_notified_on < p_day)
         order by user_id
         limit greatest(1, least(p_limit, 200))
         for update skip locked
     )
    returning l.*
$$;

-- 掃除に LINE の分を足す（0047 の connect_purge を置き換え）。
create or replace function public.connect_purge()
returns void language sql security definer set search_path = public as $$
    delete from public.connect_events where processed_at < now() - interval '14 days';
    delete from public.connect_deliveries where status <> 'pending' and updated_at < now() - interval '14 days';
    delete from public.connect_oauth_pairings where expires_at < now() - interval '1 day';
    delete from public.line_link_codes where expires_at < now();
    delete from public.line_link_attempts where attempted_at < now() - interval '1 day';
    delete from public.line_pending_logs where expires_at < now() - interval '1 day';
    delete from public.connect_ai_usage where day < (now() at time zone 'Asia/Tokyo')::date - 7;
$$;

revoke all on function public.connect_take_ai_quota(uuid, date, int) from public, anon, authenticated;
revoke all on function public.connect_claim_line_notifications(int, date, int) from public, anon, authenticated;
revoke all on function public.connect_purge() from public, anon, authenticated;
grant execute on function public.connect_take_ai_quota(uuid, date, int) to service_role;
grant execute on function public.connect_claim_line_notifications(int, date, int) to service_role;
grant execute on function public.connect_purge() to service_role;

-- ------------------------------------------------------------
-- コーチの会話がどこから来たか（app / line / mcp / api）。アプリは知らない列を読まない（差分 pull は既知の列だけ使う）。
-- アプリの upsert はこの列を送らないので、アプリで書いた会話は既定の app のまま。
-- ------------------------------------------------------------
alter table public.coach_messages add column if not exists channel text not null default 'app';

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'coach_messages_channel') then
        alter table public.coach_messages
            add constraint coach_messages_channel check (channel in ('app', 'line', 'mcp', 'api'));
    end if;
end $$;
