-- 必殺技: パワーを使って週ボスに 1撃（issue #150）。
--
-- ボスへの攻撃はワークアウトの完了だけで、週の後半に目標へ届かないと分かると取り返せなかった。
-- 貯めたパワー（ワークアウトと拾い物で貯まる）を使い、1人につきパーティごと週1回だけ 1撃を出せるようにする。
-- - パワーの残高は端末で計算する（遠征と同じ）。サーバーは「出した記録」と使ったパワーを持ち、
--   アプリはその合計を残高から引く（宝箱のパワーを足すのと同じ控え方）
-- - 残高はサーバーで確かめられないが、効き目は週1回・1撃に限られるので、払わずに出しても得は広がらない
-- - ジョブのスキル・連携の判定には入れない（ワークアウトの攻撃だけで決まる）。1人あたりの上限（目標＋1）の外
-- - 撃破・あと1撃の通知はワークアウトのときと同じ

create table if not exists public.party_special_attacks (
    id           uuid primary key default gen_random_uuid(),
    party_id     uuid not null references public.parties(id) on delete cascade,
    user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
    week_start   timestamptz not null,
    energy_spent int not null check (energy_spent > 0),
    created_at   timestamptz not null default now(),
    unique (party_id, user_id, week_start)
);
create index if not exists party_special_attacks_week_idx on public.party_special_attacks (party_id, week_start);
alter table public.party_special_attacks enable row level security;
-- 読めるのは自分の記録だけ（使ったパワーの合計を出すため）。出すのは下の RPC だけなので書き込みのポリシーは置かない。
drop policy if exists party_special_attacks_select_own on public.party_special_attacks;
create policy party_special_attacks_select_own on public.party_special_attacks
  for select using (user_id = auth.uid());

-- 必殺技に使うパワー（アプリの PartyBoss.specialAttackCost と同じ値）。
create or replace function public.party_special_attack_cost()
returns int language sql immutable as $$ select 100 $$;

-- パーティの与ダメージ合計（基本 + 連携 + スキル + 必殺技）。シグネチャは 0040 のまま。
-- p_exclude_workout（「この1回の前」の計算）は必殺技には関係しない。
create or replace function public.party_damage(p_party uuid, p_week_start timestamptz, p_exclude_workout uuid default null)
returns int language sql stable security definer set search_path = public as $$
    select (
        coalesce((select sum(a.base + a.skill + a.combo)
                  from public.party_attacks(p_party, p_week_start, p_exclude_workout) a), 0)
        + (select count(*) from public.party_special_attacks s
           where s.party_id = p_party and s.week_start = p_week_start)
    )::int
$$;

-- ------------------------------------------------------------
-- 状況（0043 の party_status。攻撃の一覧とダメージに必殺技を足す。ほかは 0043 のまま）
-- ------------------------------------------------------------
create or replace function public.party_status(p_party_id uuid, p_week_start timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws timestamptz := public.party_week_start(coalesce(p_week_start, now()));
    next_ws timestamptz := ws + interval '7 days';
    tier text;
    hp int;
    dmg int;
    attacks json;
    defeated boolean;
begin
    if uid is null then raise exception 'not authenticated'; end if;
    if not public.is_party_member(p_party_id) then return null; end if;
    tier := public.party_tier(p_party_id, ws);
    hp := public.party_hp(p_party_id, ws);
    -- 攻撃の一覧とダメージは1回の集計から作る（ジョブの判定を何度も走らせない）。
    -- 必殺技（0045）も同じ一覧に時刻順で混ぜる。category は 'special'、内訳は基本の 1 だけ。
    -- ワークアウトの攻撃の id（md5(workout_id)）は 0043 のまま（アプリの「再生済み」の判定が変わらない）。
    with atk as (
        select a.workout_id::text as key, a.user_id, a.completed_at as at, a.day,
               public.party_workout_category(a.workout_id) as category, a.base, a.skill, a.combo
        from public.party_attacks(p_party_id, ws) a
        union all
        select s.id::text, s.user_id, s.created_at, (s.created_at at time zone 'Asia/Tokyo')::date,
               'special', 1, 0, 0
        from public.party_special_attacks s
        where s.party_id = p_party_id and s.week_start = ws
    )
    select coalesce(json_agg(json_build_object(
               'id', md5(atk.key),
               'user_id', atk.user_id,
               'day', to_char(atk.day, 'YYYY-MM-DD'),
               'category', atk.category,
               'base', atk.base,
               'skill', atk.skill,
               'combo', atk.combo
           ) order by atk.at, atk.key), '[]'::json),
           coalesce(sum(atk.base + atk.skill + atk.combo), 0)::int
      into attacks, dmg
      from atk;
    -- party_defeated と同じ判定（記録があれば撃破済み。無くても届いていれば記録する）。
    defeated := exists (select 1 from public.party_defeats where party_id = p_party_id and week_start = ws);
    if not defeated and hp > 0 and dmg >= hp then
        insert into public.party_defeats (party_id, week_start, tier)
            values (p_party_id, ws, tier)
            on conflict do nothing;
        defeated := true;
    end if;
    return json_build_object(
        'party_id', p_party_id,
        'name', (select name from public.parties where id = p_party_id),
        'week_start', ws,
        'boss_id', public.party_boss_id(ws),
        'tier', tier,
        'reward_exp', public.party_boss_reward_exp(tier),
        'hp', hp,
        'damage', dmg,
        'defeated', defeated,
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
        'attacks', attacks,
        'members', coalesce((
            select json_agg(json_build_object(
                'user_id', m.user_id,
                'display_name', coalesce(pr.display_name, 'メンバー'),
                'avatar_url', pr.avatar_url,
                'weekly_goal', m.weekly_goal,
                'hits', public.party_member_hits(m.user_id, ws),
                'job', public.party_member_job(m.user_id, ws),
                'look', pr.character_look,
                -- トレ中。見える範囲は live_sessions の RLS と同じ（本人か、フォローしている相手の生きている配信）。
                'live_session_id', (
                    select s.id from public.live_sessions s
                    where s.user_id = m.user_id
                      and public.is_live(s)
                      and (m.user_id = uid or public.is_following(m.user_id))
                    order by s.started_at desc
                    limit 1
                )
            ) order by m.joined_at)
            from public.party_members m
            left join public.profiles pr on pr.id = m.user_id
            where m.party_id = p_party_id
        ), '[]'::json)
    );
end;
$$;

-- ------------------------------------------------------------
-- 必殺技を出す
-- ------------------------------------------------------------
-- 今週のボスに 1撃。出したあとの状況（party_status）を返す。
-- 失敗: not authenticated / not a member / no boss / already defeated / already used
create or replace function public.party_special_attack(p_party_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ws timestamptz := public.party_week_start(now());
  cfg public.push_config;
  hp int;
  before_dmg int;
  after_dmg int;
  member_count int;
  inserted int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if not public.is_party_member(p_party_id) then raise exception 'not a member'; end if;
  hp := public.party_hp(p_party_id, ws);
  if hp = 0 then raise exception 'no boss'; end if;
  before_dmg := public.party_damage(p_party_id, ws);
  if before_dmg >= hp
     or exists (select 1 from public.party_defeats where party_id = p_party_id and week_start = ws) then
    raise exception 'already defeated';
  end if;

  insert into public.party_special_attacks (party_id, user_id, week_start, energy_spent)
      values (p_party_id, uid, ws, public.party_special_attack_cost())
      on conflict (party_id, user_id, week_start) do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then raise exception 'already used'; end if;

  after_dmg := public.party_damage(p_party_id, ws);
  member_count := (select count(*) from public.party_members where party_id = p_party_id);
  select * into cfg from public.push_config where id = 1;

  -- 撃破・あと1撃の知らせ（notify_boss_defeated と同じ条件と中身）。
  if after_dmg >= hp then
    insert into public.party_defeats (party_id, week_start, defeated_by, tier)
        values (p_party_id, ws, uid, public.party_tier(p_party_id, ws))
        on conflict do nothing;
    if member_count >= 2 and coalesce(cfg.send_push_url, '') <> '' then
      perform net.http_post(
        url     := cfg.send_push_url,
        headers := jsonb_build_object('Content-Type', 'application/json', 'X-Push-Secret', coalesce(cfg.push_secret, '')),
        body    := jsonb_build_object('event', 'boss_defeated', 'partyId', p_party_id,
                                      'bossId', public.party_boss_id(ws), 'defeatedBy', uid)
      );
    end if;
  elsif hp - after_dmg = 1 and member_count >= 2 then
    insert into public.party_reach_notices (party_id, week_start, attacker)
        values (p_party_id, ws, uid)
        on conflict do nothing;
    get diagnostics inserted = row_count;
    if inserted > 0 and coalesce(cfg.send_push_url, '') <> '' then
      perform net.http_post(
        url     := cfg.send_push_url,
        headers := jsonb_build_object('Content-Type', 'application/json', 'X-Push-Secret', coalesce(cfg.push_secret, '')),
        body    := jsonb_build_object('event', 'boss_reach', 'partyId', p_party_id,
                                      'bossId', public.party_boss_id(ws), 'attackerId', uid)
      );
    end if;
  end if;

  return public.party_status(p_party_id, ws);
end;
$$;

-- ------------------------------------------------------------
-- 権限
-- ------------------------------------------------------------
revoke all on function public.party_special_attack(uuid) from public, anon;
grant execute on function public.party_special_attack(uuid) to authenticated;
revoke all on function public.party_damage(uuid, timestamptz, uuid) from public, anon, authenticated;
