-- ============================================================
-- 0041_multi_party.sql
-- ============================================================
-- 週ボスのパーティを複数組めるようにする（issue #130。0040 の仕様変更）。
--
-- - 1人が入れるパーティは最大5つ（1パーティは最大5人のまま）
-- - ワークアウト1回は、入っている全パーティのボスに1撃ずつ入る（振り分けはさせない）
-- - 週目標は全パーティで共通
-- - 宝箱はパーティごとに1つ。パーティが消えても報酬（トロフィー）は残す
-- - パーティに名前を付けられる（メンバーなら誰でも変更可）。未設定ならアプリがメンバー名で表示する
-- - 0040 を適用した時点でアプリは未配信のため、データの移行は不要（報酬は 0 行の前提で主キーを付け替える）

-- 1人が入れるパーティの上限。アプリの PartyBoss.maxPartiesPerUser と揃える。
create or replace function public.party_max_per_user()
returns int language sql immutable as $$ select 5 $$;

-- ------------------------------------------------------------
-- テーブル
-- ------------------------------------------------------------
alter table public.parties add column if not exists name text;
alter table public.parties drop constraint if exists parties_name_length;
alter table public.parties add constraint parties_name_length check (name is null or char_length(name) between 1 and 20);

drop index if exists public.party_members_one_party;
create index if not exists party_members_user_idx on public.party_members(user_id);

-- 報酬はパーティ×週ごと。パーティが消えた報酬（party_id = null）も残すため、代理キーにする。
alter table public.party_boss_rewards add column if not exists id uuid not null default gen_random_uuid();
alter table public.party_boss_rewards drop constraint if exists party_boss_rewards_pkey;
alter table public.party_boss_rewards add primary key (id);
create unique index if not exists party_boss_rewards_user_party_week
    on public.party_boss_rewards(user_id, party_id, week_start);

-- ------------------------------------------------------------
-- RLS（所属判定を「唯一のパーティ」から「所属しているか」へ）
-- ------------------------------------------------------------
create or replace function public.is_party_member(p_party uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from public.party_members where party_id = p_party and user_id = auth.uid())
$$;

drop policy if exists parties_member_read on public.parties;
create policy parties_member_read on public.parties
    for select using (public.is_party_member(id));

drop policy if exists party_members_member_read on public.party_members;
create policy party_members_member_read on public.party_members
    for select using (public.is_party_member(party_id));

drop policy if exists party_defeats_member_read on public.party_defeats;
create policy party_defeats_member_read on public.party_defeats
    for select using (public.is_party_member(party_id));

drop function if exists public.my_party_id();

-- ------------------------------------------------------------
-- RPC（パーティを指定する形へ。旧シグネチャは消す）
-- ------------------------------------------------------------
drop function if exists public.party_status(timestamptz);
drop function if exists public.claim_boss_reward(timestamptz);
drop function if exists public.leave_party();

-- 1つもパーティが無ければ1人パーティを作る（ボス画面を初めて開いたとき）。週目標は全所属に写す。
-- 返り値は最初に入ったパーティ。
create or replace function public.ensure_my_party(p_weekly_goal int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    pid uuid;
    goal int := least(greatest(coalesce(p_weekly_goal, 3), 1), 7);
begin
    if uid is null then raise exception 'not authenticated'; end if;
    select party_id into pid from public.party_members where user_id = uid order by joined_at limit 1;
    if pid is null then
        insert into public.parties (created_by) values (uid) returning id into pid;
        insert into public.party_members (party_id, user_id, weekly_goal) values (pid, uid, goal);
    else
        update public.party_members set weekly_goal = goal where user_id = uid and weekly_goal <> goal;
    end if;
    return pid;
end;
$$;

-- 新しいパーティを作る（別のグループ用）。上限を超えるなら例外。
create or replace function public.create_party(p_weekly_goal int, p_name text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    pid uuid;
    goal int := least(greatest(coalesce(p_weekly_goal, 3), 1), 7);
    clean text := nullif(btrim(coalesce(p_name, '')), '');
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if (select count(*) from public.party_members where user_id = uid) >= public.party_max_per_user() then
        raise exception 'too many parties' using errcode = 'P0001';
    end if;
    insert into public.parties (created_by, name) values (uid, left(clean, 20)) returning id into pid;
    insert into public.party_members (party_id, user_id, weekly_goal) values (pid, uid, goal);
    return pid;
end;
$$;

-- 招待リンクから参加する。今のパーティからは抜けない。満員・上限超過・存在しないときは例外。
create or replace function public.join_party(p_party_id uuid, p_weekly_goal int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    goal int := least(greatest(coalesce(p_weekly_goal, 3), 1), 7);
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if not exists (select 1 from public.parties where id = p_party_id) then
        raise exception 'party not found' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.party_members where party_id = p_party_id and user_id = uid) then
        update public.party_members set weekly_goal = goal where user_id = uid;
        return p_party_id;
    end if;
    if (select count(*) from public.party_members where user_id = uid) >= public.party_max_per_user() then
        raise exception 'too many parties' using errcode = 'P0001';
    end if;
    -- 同時参加で6人目が入らないよう、参加先の行をロックしてから数える。
    perform 1 from public.parties where id = p_party_id for update;
    if (select count(*) from public.party_members where party_id = p_party_id) >= 5 then
        raise exception 'party is full' using errcode = 'P0001';
    end if;
    insert into public.party_members (party_id, user_id, weekly_goal) values (p_party_id, uid, goal);
    return p_party_id;
end;
$$;

-- 指定したパーティを抜ける（空になったら消す。受け取った報酬は残る）。
create or replace function public.leave_party(p_party_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated'; end if;
    delete from public.party_members where party_id = p_party_id and user_id = uid;
    delete from public.parties p where p.id = p_party_id
        and not exists (select 1 from public.party_members m where m.party_id = p_party_id);
end;
$$;

-- パーティの名前を変える（メンバーなら誰でも）。空にすると未設定（メンバー名で表示）に戻る。
create or replace function public.rename_party(p_party_id uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare
    clean text := nullif(btrim(coalesce(p_name, '')), '');
begin
    if auth.uid() is null then raise exception 'not authenticated'; end if;
    if not public.is_party_member(p_party_id) then
        raise exception 'not a member' using errcode = 'P0001';
    end if;
    update public.parties set name = left(clean, 20) where id = p_party_id;
end;
$$;

-- 1つのパーティの今週（または指定した週）の状況。メンバーでなければ null。
create or replace function public.party_status(p_party_id uuid, p_week_start timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws timestamptz := public.party_week_start(coalesce(p_week_start, now()));
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if not public.is_party_member(p_party_id) then return null; end if;
    return json_build_object(
        'party_id', p_party_id,
        'name', (select name from public.parties where id = p_party_id),
        'week_start', ws,
        'boss_id', public.party_boss_id(ws),
        'hp', public.party_hp(p_party_id),
        'damage', public.party_damage(p_party_id, ws),
        'defeated', public.party_defeated(p_party_id, ws),
        'claimed', exists (select 1 from public.party_boss_rewards r
                           where r.user_id = uid and r.party_id = p_party_id and r.week_start = ws),
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
            where m.party_id = p_party_id
        ), '[]'::json)
    );
end;
$$;

-- 自分の全パーティの状況（入った順）。1つも無ければ空配列。
create or replace function public.my_parties(p_week_start timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated'; end if;
    return coalesce((
        select json_agg(public.party_status(m.party_id, p_week_start) order by m.joined_at)
        from public.party_members m where m.user_id = uid
    ), '[]'::json);
end;
$$;

-- 宝箱を開ける（パーティ×週）。今週か先週のぶんだけ。撃破していなければ例外、受け取り済みならそのまま返す。
create or replace function public.claim_boss_reward(p_party_id uuid, p_week_start timestamptz)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws timestamptz := public.party_week_start(p_week_start);
    current_ws timestamptz := public.party_week_start(now());
    rec public.party_boss_rewards;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if ws > current_ws or ws < current_ws - interval '7 days' then
        raise exception 'week out of range' using errcode = 'P0001';
    end if;
    select * into rec from public.party_boss_rewards
        where user_id = uid and party_id = p_party_id and week_start = ws;
    if found then
        return json_build_object('party_id', rec.party_id, 'boss_id', rec.boss_id, 'energy', rec.energy, 'week_start', rec.week_start);
    end if;
    if not public.is_party_member(p_party_id) or not public.party_defeated(p_party_id, ws) then
        raise exception 'boss not defeated' using errcode = 'P0001';
    end if;
    insert into public.party_boss_rewards (user_id, week_start, boss_id, energy, party_id)
        values (uid, ws, public.party_boss_id(ws), public.party_boss_reward_energy(), p_party_id)
        returning * into rec;
    return json_build_object('party_id', rec.party_id, 'boss_id', rec.boss_id, 'energy', rec.energy, 'week_start', rec.week_start);
end;
$$;

revoke all on function public.create_party(int, text) from public;
revoke all on function public.join_party(uuid, int) from public;
revoke all on function public.leave_party(uuid) from public;
revoke all on function public.rename_party(uuid, text) from public;
revoke all on function public.party_status(uuid, timestamptz) from public;
revoke all on function public.my_parties(timestamptz) from public;
revoke all on function public.claim_boss_reward(uuid, timestamptz) from public;
grant execute on function public.create_party(int, text) to authenticated;
grant execute on function public.join_party(uuid, int) to authenticated;
grant execute on function public.leave_party(uuid) to authenticated;
grant execute on function public.rename_party(uuid, text) to authenticated;
grant execute on function public.party_status(uuid, timestamptz) to authenticated;
grant execute on function public.my_parties(timestamptz) to authenticated;
grant execute on function public.claim_boss_reward(uuid, timestamptz) to authenticated;

-- ------------------------------------------------------------
-- 撃破の通知（入っている全パーティを見る）
-- ------------------------------------------------------------
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
  select * into cfg from public.push_config where id = 1;

  for pid in select party_id from public.party_members where user_id = new.user_id loop
    hp := public.party_hp(pid);
    continue when hp = 0;
    -- この1回で HP が 0 になったパーティだけ（同じ週に二度は鳴らない）。
    continue when not (public.party_damage(pid, ws, new.id) < hp and public.party_damage(pid, ws) >= hp);
    insert into public.party_defeats (party_id, week_start, defeated_by)
        values (pid, ws, new.user_id)
        on conflict do nothing;
    -- 1人パーティは倒した本人しかいないので、知らせる相手がいない。
    continue when (select count(*) from public.party_members where party_id = pid) < 2;
    continue when cfg.send_push_url is null or cfg.send_push_url = '';
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
  end loop;
  return new;
end;
$$;
