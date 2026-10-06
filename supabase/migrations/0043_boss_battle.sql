-- ============================================================
-- 0043_boss_battle.sql
-- ============================================================
-- 週ボスをダンジョンの戦闘にする（issue #137）。
--
-- - ダメージ = 基本 + 連携 + スキル
--   - 基本: 完了したワークアウト1回 = 1撃、1人あたり「目標 + 1」まで（0040 から変えない）
--   - 連携: 同じ日（JST）に2人以上が攻撃したら、その日に1回 +1
--   - スキル: 週の頭で決まるジョブごとの条件を満たすと、1人週1回まで +1
-- - ジョブは前の28日間に完了したワークアウトの系統（上半身・下半身・体幹・有酸素・全身）で決まる。
--   半分を超える系統があればそのジョブ、無ければ（バランス型・記録なし）勇者
-- - スキルと連携の条件は**ワークアウトの完了日時だけ**で決まる（部位はジョブを決める過去の記録にだけ使う）。
--   セットは親のワークアウトより後に同期されるので、部位を条件にするとトリガーの時点で判定できない
-- - 今週の攻撃の一覧（誰が・何日・どの系統・ダメージの内訳）を状況に足す。時刻は返さない
-- - 自分のキャラの見た目を profiles に載せ、仲間の画面で本人の姿を描けるようにする
-- - 「あと1撃」の通知: 攻撃で残り HP がちょうど 1 になったとき、攻撃した本人以外へ（パーティ×週で1回）
-- - 1.7.0 以前のアプリが呼ぶ RPC のシグネチャと既存の項目は変えない（項目の追加だけ）

-- ------------------------------------------------------------
-- キャラの見た目
-- ------------------------------------------------------------
-- 体格・スキン・髪・アクセサリー・装備・進化段階の ID だけを持つ（描画はアプリ側）。
-- プロフィールは全員参照可なので、見た目も同じ範囲で見える（アバターと同じ扱い）。
alter table public.profiles add column if not exists character_look jsonb;
alter table public.profiles drop constraint if exists profiles_character_look_shape;
alter table public.profiles add constraint profiles_character_look_shape check (
    character_look is null
    or (jsonb_typeof(character_look) = 'object' and octet_length(character_look::text) <= 1024)
);

-- 自分の見た目を載せる（null で消す）。プロフィールの同期（端末の SwiftData が正）とは別の列で、
-- 同期の upsert は列を指定するのでここを上書きしない。
create or replace function public.set_character_look(p_look jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'not authenticated'; end if;
    if p_look is not null
       and (jsonb_typeof(p_look) <> 'object' or octet_length(p_look::text) > 1024) then
        raise exception 'invalid look' using errcode = 'P0001';
    end if;
    update public.profiles set character_look = p_look where id = auth.uid();
end;
$$;

-- ------------------------------------------------------------
-- 系統とジョブ
-- ------------------------------------------------------------
-- ワークアウトの系統。完了したセットが一番多い系統（無ければ種目の数）。種目が無ければ全身。
-- アプリの PartyBoss.Category と同じ分け方。
create or replace function public.party_workout_category(p_workout uuid)
returns text language sql stable security definer set search_path = public as $$
    select coalesce((
        select g.cat from (
            select case e.muscle_group
                       when 'chest' then 'upper' when 'back' then 'upper'
                       when 'shoulders' then 'upper' when 'arms' then 'upper'
                       when 'legs' then 'lower' when 'glutes' then 'lower'
                       when 'abs' then 'core' when 'core' then 'core'
                       when 'cardio' then 'cardio'
                       else 'full'
                   end as cat,
                   count(s.id) as sets,
                   count(distinct we.id) as exercises
            from public.workout_exercises we
            join public.exercises e on e.id = we.exercise_id
            left join public.exercise_sets s on s.workout_exercise_id = we.id and s.is_completed
            where we.workout_id = p_workout
            group by 1
        ) g
        order by g.sets desc, g.exercises desc, g.cat
        limit 1
    ), 'full')
$$;

-- その週のジョブ。週の頭より前の28日間に完了したワークアウトの系統を数え、
-- 半分を超える系統があればそのジョブ、無ければ勇者。週の途中では変わらない。
create or replace function public.party_member_job(p_user uuid, p_week_start timestamptz)
returns text language sql stable security definer set search_path = public as $$
    with cats as (
        select public.party_workout_category(w.id) as cat
        from public.workouts w
        where w.user_id = p_user
          and w.completed_at is not null
          and w.completed_at >= p_week_start - interval '28 days'
          and w.completed_at < p_week_start
    ),
    top as (
        select cat, count(*) as n from cats group by cat order by count(*) desc, cat limit 1
    )
    select coalesce((
        select case top.cat
                   when 'upper' then 'warrior'
                   when 'lower' then 'monk'
                   when 'cardio' then 'thief'
                   when 'core' then 'priest'
                   else 'hero'
               end
        from top
        where top.n * 2 > (select count(*) from cats)
    ), 'hero')
$$;

-- ------------------------------------------------------------
-- 攻撃とダメージ
-- ------------------------------------------------------------
-- その週の攻撃（完了したワークアウト）とダメージの内訳。1行 = 1回の攻撃。
-- - base: 1人あたり「目標 + 1」回目まで 1
-- - combo: その日に2人目の仲間が攻撃した、その人のその日の最初の攻撃に 1（＝連携が成立した1撃）
-- - skill: ジョブの条件を初めて満たした攻撃に 1（1人週1回）
--     戦士 = 土日 / 盗賊 = 月火 / 武闘家 = 前日にも攻撃している / 僧侶 = 連携の日 / 勇者 = 目標の回数目
-- p_exclude_workout は「この1回の前」の計算用（撃破・あと1撃の通知）。除いた攻撃は連携とスキルの判定からも外れる。
-- アプリの PartyBoss.score と同じ規則。変えるときは両方を変えて scripts/sqltest で突き合わせる。
create or replace function public.party_attacks(p_party uuid, p_week_start timestamptz, p_exclude_workout uuid default null)
returns table (workout_id uuid, user_id uuid, completed_at timestamptz, day date, job text, base int, skill int, combo int)
language sql stable security definer set search_path = public as $$
    with mem as (
        select m.user_id, m.weekly_goal, public.party_member_job(m.user_id, p_week_start) as job
        from public.party_members m
        where m.party_id = p_party
    ),
    a as (
        select w.id as workout_id, w.user_id, w.completed_at,
               (w.completed_at at time zone 'Asia/Tokyo')::date as day,
               mem.weekly_goal, mem.job,
               row_number() over (partition by w.user_id order by w.completed_at, w.id) as seq
        from mem
        join public.workouts w on w.user_id = mem.user_id
        where w.completed_at is not null
          and w.completed_at >= p_week_start
          and w.completed_at < p_week_start + interval '7 days'
          and (p_exclude_workout is null or w.id <> p_exclude_workout)
    ),
    b as (
        select a.*,
               row_number() over (partition by a.day, a.user_id order by a.completed_at, a.workout_id) as day_user_seq,
               lag(a.day) over (partition by a.user_id order by a.completed_at, a.workout_id) as prev_day
        from a
    ),
    c as (
        -- その日に何人目の仲間として来たか（その人のその日の最初の攻撃にだけ振る）。
        select b.*,
               case when b.day_user_seq = 1 then
                   row_number() over (partition by b.day, b.day_user_seq = 1 order by b.completed_at, b.workout_id)
               end as arrival
        from b
    ),
    d as (
        select c.*, coalesce(max(c.arrival) over (partition by c.day), 0) >= 2 as combo_day
        from c
    ),
    e as (
        select d.*,
               coalesce(case d.job
                   when 'warrior' then extract(isodow from d.day) in (6, 7)
                   when 'thief'   then extract(isodow from d.day) in (1, 2)
                   when 'monk'    then d.prev_day = d.day - 1
                   when 'priest'  then d.combo_day
                   else d.seq = d.weekly_goal
               end, false) as cond
        from d
    )
    select e.workout_id, e.user_id, e.completed_at, e.day, e.job,
           (e.seq <= e.weekly_goal + 1)::int as base,
           (e.cond and row_number() over (partition by e.user_id, e.cond order by e.completed_at, e.workout_id) = 1)::int as skill,
           (e.day_user_seq = 1 and e.arrival = 2)::int as combo
    from e
$$;

-- パーティの与ダメージ合計（基本 + 連携 + スキル）。シグネチャは 0040 のまま。
create or replace function public.party_damage(p_party uuid, p_week_start timestamptz, p_exclude_workout uuid default null)
returns int language sql stable security definer set search_path = public as $$
    select coalesce(sum(a.base + a.skill + a.combo), 0)::int
    from public.party_attacks(p_party, p_week_start, p_exclude_workout) a
$$;

-- ------------------------------------------------------------
-- 状況（attacks・メンバーの job / look / live_session_id を足す。既存の項目はそのまま）
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
    select coalesce(json_agg(json_build_object(
               'id', md5(a.workout_id::text),
               'user_id', a.user_id,
               'day', to_char(a.day, 'YYYY-MM-DD'),
               'category', public.party_workout_category(a.workout_id),
               'base', a.base,
               'skill', a.skill,
               'combo', a.combo
           ) order by a.completed_at, a.workout_id), '[]'::json),
           coalesce(sum(a.base + a.skill + a.combo), 0)::int
      into attacks, dmg
      from public.party_attacks(p_party_id, ws) a;
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
-- 「あと1撃」の通知
-- ------------------------------------------------------------
-- 送った記録（パーティ×週で1回）。読むのは集計（service role）だけなのでポリシーは置かない。
create table if not exists public.party_reach_notices (
    party_id   uuid not null references public.parties(id) on delete cascade,
    week_start timestamptz not null,
    attacker   uuid references auth.users(id) on delete set null,
    sent_at    timestamptz not null default now(),
    primary key (party_id, week_start)
);
alter table public.party_reach_notices enable row level security;

-- 撃破（HP が 0 になった）と、あと1撃（残り HP がちょうど 1 になった）を、完了の瞬間に判定して知らせる。
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
  before_dmg int;
  after_dmg int;
  member_count int;
  inserted int;
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
    before_dmg := public.party_damage(pid, ws, new.id);
    continue when before_dmg >= hp;  -- この1回の前に倒れていた
    after_dmg := public.party_damage(pid, ws);
    member_count := (select count(*) from public.party_members where party_id = pid);

    if after_dmg >= hp then
      -- この1回で HP が 0 になった（同じ週に二度は鳴らない）。
      insert into public.party_defeats (party_id, week_start, defeated_by, tier)
          values (pid, ws, new.user_id, public.party_tier(pid, ws))
          on conflict do nothing;
      -- 1人パーティは倒した本人しかいないので、知らせる相手がいない。
      continue when member_count < 2;
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
    elsif hp - after_dmg = 1 then
      -- この1回で残り HP がちょうど 1 になった。パーティ×週で1回だけ。
      continue when member_count < 2;
      insert into public.party_reach_notices (party_id, week_start, attacker)
          values (pid, ws, new.user_id)
          on conflict do nothing;
      get diagnostics inserted = row_count;
      continue when inserted = 0;
      continue when cfg.send_push_url is null or cfg.send_push_url = '';
      perform net.http_post(
        url     := cfg.send_push_url,
        headers := jsonb_build_object(
                     'Content-Type', 'application/json',
                     'X-Push-Secret', coalesce(cfg.push_secret, '')
                   ),
        body    := jsonb_build_object(
                     'event', 'boss_reach',
                     'partyId', pid,
                     'bossId', public.party_boss_id(ws),
                     'attackerId', new.user_id
                   )
      );
    end if;
  end loop;
  return new;
end;
$$;

-- ------------------------------------------------------------
-- 権限
-- ------------------------------------------------------------
revoke all on function public.set_character_look(jsonb) from public;
grant execute on function public.set_character_look(jsonb) to authenticated;
-- 内部の集計関数は他人のワークアウトを数えられるので、外から直接呼ばせない。
revoke all on function public.party_workout_category(uuid) from public, anon, authenticated;
revoke all on function public.party_member_job(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.party_attacks(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.party_damage(uuid, timestamptz, uuid) from public, anon, authenticated;
