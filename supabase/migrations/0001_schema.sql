-- Gymnee バックエンドスキーマ (§4 データモデル / アフィリエイト移行後)
-- 適用方法: Supabase SQL Editor に貼り付け、または `psql "$DATABASE_URL" -f 0001_schema.sql`
--
-- 設計方針:
--   * 各テーブルの id はクライアント(SwiftData)生成の UUID をそのまま使う（オフラインファースト）。
--   * updated_at はクライアントが送る値を正とする（同期は last-write-wins, §9-7）。サーバで上書きしない。
--   * is_dirty はローカル限定フラグのため DB には持たない。
--   * ユーザー所有データの user_id は auth.users(id) を参照し ON DELETE CASCADE（アカウント削除でデータも消える, §7）。

create extension if not exists "pgcrypto";

-- =========================================================
-- 4.1 ユーザー・ジム
-- =========================================================

create table if not exists public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default 'ゲスト',
    avatar_url   text,
    bio          text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

create table if not exists public.gyms (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    chain       text,
    address     text,
    lat         double precision,
    lng         double precision,
    source      text not null default 'user' check (source in ('preset','user')),
    created_by  uuid default auth.uid() references auth.users(id) on delete cascade, -- preset は明示 NULL（全員参照可）
    is_favorite boolean not null default false,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);
create index if not exists gyms_created_by_idx on public.gyms(created_by);

create table if not exists public.gym_equipment (
    id         uuid primary key default gen_random_uuid(),
    gym_id     uuid references public.gyms(id) on delete cascade,
    label      text not null,
    note       text,
    created_by uuid default auth.uid() references auth.users(id) on delete cascade,
    updated_at timestamptz not null default now()
);
create index if not exists gym_equipment_gym_idx on public.gym_equipment(gym_id);

-- =========================================================
-- 4.2 来店・ワークアウト
-- =========================================================

create table if not exists public.visits (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    gym_id     uuid references public.gyms(id) on delete set null,
    visited_at timestamptz not null default now(),
    photo_url  text,
    lat        double precision,
    lng        double precision,
    note       text,
    updated_at timestamptz not null default now()
);
create index if not exists visits_user_idx on public.visits(user_id, visited_at desc);

create table if not exists public.visit_partners (
    id                   uuid primary key default gen_random_uuid(),
    visit_id             uuid not null references public.visits(id) on delete cascade,
    partner_user_id      uuid references auth.users(id) on delete cascade,
    partner_display_name text,
    updated_at           timestamptz not null default now()
);
create index if not exists visit_partners_visit_idx on public.visit_partners(visit_id);
create index if not exists visit_partners_partner_idx on public.visit_partners(partner_user_id);

create table if not exists public.workouts (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    visit_id     uuid references public.visits(id) on delete set null,
    date         timestamptz not null default now(),
    name         text not null default 'ワークアウト',
    routine_id   uuid,
    note         text,
    is_planned   boolean not null default false,
    completed_at timestamptz,
    updated_at   timestamptz not null default now()
);
create index if not exists workouts_user_idx on public.workouts(user_id, date desc);

create table if not exists public.exercises (
    id            uuid primary key default gen_random_uuid(),
    name          text not null,
    muscle_group  text not null,
    equipment     text not null,
    is_custom     boolean not null default false,
    created_by    uuid default auth.uid() references auth.users(id) on delete cascade, -- preset は明示 NULL
    updated_at    timestamptz not null default now()
);
create index if not exists exercises_created_by_idx on public.exercises(created_by);

create table if not exists public.workout_exercises (
    id             uuid primary key default gen_random_uuid(),
    workout_id     uuid not null references public.workouts(id) on delete cascade,
    exercise_id    uuid references public.exercises(id) on delete set null,
    order_index    integer not null default 0,
    note           text,
    superset_group integer,
    rest_seconds   integer,
    updated_at     timestamptz not null default now()
);
create index if not exists workout_exercises_workout_idx on public.workout_exercises(workout_id);

create table if not exists public.exercise_sets (
    id                  uuid primary key default gen_random_uuid(),
    workout_exercise_id uuid not null references public.workout_exercises(id) on delete cascade,
    set_index           integer not null default 0,
    weight              double precision not null default 0,
    reps                integer not null default 0,
    rpe                 double precision,
    rir                 integer,
    type                text not null default 'normal',
    is_pr               boolean not null default false,
    is_completed        boolean not null default false,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index if not exists exercise_sets_we_idx on public.exercise_sets(workout_exercise_id);

create table if not exists public.routines (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    name       text not null,
    note       text,
    updated_at timestamptz not null default now()
);
create index if not exists routines_user_idx on public.routines(user_id);

create table if not exists public.routine_exercises (
    id           uuid primary key default gen_random_uuid(),
    routine_id   uuid not null references public.routines(id) on delete cascade,
    exercise_id  uuid references public.exercises(id) on delete set null,
    order_index  integer not null default 0,
    target_sets  integer not null default 3,
    target_reps  integer,
    rest_seconds integer,
    updated_at   timestamptz not null default now()
);
create index if not exists routine_exercises_routine_idx on public.routine_exercises(routine_id);

create table if not exists public.personal_records (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    exercise_id uuid references public.exercises(id) on delete cascade,
    type        text not null,
    value       double precision not null,
    achieved_at timestamptz not null default now(),
    workout_id  uuid,
    updated_at  timestamptz not null default now()
);
create index if not exists personal_records_user_idx on public.personal_records(user_id, exercise_id);

-- =========================================================
-- 4.3 身体・写真
-- =========================================================

create table if not exists public.body_metrics (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references auth.users(id) on delete cascade,
    date            timestamptz not null default now(),
    weight          double precision,
    body_fat        double precision,
    measurements    jsonb not null default '{}'::jsonb,
    from_health_kit boolean not null default false,
    updated_at      timestamptz not null default now()
);
create index if not exists body_metrics_user_idx on public.body_metrics(user_id, date desc);

create table if not exists public.progress_photos (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    date       timestamptz not null default now(),
    photo_url  text,
    visibility text not null default 'private' check (visibility in ('private','friends','public')),
    note       text,
    updated_at timestamptz not null default now()
);
create index if not exists progress_photos_user_idx on public.progress_photos(user_id, date desc);

-- =========================================================
-- 4.4 ソーシャル
-- =========================================================

create table if not exists public.follows (
    id                    uuid primary key default gen_random_uuid(),
    follower_id           uuid not null references auth.users(id) on delete cascade,
    followee_id           uuid not null references auth.users(id) on delete cascade,
    followee_display_name text,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    unique (follower_id, followee_id)
);
create index if not exists follows_follower_idx on public.follows(follower_id);
create index if not exists follows_followee_idx on public.follows(followee_id);

create table if not exists public.feed_items (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid not null references auth.users(id) on delete cascade,
    author_display_name text,
    type                text not null check (type in ('visit','pr','workout')),
    ref_id              uuid not null,
    summary             text,
    visibility          text not null default 'friends' check (visibility in ('private','friends','public')),
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
create index if not exists feed_items_user_idx on public.feed_items(user_id, created_at desc);

-- =========================================================
-- 4.5 コマース（アフィリエイト）
-- =========================================================

-- products は全ユーザー共通カタログ（サーバ管理）。注文・カート・決済テーブルはアフィリエイト方式のため廃止。
create table if not exists public.products (
    id                uuid primary key default gen_random_uuid(),
    name              text not null,
    description       text,
    price             numeric(10,2) not null default 0,  -- 参考価格
    image_url         text,
    category          text,
    goal_tags         text[] not null default '{}',
    affiliate_url     text,   -- 提携先(計測タグ付き)URL
    merchant          text,   -- 楽天市場 / iHerb 等（開示表示用）
    servings_per_unit integer,
    is_active         boolean not null default true,
    updated_at        timestamptz not null default now()
);

create table if not exists public.supply_logs (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    product_id   uuid references public.products(id) on delete set null,
    date         timestamptz not null default now(),
    amount       double precision not null default 1,
    product_name text,
    updated_at   timestamptz not null default now()
);
create index if not exists supply_logs_user_idx on public.supply_logs(user_id, date desc);

create table if not exists public.subscriptions (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    tier       text not null default 'free' check (tier in ('free','pro','elite')),
    status     text not null default 'active' check (status in ('active','cancelled','expired')),
    started_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index if not exists subscriptions_user_idx on public.subscriptions(user_id);
