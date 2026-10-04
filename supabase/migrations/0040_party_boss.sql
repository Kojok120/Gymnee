-- ============================================================
-- 0040_party_boss.sql
-- ============================================================
-- 友達と倒す「週ボス」（issue #128）。
--
-- 設計の前提:
-- - 1人1パーティ・最大5人。パーティが無い人も「1人パーティ」として同じ仕組みに乗る（ソロ戦）
-- - 週は月曜 0:00（JST）で切り替わる。全員で同じ週を共有するので、端末の週（ロケール依存）ではなく
--   サーバーで決める
-- - ボスの HP = メンバーの週目標の合計。完了したワークアウト1回 = 1撃。
--   1人が削れるのは「自分の目標 + 1」まで（誰か1人が全部倒してしまわないように）
-- - ダメージは同期済みの workouts からサーバーで数える。クライアントには書かせない
-- - 報酬の受け取りもサーバーで撃破を検証してから記録する（所持はサーバーが正）
-- - パーティ・メンバー・報酬はすべて RPC 経由でしか書けない（テーブルへの直接の書き込みは不可）

-- ------------------------------------------------------------
-- 週とボス
-- ------------------------------------------------------------
-- その時刻が属する週の開始（月曜 0:00 JST）。
create or replace function public.party_week_start(ts timestamptz)
returns timestamptz language sql immutable as $$
    select date_trunc('week', ts at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo'
$$;

-- 週ごとのボス。アプリの PartyBoss.catalog と同じ並び・同じ起点で回す。
-- 起点 2026-01-05（月）からの経過週数 mod ボス数。
create or replace function public.party_boss_id(week_start timestamptz)
returns text language sql immutable as $$
    select (array['sloth_slime','couch_golem','snooze_dragon','junk_kraken'])[
        (((floor(extract(epoch from (week_start - timestamptz '2026-01-05 00:00:00+09')) / 604800))::int % 4 + 4) % 4) + 1
    ]
$$;

-- 撃破の報酬（テストステロンパワー）。アプリの PartyBoss.rewardEnergy と揃える。
create or replace function public.party_boss_reward_energy()
returns int language sql immutable as $$ select 60 $$;

-- ------------------------------------------------------------
-- テーブル
-- ------------------------------------------------------------
create table if not exists public.parties (
    id         uuid primary key default gen_random_uuid(),
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.party_members (
    party_id    uuid not null references public.parties(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    -- ボスの HP と、1人が削れる上限の元になる。アプリの週目標（1〜7）を RPC で写す。
    weekly_goal int not null default 3 check (weekly_goal between 1 and 7),
    joined_at   timestamptz not null default now(),
    primary key (party_id, user_id)
);
-- 1人1パーティ。
create unique index if not exists party_members_one_party on public.party_members(user_id);

create table if not exists public.party_boss_rewards (
    user_id    uuid not null references auth.users(id) on delete cascade,
    week_start timestamptz not null,
    boss_id    text not null,
    energy     int not null,
    -- 受け取った時点のパーティ（集計用）。パーティが消えても報酬は残す。
    party_id   uuid references public.parties(id) on delete set null,
    claimed_at timestamptz not null default now(),
    primary key (user_id, week_start)
);

-- 撃破の記録。撃破後にメンバーが増えて HP が上がっても、その週は撃破済みのままにする
-- （宝箱をまだ開けていないメンバーが受け取れなくならないように）。
create table if not exists public.party_defeats (
    party_id    uuid not null references public.parties(id) on delete cascade,
    week_start  timestamptz not null,
    defeated_by uuid references auth.users(id) on delete set null,
    defeated_at timestamptz not null default now(),
    primary key (party_id, week_start)
);

-- ------------------------------------------------------------
-- RLS（読みだけ。書きは RPC）
-- ------------------------------------------------------------
-- party_members の自己参照ポリシーは再帰するので、SECURITY DEFINER の関数で判定する。
create or replace function public.my_party_id()
returns uuid language sql stable security definer set search_path = public as $$
    select party_id from public.party_members where user_id = auth.uid()
$$;

alter table public.parties enable row level security;
alter table public.party_members enable row level security;
alter table public.party_boss_rewards enable row level security;
alter table public.party_defeats enable row level security;

drop policy if exists party_defeats_member_read on public.party_defeats;
create policy party_defeats_member_read on public.party_defeats
    for select using (party_id = public.my_party_id());

drop policy if exists parties_member_read on public.parties;
create policy parties_member_read on public.parties
    for select using (id = public.my_party_id());

drop policy if exists party_members_member_read on public.party_members;
create policy party_members_member_read on public.party_members
    for select using (party_id = public.my_party_id());

drop policy if exists party_boss_rewards_owner_read on public.party_boss_rewards;
create policy party_boss_rewards_owner_read on public.party_boss_rewards
    for select using (user_id = auth.uid());

-- ------------------------------------------------------------
-- ダメージと HP
-- ------------------------------------------------------------
-- その週にメンバーが完了したワークアウトの回数。exclude_workout は撃破通知の「この1回の前」の計算用。
create or replace function public.party_member_hits(p_user uuid, p_week_start timestamptz, p_exclude_workout uuid default null)
returns int language sql stable security definer set search_path = public as $$
    select count(*)::int from public.workouts w
    where w.user_id = p_user
      and w.completed_at is not null
      and w.completed_at >= p_week_start
      and w.completed_at < p_week_start + interval '7 days'
      and (p_exclude_workout is null or w.id <> p_exclude_workout)
$$;

create or replace function public.party_hp(p_party uuid)
returns int language sql stable security definer set search_path = public as $$
    select coalesce(sum(weekly_goal), 0)::int from public.party_members where party_id = p_party
$$;

-- パーティの与ダメージ合計。1人あたり「目標 + 1」で頭打ち。
create or replace function public.party_damage(p_party uuid, p_week_start timestamptz, p_exclude_workout uuid default null)
returns int language sql stable security definer set search_path = public as $$
    select coalesce(sum(least(public.party_member_hits(m.user_id, p_week_start, p_exclude_workout), m.weekly_goal + 1)), 0)::int
    from public.party_members m where m.party_id = p_party
$$;

-- その週に倒したか。記録があれば撃破済み。記録が無くても（後から同期された記録などで）
-- ダメージが HP に届いていれば撃破済みとし、そのとき記録を残す。
create or replace function public.party_defeated(p_party uuid, p_week_start timestamptz)
returns boolean language plpgsql security definer set search_path = public as $$
declare
    hp int;
begin
    if exists (select 1 from public.party_defeats where party_id = p_party and week_start = p_week_start) then
        return true;
    end if;
    hp := public.party_hp(p_party);
    if hp > 0 and public.party_damage(p_party, p_week_start) >= hp then
        insert into public.party_defeats (party_id, week_start) values (p_party, p_week_start)
            on conflict do nothing;
        return true;
    end if;
    return false;
end;
$$;

-- ------------------------------------------------------------
-- RPC
-- ------------------------------------------------------------
-- 自分のパーティを返す。無ければ1人パーティを作る。週目標も写す。
create or replace function public.ensure_my_party(p_weekly_goal int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    pid uuid;
    goal int := least(greatest(coalesce(p_weekly_goal, 3), 1), 7);
begin
    if uid is null then raise exception 'not authenticated'; end if;
    select party_id into pid from public.party_members where user_id = uid;
    if pid is null then
        insert into public.parties (created_by) values (uid) returning id into pid;
        insert into public.party_members (party_id, user_id, weekly_goal) values (pid, uid, goal);
    else
        update public.party_members set weekly_goal = goal where user_id = uid and weekly_goal <> goal;
    end if;
    return pid;
end;
$$;

-- 招待リンクから参加する。元のパーティは抜ける（空になったら消す）。満員（5人）なら例外。
create or replace function public.join_party(p_party_id uuid, p_weekly_goal int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    current_pid uuid;
    goal int := least(greatest(coalesce(p_weekly_goal, 3), 1), 7);
    member_count int;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if not exists (select 1 from public.parties where id = p_party_id) then
        raise exception 'party not found' using errcode = 'P0002';
    end if;
    select party_id into current_pid from public.party_members where user_id = uid;
    if current_pid = p_party_id then
        update public.party_members set weekly_goal = goal where user_id = uid;
        return p_party_id;
    end if;
    -- 同時参加で6人目が入らないよう、参加先の行をロックしてから数える。
    perform 1 from public.parties where id = p_party_id for update;
    select count(*) into member_count from public.party_members where party_id = p_party_id;
    if member_count >= 5 then
        raise exception 'party is full' using errcode = 'P0001';
    end if;
    if current_pid is not null then
        delete from public.party_members where user_id = uid;
        delete from public.parties p where p.id = current_pid
            and not exists (select 1 from public.party_members m where m.party_id = current_pid);
    end if;
    insert into public.party_members (party_id, user_id, weekly_goal) values (p_party_id, uid, goal);
    return p_party_id;
end;
$$;

-- パーティを抜ける（空になったら消す）。次にボスを開くと1人パーティが作られる。
create or replace function public.leave_party()
returns void language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    current_pid uuid;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    select party_id into current_pid from public.party_members where user_id = uid;
    if current_pid is null then return; end if;
    delete from public.party_members where user_id = uid;
    delete from public.parties p where p.id = current_pid
        and not exists (select 1 from public.party_members m where m.party_id = current_pid);
end;
$$;

-- 設定で週目標を変えたとき、パーティに入っていれば写す（入っていなければ何もしない）。
create or replace function public.set_party_weekly_goal(p_weekly_goal int)
returns void language sql security definer set search_path = public as $$
    update public.party_members
    set weekly_goal = least(greatest(coalesce(p_weekly_goal, 3), 1), 7)
    where user_id = auth.uid()
$$;

-- 今週（または指定した週）の自分のパーティの状況。パーティが無ければ null。
create or replace function public.party_status(p_week_start timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    pid uuid;
    ws timestamptz := public.party_week_start(coalesce(p_week_start, now()));
    hp int;
    dmg int;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    select party_id into pid from public.party_members where user_id = uid;
    if pid is null then return null; end if;
    hp := public.party_hp(pid);
    dmg := public.party_damage(pid, ws);
    return json_build_object(
        'party_id', pid,
        'week_start', ws,
        'boss_id', public.party_boss_id(ws),
        'hp', hp,
        'damage', dmg,
        'defeated', public.party_defeated(pid, ws),
        'claimed', exists (select 1 from public.party_boss_rewards r where r.user_id = uid and r.week_start = ws),
        'members', coalesce((
            select json_agg(json_build_object(
                'user_id', m.user_id,
                'display_name', coalesce(pr.display_name, 'メンバー'),
                'avatar_url', pr.avatar_url,
                'weekly_goal', m.weekly_goal,
                'hits', public.party_member_hits(m.user_id, ws)
            ) order by m.joined_at)
            from public.party_members m
            left join public.profiles pr on pr.id = m.user_id
            where m.party_id = pid
        ), '[]'::json)
    );
end;
$$;

-- 宝箱を開ける。今週か先週のぶんだけ。撃破していなければ例外、受け取り済みならそのまま返す。
create or replace function public.claim_boss_reward(p_week_start timestamptz)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    pid uuid;
    ws timestamptz := public.party_week_start(p_week_start);
    current_ws timestamptz := public.party_week_start(now());
    rec public.party_boss_rewards;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if ws > current_ws or ws < current_ws - interval '7 days' then
        raise exception 'week out of range' using errcode = 'P0001';
    end if;
    select * into rec from public.party_boss_rewards where user_id = uid and week_start = ws;
    if found then
        return json_build_object('boss_id', rec.boss_id, 'energy', rec.energy, 'week_start', rec.week_start);
    end if;
    select party_id into pid from public.party_members where user_id = uid;
    if pid is null or not public.party_defeated(pid, ws) then
        raise exception 'boss not defeated' using errcode = 'P0001';
    end if;
    insert into public.party_boss_rewards (user_id, week_start, boss_id, energy, party_id)
        values (uid, ws, public.party_boss_id(ws), public.party_boss_reward_energy(), pid)
        returning * into rec;
    return json_build_object('boss_id', rec.boss_id, 'energy', rec.energy, 'week_start', rec.week_start);
end;
$$;

revoke all on function public.ensure_my_party(int) from public;
revoke all on function public.join_party(uuid, int) from public;
revoke all on function public.leave_party() from public;
revoke all on function public.set_party_weekly_goal(int) from public;
revoke all on function public.party_status(timestamptz) from public;
revoke all on function public.claim_boss_reward(timestamptz) from public;
grant execute on function public.ensure_my_party(int) to authenticated;
grant execute on function public.join_party(uuid, int) to authenticated;
grant execute on function public.leave_party() to authenticated;
grant execute on function public.set_party_weekly_goal(int) to authenticated;
grant execute on function public.party_status(timestamptz) to authenticated;
grant execute on function public.claim_boss_reward(timestamptz) to authenticated;
-- 内部の集計関数は他人のワークアウト件数を数えられるので、外から直接呼ばせない。
revoke all on function public.party_member_hits(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.party_damage(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.party_hp(uuid) from public, anon, authenticated;
revoke all on function public.party_defeated(uuid, timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 撃破の通知
-- ------------------------------------------------------------
-- 受け取る側: パーティのボス撃破の通知を受け取るか。
alter table public.profiles add column if not exists notify_party boolean not null default true;

-- ワークアウトの完了でボスの HP が 0 になった瞬間だけ、メンバーへ知らせる。
-- 「この1回を除いたダメージ < HP <= 含めたダメージ」のときだけ送るので、同じ週に二度は鳴らない。
create or replace function public.notify_boss_defeated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_config;
  pid uuid;
  ws timestamptz;
  hp int;
begin
  if new.completed_at is null then return new; end if;
  if tg_op = 'UPDATE' and old.completed_at is not null then return new; end if;
  -- 一括同期・後追い記録での暴発を防ぐ（今週ぶんの、いま完了した記録だけ）。
  if new.completed_at < now() - interval '10 minutes' then return new; end if;
  ws := public.party_week_start(new.completed_at);
  if ws <> public.party_week_start(now()) then return new; end if;

  select party_id into pid from public.party_members where user_id = new.user_id;
  if pid is null then return new; end if;
  hp := public.party_hp(pid);
  if hp = 0 then return new; end if;
  if not (public.party_damage(pid, ws, new.id) < hp and public.party_damage(pid, ws) >= hp) then
    return new;
  end if;
  insert into public.party_defeats (party_id, week_start, defeated_by)
      values (pid, ws, new.user_id)
      on conflict do nothing;
  -- 1人パーティは倒した本人しかいないので、知らせる相手がいない。
  if (select count(*) from public.party_members where party_id = pid) < 2 then return new; end if;

  select * into cfg from public.push_config where id = 1;
  if cfg.send_push_url is null or cfg.send_push_url = '' then
    return new;
  end if;
  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object(
                 'event', 'boss_defeated',
                 'partyId', pid,
                 'bossId', public.party_boss_id(ws),
                 'defeatedBy', new.user_id
               )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_boss_defeated on public.workouts;
create trigger trg_notify_boss_defeated
  after insert or update of completed_at on public.workouts
  for each row execute function public.notify_boss_defeated();
