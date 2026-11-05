-- 0047: 外部連携の送り先（Slack / Discord / 汎用 Webhook）と、記録の完了の知らせ（#171 の 2 段目）
-- Worker（connect/）が service role で使う。どの表も RLS を有効にし、ポリシーは置かない（アプリも Worker 経由）。
--
-- 流れ:
--   workouts の完了 → トリガーが connect_events に積む（少し待ってから処理する）
--   → Worker の cron が connect_fanout_events で送り先ごとの connect_deliveries に展開
--   → connect_claim_deliveries で取り出して送る（失敗したら時間をあけて再試行）
-- 少し待つのは、アプリが workouts → workout_exercises → exercise_sets の順に送るため、
-- 完了の瞬間にはまだセットがサーバーに無いから。本文は送るときにその時点のデータで作る。

-- ------------------------------------------------------------
-- 送り先
-- ------------------------------------------------------------
create table if not exists public.connect_destinations (
    id                         uuid primary key default gen_random_uuid(),
    user_id                    uuid not null references auth.users(id) on delete cascade,
    kind                       text not null,
    -- 一覧に出す名前（#channel・ワークスペース名・URL のホスト）。秘密は含めない
    label                      text not null,
    -- 送り先の URL（AES-GCM。鍵は Worker の ENCRYPTION_KEY）。Slack / Discord の URL はそれ自体が投稿の鍵なので平文で持たない
    target_ciphertext          text not null,
    -- 汎用 Webhook の署名鍵（whsec_…。同じく暗号化）
    signing_secret_ciphertext  text,
    events                     text[] not null default array['workout.completed', 'weekly.summary'],
    consecutive_failures       int not null default 0,
    disabled_at                timestamptz,
    disabled_reason            text,
    last_delivered_at          timestamptz,
    created_at                 timestamptz not null default now(),
    updated_at                 timestamptz not null default now(),
    constraint connect_destinations_kind check (kind in ('slack', 'discord', 'webhook')),
    constraint connect_destinations_events_known check (events <@ array['workout.completed', 'weekly.summary']::text[]),
    constraint connect_destinations_label_length check (char_length(label) between 1 and 120)
);

create index if not exists connect_destinations_user_idx on public.connect_destinations (user_id);

alter table public.connect_destinations enable row level security;
revoke all on table public.connect_destinations from anon, authenticated;

-- ------------------------------------------------------------
-- 起きたこと（いまは記録の完了だけ）
-- ------------------------------------------------------------
create table if not exists public.connect_events (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null references auth.users(id) on delete cascade,
    type           text not null,
    subject_id     uuid not null,
    occurred_at    timestamptz not null,
    process_after  timestamptz not null default now() + interval '2 minutes',
    processed_at   timestamptz,
    created_at     timestamptz not null default now(),
    constraint connect_events_once unique (type, subject_id)
);

create index if not exists connect_events_pending_idx on public.connect_events (process_after) where processed_at is null;

alter table public.connect_events enable row level security;
revoke all on table public.connect_events from anon, authenticated;

-- ------------------------------------------------------------
-- 送り先ごとの配信（再試行の単位）
-- ------------------------------------------------------------
create table if not exists public.connect_deliveries (
    id               uuid primary key default gen_random_uuid(),
    destination_id   uuid not null references public.connect_destinations(id) on delete cascade,
    user_id          uuid not null references auth.users(id) on delete cascade,
    event_type       text not null,
    -- 同じ送り先に同じ知らせを 2 回送らないための鍵（workout.completed:<id> / weekly.summary:<週の初日>）
    subject_key      text not null,
    subject_id       uuid,
    period_start     timestamptz,
    status           text not null default 'pending',
    attempts         int not null default 0,
    next_attempt_at  timestamptz not null default now(),
    last_status      int,
    last_error       text,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    constraint connect_deliveries_once unique (destination_id, subject_key),
    constraint connect_deliveries_status check (status in ('pending', 'succeeded', 'failed'))
);

create index if not exists connect_deliveries_due_idx on public.connect_deliveries (next_attempt_at) where status = 'pending';

alter table public.connect_deliveries enable row level security;
revoke all on table public.connect_deliveries from anon, authenticated;

-- ------------------------------------------------------------
-- 記録の完了を拾う
-- 完了時刻が直近 24 時間以内の記録だけ（ゲストからの初回サインインで過去分がまとめて上がっても知らせない）。
-- 完了済みの記録を直したとき（old.completed_at があるとき）は知らせない。送り先の無い人の分は積まない。
-- ------------------------------------------------------------
create or replace function public.connect_enqueue_workout_completed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.completed_at is null or new.is_planned then
        return new;
    end if;
    if tg_op = 'UPDATE' and old.completed_at is not null then
        return new;
    end if;
    if new.completed_at < now() - interval '24 hours' or new.completed_at > now() + interval '1 hour' then
        return new;
    end if;
    if not exists (
        select 1 from public.connect_destinations d
        where d.user_id = new.user_id and d.disabled_at is null and 'workout.completed' = any(d.events)
    ) then
        return new;
    end if;
    insert into public.connect_events (user_id, type, subject_id, occurred_at)
    values (new.user_id, 'workout.completed', new.id, new.completed_at)
    on conflict (type, subject_id) do nothing;
    return new;
end;
$$;

revoke all on function public.connect_enqueue_workout_completed() from public, anon, authenticated;

drop trigger if exists trg_connect_workout_completed on public.workouts;
create trigger trg_connect_workout_completed
    after insert or update of completed_at on public.workouts
    for each row execute function public.connect_enqueue_workout_completed();

-- ------------------------------------------------------------
-- Worker が使う関数（service_role だけ）
-- ------------------------------------------------------------

-- 待ち時間を過ぎた知らせを取り出し、送り先ごとの配信に展開する。展開した配信の数を返す。
-- 同時に動いても同じ知らせを 2 回取り出さない（for update skip locked）。
create or replace function public.connect_fanout_events(p_limit int default 50)
returns int language plpgsql security definer set search_path = public as $$
declare
    n int;
begin
    with claimed as (
        update public.connect_events e
           set processed_at = now()
         where e.id in (
            select id from public.connect_events
             where processed_at is null and process_after <= now()
             order by process_after
             limit greatest(1, least(p_limit, 500))
             for update skip locked
         )
        returning e.*
    ), ins as (
        insert into public.connect_deliveries (destination_id, user_id, event_type, subject_key, subject_id)
        select d.id, c.user_id, c.type, c.type || ':' || c.subject_id, c.subject_id
          from claimed c
          join public.connect_destinations d
            on d.user_id = c.user_id and d.disabled_at is null and c.type = any(d.events)
        on conflict (destination_id, subject_key) do nothing
        returning 1
    )
    select count(*) into n from ins;
    return n;
end;
$$;

-- 週のふりかえりを、受け取る設定の送り先ごとに積む（月曜の朝に先週分）。積んだ数を返す。何度呼んでも 1 回分しか積まない。
create or replace function public.connect_enqueue_weekly(p_week_start timestamptz)
returns int language plpgsql security definer set search_path = public as $$
declare
    n int;
begin
    with ins as (
        insert into public.connect_deliveries (destination_id, user_id, event_type, subject_key, period_start)
        select d.id, d.user_id, 'weekly.summary',
               'weekly.summary:' || to_char(p_week_start at time zone 'Asia/Tokyo', 'YYYY-MM-DD'),
               p_week_start
          from public.connect_destinations d
         where d.disabled_at is null and 'weekly.summary' = any(d.events)
        on conflict (destination_id, subject_key) do nothing
        returning 1
    )
    select count(*) into n from ins;
    return n;
end;
$$;

-- 送る順番が来た配信を取り出す。取り出した配信は 2 分間ほかから見えない（その間に送り終える。
-- Worker が途中で落ちても 2 分後にもう一度取り出される）。
create or replace function public.connect_claim_deliveries(p_limit int default 25)
returns setof public.connect_deliveries language sql security definer set search_path = public as $$
    update public.connect_deliveries d
       set attempts = d.attempts + 1, next_attempt_at = now() + interval '2 minutes', updated_at = now()
     where d.id in (
        select id from public.connect_deliveries
         where status = 'pending' and next_attempt_at <= now()
         order by next_attempt_at
         limit greatest(1, least(p_limit, 200))
         for update skip locked
     )
    returning d.*
$$;

-- 古いものを掃除する（知らせ・配信は 14 日、OAuth の承認待ちは切れてから 1 日）。
create or replace function public.connect_purge()
returns void language sql security definer set search_path = public as $$
    delete from public.connect_events where processed_at < now() - interval '14 days';
    delete from public.connect_deliveries where status <> 'pending' and updated_at < now() - interval '14 days';
    delete from public.connect_oauth_pairings where expires_at < now() - interval '1 day';
$$;

revoke all on function public.connect_fanout_events(int) from public, anon, authenticated;
revoke all on function public.connect_enqueue_weekly(timestamptz) from public, anon, authenticated;
revoke all on function public.connect_claim_deliveries(int) from public, anon, authenticated;
revoke all on function public.connect_purge() from public, anon, authenticated;
grant execute on function public.connect_fanout_events(int) to service_role;
grant execute on function public.connect_enqueue_weekly(timestamptz) to service_role;
grant execute on function public.connect_claim_deliveries(int) to service_role;
grant execute on function public.connect_purge() to service_role;
