-- ============================================================
-- 0037_live_sessions.sql
-- ============================================================
-- 「いまトレーニング中」の配信と、それに対する応援。
--
-- 設計の前提:
-- - **既定はオフ**。トレ中であることをフォロワーに知らせるのは居場所と行動を実時間で明かすことなので、
--   `profiles.share_live_start` を明示的にオンにした人だけが配信する
-- - ローカル（SwiftData）には持たない。オンラインでしか意味がない情報で、
--   端末を正にすると「終わっていないセッション」がオフラインで残り続ける
-- - 生きているセッションには**期限**を設ける。アプリを落として終了できなかった行が
--   いつまでも「トレーニング中」として出続けるのを防ぐ

-- 生きているとみなす上限。これを超えたら終了扱い（＝配信も応援も止まる）。
create or replace function public.live_session_max_duration()
returns interval language sql immutable as $$ select interval '3 hours' $$;

create table if not exists public.live_sessions (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
    started_at timestamptz not null default now(),
    ended_at   timestamptz,
    updated_at timestamptz not null default now()
);
create index if not exists live_sessions_user_idx on public.live_sessions(user_id);
create index if not exists live_sessions_active_idx on public.live_sessions(started_at desc) where ended_at is null;

-- 生きているか（期限切れは自動で終了扱い）。
create or replace function public.is_live(s public.live_sessions)
returns boolean
language sql stable as $$
    select s.ended_at is null and s.started_at > now() - public.live_session_max_duration();
$$;

alter table public.live_sessions enable row level security;

drop policy if exists live_sessions_owner_all on public.live_sessions;
create policy live_sessions_owner_all on public.live_sessions
    for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- フォロワーは**生きている間だけ**見える。終わったセッションは追えない。
drop policy if exists live_sessions_follower_read on public.live_sessions;
create policy live_sessions_follower_read on public.live_sessions
    for select using (
        public.is_following(user_id)
        and ended_at is null
        and started_at > now() - public.live_session_max_duration()
    );

-- ============================================================
-- 応援
-- ============================================================
create table if not exists public.session_cheers (
    id         uuid primary key default gen_random_uuid(),
    session_id uuid not null references public.live_sessions(id) on delete cascade,
    user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
    -- スタンプの種類。post_reactions と同じ語彙に揃える。
    kind       text not null default 'fire' check (kind in ('fire','clap','strong','like')),
    created_at timestamptz not null default now()
);
-- 同じ人が同じスタンプを連打しても 1 回。応援の押し合いにしない。
create unique index if not exists session_cheers_unique on public.session_cheers(session_id, user_id, kind);
create index if not exists session_cheers_session_idx on public.session_cheers(session_id);

alter table public.session_cheers enable row level security;

-- 応援できるのは、生きているセッションを持つ人をフォローしている人だけ（自分自身は除く）。
drop policy if exists session_cheers_insert on public.session_cheers;
create policy session_cheers_insert on public.session_cheers
    for insert with check (
        user_id = auth.uid()
        and exists (
            select 1 from public.live_sessions s
            where s.id = session_id
              and s.user_id <> auth.uid()
              and public.is_following(s.user_id)
              and s.ended_at is null
              and s.started_at > now() - public.live_session_max_duration()
        )
    );

-- 読めるのは、応援した本人と、応援されたセッションの持ち主。
drop policy if exists session_cheers_read on public.session_cheers;
create policy session_cheers_read on public.session_cheers
    for select using (
        user_id = auth.uid()
        or exists (select 1 from public.live_sessions s where s.id = session_id and s.user_id = auth.uid())
    );

drop policy if exists session_cheers_delete on public.session_cheers;
create policy session_cheers_delete on public.session_cheers
    for delete using (user_id = auth.uid());

-- ============================================================
-- 通知の設定
-- ============================================================
-- 送る側: トレ開始をフォロワーに知らせるか。**既定はオフ**。
alter table public.profiles add column if not exists share_live_start boolean not null default false;
-- 受け取る側: フォロー中の人のトレ開始通知を受け取るか。
alter table public.profiles add column if not exists notify_live_start boolean not null default true;
-- トレ中に応援が届いたことの通知。
alter table public.profiles add column if not exists notify_cheer boolean not null default true;

-- ============================================================
-- push
-- ============================================================
-- トレ開始 → フォロワーへ。
create or replace function public.notify_live_start()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_config;
  shares boolean;
begin
  select * into cfg from public.push_config where id = 1;
  if cfg.send_push_url is null or cfg.send_push_url = '' then
    return new;
  end if;
  -- 配信をオンにしている人だけ。既定オフなので、明示的に許可した人しか流れない。
  select share_live_start into shares from public.profiles where id = new.user_id;
  if coalesce(shares, false) is not true then
    return new;
  end if;
  -- バックフィルや時刻ずれで過去のセッションが流れないようにする。
  if new.started_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'live_start', 'sessionId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_live_start on public.live_sessions;
create trigger trg_notify_live_start
  after insert on public.live_sessions
  for each row execute function public.notify_live_start();

-- 応援 → トレ中の人へ。
create or replace function public.notify_session_cheer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_config;
begin
  select * into cfg from public.push_config where id = 1;
  if cfg.send_push_url is null or cfg.send_push_url = '' then
    return new;
  end if;
  if new.created_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'cheer', 'cheerId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_session_cheer on public.session_cheers;
create trigger trg_notify_session_cheer
  after insert on public.session_cheers
  for each row execute function public.notify_session_cheer();
