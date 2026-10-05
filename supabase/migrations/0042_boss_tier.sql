-- ============================================================
-- 0042_boss_tier.sql
-- ============================================================
-- 週ボスの強さのランク（弱い・中・強い）と、翌週のランクの投票（issue #133）。
--
-- - 週の途中で翌週のボスのランクにメンバーが投票し、日曜 23:59（JST）で締め切る。
--   月曜からそのランクのボスが出る。多数決で、同票は弱い方、票がゼロなら中
-- - HP: 弱い = 週目標の合計の6割（切り上げ・最低1）/ 中 = 合計 / 強い = 全員が目標+1回（合計 + 人数）
--   1人が削れる上限（目標+1）は変えないので、強いボスは全員が目標を1回超えて初めて倒せる
-- - 報酬に EXP を足す: 弱い 100 / 中 200 / 強い 400（パワー +60 は据え置き）
-- - 審査中の 1.6.0 が呼ぶ RPC のシグネチャと既存の項目は変えない（項目の追加だけ）

-- ------------------------------------------------------------
-- 投票
-- ------------------------------------------------------------
create table if not exists public.party_tier_votes (
    party_id   uuid not null references public.parties(id) on delete cascade,
    -- 投票先の週（その週の月曜 0:00 JST）。投票は常に「翌週」に向けて行う。
    week_start timestamptz not null,
    user_id    uuid not null references auth.users(id) on delete cascade,
    tier       text not null check (tier in ('weak', 'medium', 'strong')),
    updated_at timestamptz not null default now(),
    primary key (party_id, week_start, user_id)
);

alter table public.party_tier_votes enable row level security;
drop policy if exists party_tier_votes_member_read on public.party_tier_votes;
create policy party_tier_votes_member_read on public.party_tier_votes
    for select using (public.is_party_member(party_id));

-- その週のランク。いまのメンバーの票だけを数える。同票は弱い方、票がゼロなら中。
create or replace function public.party_tier(p_party uuid, p_week_start timestamptz)
returns text language sql stable security definer set search_path = public as $$
    select coalesce((
        select v.tier
        from public.party_tier_votes v
        join public.party_members m on m.party_id = v.party_id and m.user_id = v.user_id
        where v.party_id = p_party and v.week_start = p_week_start
        group by v.tier
        order by count(*) desc, case v.tier when 'weak' then 1 when 'medium' then 2 else 3 end
        limit 1
    ), 'medium')
$$;

-- ランクごとの報酬 EXP。アプリの PartyBoss.Tier.rewardExp と揃える。
create or replace function public.party_boss_reward_exp(p_tier text)
returns int language sql immutable as $$
    select case p_tier when 'weak' then 100 when 'strong' then 400 else 200 end
$$;

-- ------------------------------------------------------------
-- HP（ランクで変わる）。旧 party_hp(uuid) はこの migration の末尾で消す
-- ------------------------------------------------------------
create or replace function public.party_hp(p_party uuid, p_week_start timestamptz)
returns int language sql stable security definer set search_path = public as $$
    select coalesce((
        select case public.party_tier(p_party, p_week_start)
            when 'weak' then greatest(1, ceil(sum(weekly_goal) * 0.6))
            when 'strong' then sum(weekly_goal) + count(*)
            else sum(weekly_goal)
        end
        from public.party_members where party_id = p_party
        having count(*) > 0
    ), 0)::int
$$;

alter table public.party_defeats add column if not exists tier text;
alter table public.party_boss_rewards add column if not exists tier text not null default 'medium';
alter table public.party_boss_rewards add column if not exists exp int not null default 0;

create or replace function public.party_defeated(p_party uuid, p_week_start timestamptz)
returns boolean language plpgsql security definer set search_path = public as $$
declare
    hp int;
begin
    if exists (select 1 from public.party_defeats where party_id = p_party and week_start = p_week_start) then
        return true;
    end if;
    hp := public.party_hp(p_party, p_week_start);
    if hp > 0 and public.party_damage(p_party, p_week_start) >= hp then
        insert into public.party_defeats (party_id, week_start, tier)
            values (p_party, p_week_start, public.party_tier(p_party, p_week_start))
            on conflict do nothing;
        return true;
    end if;
    return false;
end;
$$;

-- ------------------------------------------------------------
-- RPC
-- ------------------------------------------------------------
-- 翌週のボスのランクに投票する（日曜 23:59 JST まで何度でも変えられる）。
create or replace function public.vote_boss_tier(p_party_id uuid, p_tier text)
returns void language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if p_tier not in ('weak', 'medium', 'strong') then
        raise exception 'invalid tier' using errcode = 'P0001';
    end if;
    if not public.is_party_member(p_party_id) then
        raise exception 'not a member' using errcode = 'P0001';
    end if;
    insert into public.party_tier_votes (party_id, week_start, user_id, tier)
        values (p_party_id, public.party_week_start(now()) + interval '7 days', uid, p_tier)
        on conflict (party_id, week_start, user_id) do update set tier = excluded.tier, updated_at = now();
end;
$$;

-- 状況に tier / reward_exp / 翌週の票（next_votes・my_next_vote）を足す。既存の項目はそのまま。
create or replace function public.party_status(p_party_id uuid, p_week_start timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws timestamptz := public.party_week_start(coalesce(p_week_start, now()));
    next_ws timestamptz := ws + interval '7 days';
    tier text;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if not public.is_party_member(p_party_id) then return null; end if;
    tier := public.party_tier(p_party_id, ws);
    return json_build_object(
        'party_id', p_party_id,
        'name', (select name from public.parties where id = p_party_id),
        'week_start', ws,
        'boss_id', public.party_boss_id(ws),
        'tier', tier,
        'reward_exp', public.party_boss_reward_exp(tier),
        'hp', public.party_hp(p_party_id, ws),
        'damage', public.party_damage(p_party_id, ws),
        'defeated', public.party_defeated(p_party_id, ws),
        'claimed', exists (select 1 from public.party_boss_rewards r
                           where r.user_id = uid and r.party_id = p_party_id and r.week_start = ws),
        'next_votes', json_build_object(
            'weak',   (select count(*) from public.party_tier_votes v join public.party_members m
                         on m.party_id = v.party_id and m.user_id = v.user_id
                       where v.party_id = p_party_id and v.week_start = next_ws and v.tier = 'weak'),
            'medium', (select count(*) from public.party_tier_votes v join public.party_members m
                         on m.party_id = v.party_id and m.user_id = v.user_id
                       where v.party_id = p_party_id and v.week_start = next_ws and v.tier = 'medium'),
            'strong', (select count(*) from public.party_tier_votes v join public.party_members m
                         on m.party_id = v.party_id and m.user_id = v.user_id
                       where v.party_id = p_party_id and v.week_start = next_ws and v.tier = 'strong')
        ),
        'my_next_vote', (select v.tier from public.party_tier_votes v
                         where v.party_id = p_party_id and v.week_start = next_ws and v.user_id = uid),
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

-- 宝箱: 撃破したランクの EXP も記録して返す。
create or replace function public.claim_boss_reward(p_party_id uuid, p_week_start timestamptz)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws timestamptz := public.party_week_start(p_week_start);
    current_ws timestamptz := public.party_week_start(now());
    tier text;
    rec public.party_boss_rewards;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if ws > current_ws or ws < current_ws - interval '7 days' then
        raise exception 'week out of range' using errcode = 'P0001';
    end if;
    select * into rec from public.party_boss_rewards
        where user_id = uid and party_id = p_party_id and week_start = ws;
    if not found then
        if not public.is_party_member(p_party_id) or not public.party_defeated(p_party_id, ws) then
            raise exception 'boss not defeated' using errcode = 'P0001';
        end if;
        -- 撃破したときのランク（記録が無ければいまのランク）。
        tier := coalesce((select d.tier from public.party_defeats d
                          where d.party_id = p_party_id and d.week_start = ws),
                         public.party_tier(p_party_id, ws));
        insert into public.party_boss_rewards (user_id, week_start, boss_id, energy, party_id, tier, exp)
            values (uid, ws, public.party_boss_id(ws), public.party_boss_reward_energy(), p_party_id,
                    tier, public.party_boss_reward_exp(tier))
            returning * into rec;
    end if;
    return json_build_object('party_id', rec.party_id, 'boss_id', rec.boss_id, 'energy', rec.energy,
                             'week_start', rec.week_start, 'tier', rec.tier, 'exp', rec.exp);
end;
$$;

revoke all on function public.vote_boss_tier(uuid, text) from public;
grant execute on function public.vote_boss_tier(uuid, text) to authenticated;
revoke all on function public.party_tier(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.party_hp(uuid, timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 撃破の通知（HP をランクで計算し、撃破時のランクを記録する）
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
    hp := public.party_hp(pid, ws);
    continue when hp = 0;
    -- この1回で HP が 0 になったパーティだけ（同じ週に二度は鳴らない）。
    continue when not (public.party_damage(pid, ws, new.id) < hp and public.party_damage(pid, ws) >= hp);
    insert into public.party_defeats (party_id, week_start, defeated_by, tier)
        values (pid, ws, new.user_id, public.party_tier(pid, ws))
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

-- 旧 HP（ランク無し）はどこからも呼ばれなくなった。
drop function if exists public.party_hp(uuid);
