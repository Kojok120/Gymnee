-- 0046: 外部連携の土台（#171）
-- api.gymnee.app の Worker（connect/）が service role で使う表と関数。
-- 外部に渡すトークンはアプリのログイン JWT より狭くするため、外部からの操作は RLS ではなく
-- 「利用者 id を引数に取る、用途を絞った関数」で通す。関数は service_role にだけ実行を許し、
-- anon / authenticated からは呼べない（アプリや第三者が他人の id を渡して呼ぶことはできない）。

-- ------------------------------------------------------------
-- PAT（個人用アクセストークン）。トークンそのものは保存せず、SHA-256 だけを持つ
-- ------------------------------------------------------------
create table if not exists public.connect_api_tokens (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id) on delete cascade,
    name          text not null,
    token_hash    text not null unique,
    -- 一覧で見分けるための先頭（gym_pat_ + 4 文字）。これだけではトークンにならない
    token_prefix  text not null,
    scopes        text[] not null,
    created_at    timestamptz not null default now(),
    last_used_at  timestamptz,
    revoked_at    timestamptz,
    constraint connect_api_tokens_name_length check (char_length(name) between 1 and 60),
    constraint connect_api_tokens_scopes_known check (scopes <@ array['read', 'workouts:write', 'coach:write']::text[])
);

create index if not exists connect_api_tokens_user_idx on public.connect_api_tokens (user_id, created_at desc);

-- RLS は有効にし、ポリシーは置かない（アプリも Worker 経由で扱う。直接は読み書きさせない）
alter table public.connect_api_tokens enable row level security;
revoke all on table public.connect_api_tokens from anon, authenticated;

-- ------------------------------------------------------------
-- MCP の OAuth を「iPhone の Gymnee で承認」するための、承認待ちの組（ペアリング）
-- ブラウザ（承認画面）とアプリの両方から即座に同じ状態を読む必要があるため、KV ではなくここに置く。
-- 10 分で切れる。ブラウザとアプリに同じ code（2 桁）を出し、利用者が見比べてから承認する。
-- ------------------------------------------------------------
create table if not exists public.connect_oauth_pairings (
    id                  uuid primary key default gen_random_uuid(),
    code                text not null,
    status              text not null default 'pending',
    client_name         text not null,
    client_domain       text,
    redirect_host       text not null,
    redirect_is_loopback boolean not null default false,
    scopes              text[] not null,
    user_id             uuid references auth.users(id) on delete cascade,
    approved_scopes     text[],
    created_at          timestamptz not null default now(),
    decided_at          timestamptz,
    expires_at          timestamptz not null default now() + interval '10 minutes',
    constraint connect_oauth_pairings_status check (status in ('pending', 'approved', 'denied', 'consumed'))
);

create index if not exists connect_oauth_pairings_expires_idx on public.connect_oauth_pairings (expires_at);

alter table public.connect_oauth_pairings enable row level security;
revoke all on table public.connect_oauth_pairings from anon, authenticated;

-- ------------------------------------------------------------
-- 外部から記録を足す（API の POST /v1/workouts・MCP の log_workout・LINE の「記録する」）
-- 種目の照合・入力の検証・自己ベストの判定は Worker 側（純粋関数・テスト済み）で済ませ、
-- ここでは 1 トランザクションで書き込むことと、持ち主の検証だけを受け持つ。
-- p_workout:
--   { id, name, date, completed_at, duration_seconds, note,
--     exercises: [{ id, exercise_id, sets: [{ id, set_index, weight, reps, duration_seconds, distance_km, is_pr }] }],
--     personal_records: [{ exercise_id, type, value }] }
-- 返り値: { workout_id, created }（created=false は同じ id が既にある＝同じ依頼の再送）
-- ------------------------------------------------------------
create or replace function public.connect_log_workout(p_user uuid, p_workout jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare
    w_id uuid := (p_workout->>'id')::uuid;
    w_completed timestamptz := (p_workout->>'completed_at')::timestamptz;
    ex jsonb;
    s jsonb;
    pr jsonb;
    we_id uuid;
    ex_id uuid;
    ord int := 0;
    owner uuid;
begin
    if p_user is null or w_id is null or w_completed is null then
        raise exception 'p_user, id, completed_at are required' using errcode = '22023';
    end if;
    if jsonb_typeof(p_workout->'exercises') <> 'array' or jsonb_array_length(p_workout->'exercises') = 0 then
        raise exception 'exercises must be a non-empty array' using errcode = '22023';
    end if;

    -- 冪等: 同じ id が既にあれば何もしない。持ち主が違う id は受け付けない。
    select user_id into owner from public.workouts where id = w_id;
    if found then
        if owner is distinct from p_user then
            raise exception 'workout id belongs to another user' using errcode = '42501';
        end if;
        return json_build_object('workout_id', w_id, 'created', false);
    end if;

    insert into public.workouts (id, user_id, date, name, note, is_planned, completed_at, duration_seconds, updated_at)
    values (
        w_id, p_user,
        coalesce((p_workout->>'date')::timestamptz, w_completed),
        left(coalesce(nullif(p_workout->>'name', ''), 'ワークアウト'), 60),
        nullif(left(p_workout->>'note', 1000), ''),
        false, w_completed,
        nullif(p_workout->>'duration_seconds', '')::int,
        now()
    );

    for ex in select value from jsonb_array_elements(p_workout->'exercises') loop
        ex_id := (ex->>'exercise_id')::uuid;
        -- 種目はプリセットか本人の種目だけ（他人の種目に記録をぶら下げない）。
        if not exists (
            select 1 from public.exercises e
            where e.id = ex_id and (e.created_by is null or e.created_by = p_user)
        ) then
            raise exception 'unknown exercise %', ex_id using errcode = '23503';
        end if;
        we_id := (ex->>'id')::uuid;
        insert into public.workout_exercises (id, workout_id, exercise_id, order_index, updated_at)
        values (we_id, w_id, ex_id, ord, now());
        ord := ord + 1;

        for s in select value from jsonb_array_elements(ex->'sets') loop
            insert into public.exercise_sets (
                id, workout_exercise_id, set_index, weight, reps, duration_seconds, distance_km,
                is_pr, is_completed, type, created_at, updated_at
            ) values (
                (s->>'id')::uuid, we_id,
                coalesce((s->>'set_index')::int, 0),
                coalesce((s->>'weight')::float8, 0),
                coalesce((s->>'reps')::int, 0),
                nullif(s->>'duration_seconds', '')::int,
                nullif(s->>'distance_km', '')::float8,
                coalesce((s->>'is_pr')::boolean, false),
                true, 'normal', now(), now()
            );
        end loop;
    end loop;

    -- 自己ベストは種目×種別で 1 行（アプリの WorkoutMetrics.upsertPR と同じ）。良くなったときだけ置き換える。
    -- min_assist は小さいほど強い。
    for pr in select value from jsonb_array_elements(coalesce(p_workout->'personal_records', '[]'::jsonb)) loop
        ex_id := (pr->>'exercise_id')::uuid;
        if exists (
            select 1 from public.personal_records r
            where r.user_id = p_user and r.exercise_id = ex_id and r.type = pr->>'type'
        ) then
            update public.personal_records r
               set value = (pr->>'value')::float8, achieved_at = w_completed, workout_id = w_id, updated_at = now()
             where r.user_id = p_user and r.exercise_id = ex_id and r.type = pr->>'type'
               and case when pr->>'type' = 'min_assist'
                        then (pr->>'value')::float8 < r.value
                        else (pr->>'value')::float8 > r.value end;
        else
            insert into public.personal_records (id, user_id, exercise_id, type, value, achieved_at, workout_id, updated_at)
            values (gen_random_uuid(), p_user, ex_id, pr->>'type', (pr->>'value')::float8, w_completed, w_id, now());
        end if;
    end loop;

    return json_build_object('workout_id', w_id, 'created', true);
end;
$$;

revoke all on function public.connect_log_workout(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.connect_log_workout(uuid, jsonb) to service_role;

-- ------------------------------------------------------------
-- パーティの状況（API の GET /v1/party・MCP・週報）
-- 外へ出すのは合計と本人の分だけ。ほかのメンバーの名前と回数は返さない（#171 の決定）。
-- ------------------------------------------------------------
create or replace function public.connect_party_overview(p_user uuid, p_now timestamptz default now())
returns json language sql stable security definer set search_path = public as $$
    select coalesce(json_agg(row_to_json(x) order by x.joined_at), '[]'::json)
    from (
        select
            p.id as party_id,
            p.name,
            m.joined_at,
            w.ws as week_start,
            public.party_boss_id(w.ws) as boss_id,
            public.party_hp(p.id, w.ws) as hp,
            public.party_damage(p.id, w.ws) as damage,
            public.party_defeated(p.id, w.ws) as defeated,
            (select count(*) from public.party_members mm where mm.party_id = p.id)::int as member_count,
            public.party_member_hits(p_user, w.ws) as my_hits,
            m.weekly_goal as my_weekly_goal
        from public.party_members m
        join public.parties p on p.id = m.party_id
        cross join (select public.party_week_start(p_now) as ws) w
        where m.user_id = p_user
    ) x
$$;

revoke all on function public.connect_party_overview(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.connect_party_overview(uuid, timestamptz) to service_role;
