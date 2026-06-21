-- Gymnee 一括セットアップ（SQL Editor に貼って Run）。初回のみ実行。

-- ============================================================
-- migrations/0001_schema.sql
-- ============================================================
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

-- ============================================================
-- migrations/0002_rls.sql
-- ============================================================
-- Gymnee 行レベルセキュリティ (§7 セキュリティ / RLS で行レベル権限)
-- 0001_schema.sql の後に適用する。
--
-- 原則:
--   * ユーザー所有テーブルは本人(user_id = auth.uid())のみ全権。
--   * マスタ(gyms/exercises)はプリセット＝全員参照、ユーザー作成分＝作成者のみ更新。
--   * 公開コンテンツ(progress_photos/feed_items)は visibility と follow 関係で参照可否を判定。
--   * products は全員参照、書込はサービスロール(管理)のみ。

-- フォロー判定ヘルパ（friends 可視性で使用）
create or replace function public.is_following(target uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.follows
        where follower_id = auth.uid() and followee_id = target
    );
$$;

-- visits ↔ visit_partners の相互参照ポリシーが無限再帰(42P17)するため、
-- RLS を介さない SECURITY DEFINER 関数で判定する。
create or replace function public.is_visit_partner(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visit_partners
        where visit_id = v_id and partner_user_id = auth.uid()
    );
$$;

create or replace function public.owns_visit(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visits
        where id = v_id and user_id = auth.uid()
    );
$$;

-- =========================================================
-- profiles : 本人のみ書込。プロフィールは全員参照可（ソーシャル表示のため）。
-- =========================================================
alter table public.profiles enable row level security;
create policy profiles_select_all on public.profiles for select to authenticated using (true);
create policy profiles_modify_self on public.profiles for all to authenticated
    using (id = auth.uid()) with check (id = auth.uid());

-- =========================================================
-- gyms : 全員参照、作成者のみ書込（preset は created_by NULL で全員参照のみ）。
-- =========================================================
alter table public.gyms enable row level security;
create policy gyms_select_all on public.gyms for select to authenticated using (true);
create policy gyms_insert_own on public.gyms for insert to authenticated
    with check (created_by = auth.uid());
create policy gyms_update_own on public.gyms for update to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy gyms_delete_own on public.gyms for delete to authenticated
    using (created_by = auth.uid());

-- gym_equipment : 全員参照、作成者のみ書込。
alter table public.gym_equipment enable row level security;
create policy gym_equipment_select_all on public.gym_equipment for select to authenticated using (true);
create policy gym_equipment_modify_own on public.gym_equipment for all to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());

-- =========================================================
-- visits : 本人のみ。合トレ相手は参照可。
-- =========================================================
alter table public.visits enable row level security;
create policy visits_select on public.visits for select to authenticated
    using (user_id = auth.uid() or public.is_visit_partner(id));
create policy visits_modify_own on public.visits for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- visit_partners : 来店オーナーが管理、相手は参照のみ（関数経由で再帰回避）。
alter table public.visit_partners enable row level security;
create policy visit_partners_select on public.visit_partners for select to authenticated
    using (partner_user_id = auth.uid() or public.owns_visit(visit_id));
create policy visit_partners_modify_owner on public.visit_partners for all to authenticated
    using (public.owns_visit(visit_id)) with check (public.owns_visit(visit_id));

-- =========================================================
-- workouts / 子テーブル : 本人のみ（子は親の所有者で判定）。
-- =========================================================
alter table public.workouts enable row level security;
create policy workouts_modify_own on public.workouts for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.workout_exercises enable row level security;
create policy workout_exercises_own on public.workout_exercises for all to authenticated
    using (exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = auth.uid()))
    with check (exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = auth.uid()));

alter table public.exercise_sets enable row level security;
create policy exercise_sets_own on public.exercise_sets for all to authenticated
    using (exists (
        select 1 from public.workout_exercises we
        join public.workouts w on w.id = we.workout_id
        where we.id = workout_exercise_id and w.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.workout_exercises we
        join public.workouts w on w.id = we.workout_id
        where we.id = workout_exercise_id and w.user_id = auth.uid()
    ));

-- =========================================================
-- exercises : 全員参照、作成者のみ書込。
-- =========================================================
alter table public.exercises enable row level security;
create policy exercises_select_all on public.exercises for select to authenticated using (true);
create policy exercises_insert_own on public.exercises for insert to authenticated
    with check (created_by = auth.uid());
create policy exercises_update_own on public.exercises for update to authenticated
    using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy exercises_delete_own on public.exercises for delete to authenticated
    using (created_by = auth.uid());

-- =========================================================
-- routines / routine_exercises : 本人のみ。
-- =========================================================
alter table public.routines enable row level security;
create policy routines_modify_own on public.routines for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.routine_exercises enable row level security;
create policy routine_exercises_own on public.routine_exercises for all to authenticated
    using (exists (select 1 from public.routines r where r.id = routine_id and r.user_id = auth.uid()))
    with check (exists (select 1 from public.routines r where r.id = routine_id and r.user_id = auth.uid()));

-- =========================================================
-- personal_records / body_metrics / supply_logs / subscriptions : 本人のみ。
-- =========================================================
alter table public.personal_records enable row level security;
create policy personal_records_own on public.personal_records for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.body_metrics enable row level security;
create policy body_metrics_own on public.body_metrics for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.supply_logs enable row level security;
create policy supply_logs_own on public.supply_logs for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.subscriptions enable row level security;
create policy subscriptions_select_own on public.subscriptions for select to authenticated
    using (user_id = auth.uid());
-- subscriptions の書込はサーバ(サービスロール)のみ＝クライアント書込ポリシーは作らない。

-- =========================================================
-- progress_photos : 本人＋可視性(public / friends)で参照。
-- =========================================================
alter table public.progress_photos enable row level security;
create policy progress_photos_select on public.progress_photos for select to authenticated
    using (
        user_id = auth.uid()
        or visibility = 'public'
        or (visibility = 'friends' and public.is_following(user_id))
    );
create policy progress_photos_modify_own on public.progress_photos for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- follows : 当事者(follower / followee)が参照、follower のみ作成/削除。
-- =========================================================
alter table public.follows enable row level security;
create policy follows_select on public.follows for select to authenticated
    using (follower_id = auth.uid() or followee_id = auth.uid());
create policy follows_modify_own on public.follows for all to authenticated
    using (follower_id = auth.uid()) with check (follower_id = auth.uid());

-- =========================================================
-- feed_items : 本人＋可視性で参照。
-- =========================================================
alter table public.feed_items enable row level security;
create policy feed_items_select on public.feed_items for select to authenticated
    using (
        user_id = auth.uid()
        or visibility = 'public'
        or (visibility = 'friends' and public.is_following(user_id))
    );
create policy feed_items_modify_own on public.feed_items for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- products : 全員参照（is_active）。書込はサービスロールのみ。
-- =========================================================
alter table public.products enable row level security;
create policy products_select_active on public.products for select to authenticated
    using (is_active = true);
-- 書込ポリシー無し＝anon/authenticated は不可。カタログ更新はサービスロール(Edge Function/管理)で行う。

-- ============================================================
-- migrations/0003_storage.sql
-- ============================================================
-- Gymnee Storage バケットとアクセス制御 (§3 画像ストレージ / §6.7 進捗写真)
-- パス規約: バケット直下を user_id で切る → "<auth.uid()>/<filename>"。RLS でパス先頭の所有者を判定。

-- バケット作成（既存ならスキップ）
insert into storage.buckets (id, name, public)
values
    ('visit-photos',    'visit-photos',    false),
    ('progress-photos', 'progress-photos', false),
    ('avatars',         'avatars',         true)
on conflict (id) do nothing;

-- 進捗写真: 体型写真は厳格に本人のみ（既定 private, §6.7）。署名URLで都度配信。
create policy "progress own read" on storage.objects for select to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own update" on storage.objects for update to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "progress own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 来店写真: 本人が書込。共有はフィード経由＋署名URL想定のため読取も本人のみ（必要なら後で friends 緩和）。
create policy "visit own read" on storage.objects for select to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own update" on storage.objects for update to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "visit own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'visit-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- アバター: 公開バケット（読取は誰でも）。書込は本人フォルダのみ。
create policy "avatars public read" on storage.objects for select to public
    using (bucket_id = 'avatars');
create policy "avatars own write" on storage.objects for insert to authenticated
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars own update" on storage.objects for update to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars own delete" on storage.objects for delete to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- migrations/0004_functions.sql
-- ============================================================
-- Gymnee サーバ関数・トリガ (§6.1 認証時の Profile 整合 / §7 アカウント削除)

-- 新規 auth ユーザー作成時に profiles 行を自動生成する。
-- 表示名は SiwA の fullName 等を raw_user_meta_data.display_name から拾う（無ければ 'ゲスト'）。
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), 'ゲスト')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- アカウント完全削除 (§7 / App Store 5.1.1(v))。
-- クライアントから RPC で呼ぶ: supabase.rpc('delete_account')。
-- auth.users を消すと user_id 参照は全て ON DELETE CASCADE で連鎖削除される。
create or replace function public.delete_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;

-- ============================================================
-- migrations/0005_device_tokens.sql
-- ============================================================
-- Gymnee APNs デバイストークン (§6.10 通知 / プッシュ)
-- 0001〜0004 の後に適用する。サーバ（Edge Function 等）が push 送信時に参照する。

create table if not exists public.device_tokens (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
    token      text not null unique,
    platform   text not null default 'ios' check (platform in ('ios','watchos')),
    updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;
-- 本人のみ（user_id は既定で auth.uid() が入る）。
create policy device_tokens_own on public.device_tokens for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- migrations/0006_fix_visits_recursion.sql
-- ============================================================
-- visits ↔ visit_partners の RLS 相互参照が無限再帰(42P17)するため、
-- SECURITY DEFINER 関数で RLS を介さずに判定して再帰を断ち切る。
-- 0002_rls.sql 適用済みの環境に対して流す（冪等：create or replace / drop if exists）。

-- 合トレ相手か？（visit_partners を RLS 無しで参照）
create or replace function public.is_visit_partner(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visit_partners
        where visit_id = v_id and partner_user_id = auth.uid()
    );
$$;

-- その来店の所有者か？（visits を RLS 無しで参照）
create or replace function public.owns_visit(v_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.visits
        where id = v_id and user_id = auth.uid()
    );
$$;

-- visits: 本人 or 合トレ相手（関数経由で再帰回避）。
drop policy if exists visits_select on public.visits;
create policy visits_select on public.visits for select to authenticated
    using (user_id = auth.uid() or public.is_visit_partner(id));

-- visit_partners: 相手本人 or 来店オーナー（関数経由で再帰回避）。
drop policy if exists visit_partners_select on public.visit_partners;
create policy visit_partners_select on public.visit_partners for select to authenticated
    using (partner_user_id = auth.uid() or public.owns_visit(visit_id));

drop policy if exists visit_partners_modify_owner on public.visit_partners;
create policy visit_partners_modify_owner on public.visit_partners for all to authenticated
    using (public.owns_visit(visit_id)) with check (public.owns_visit(visit_id));

-- ============================================================
-- seed.sql
-- ============================================================
-- Gymnee サーバ側プリセット投入（任意）。products は RLS でクライアント書込不可のため、
-- カタログはここ（またはEdge Function/管理）から投入する。
-- affiliate_url は楽天アフィリエイト計測リダイレクト（ID: 5519c310...）。クリック経由の購入で手数料が発生。

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
values
    ('ホエイプロテイン 1kg', '高純度ホエイ。増量・維持の基本。', 3980, 'プロテイン', array['bulk','maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%9B%E3%82%A8%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg%2F', 33),
    ('ソイプロテイン 1kg', '植物性。減量フェーズに。', 3580, 'プロテイン', array['cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%82%BD%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg%2F', 33),
    ('クレアチン 500g', '高強度トレの定番サプリ。', 2480, 'サプリ', array['strength','bulk'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%82%AF%E3%83%AC%E3%82%A2%E3%83%81%E3%83%B3%20%E3%83%A2%E3%83%8E%E3%83%8F%E3%82%A4%E3%83%89%E3%83%AC%E3%83%BC%E3%83%88%2F', 100),
    ('EAA 500g', 'トレ中のアミノ酸補給。', 4280, 'サプリ', array['maintain','cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2FEAA%20%E3%82%A2%E3%83%9F%E3%83%8E%E9%85%B8%2F', 50),
    ('マルトデキストリン 1kg', '増量期のカロリー補給に。', 1880, 'カーボ', array['bulk'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%9E%E3%83%AB%E3%83%88%E3%83%87%E3%82%AD%E3%82%B9%E3%83%88%E3%83%AA%E3%83%B3%201kg%2F', 20),
    ('リストラップ', '高重量プレス系の手首保護。', 1980, 'ギア', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%AA%E3%82%B9%E3%83%88%E3%83%A9%E3%83%83%E3%83%97%20%E7%AD%8B%E3%83%88%E3%83%AC%2F', null),
    ('トレーニングベルト', 'スクワット/デッドの体幹サポート。', 5980, 'ギア', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%88%E3%83%AC%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0%E3%83%99%E3%83%AB%E3%83%88%2F', null)
on conflict do nothing;

-- ============================================================
-- migrations/0007_moderation.sql
-- ============================================================
-- モデレーション（UGC安全 / App Store ガイドライン1.2.5）。
-- blocks: 迷惑ユーザーのブロック。reports: 不適切なユーザー/コンテンツの通報。

create table if not exists public.blocks (
    id                   uuid primary key default gen_random_uuid(),
    blocker_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
    blocked_id           uuid not null references auth.users(id) on delete cascade,
    blocked_display_name text,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    unique (blocker_id, blocked_id)
);
create index if not exists blocks_blocker_idx on public.blocks(blocker_id);
create index if not exists blocks_blocked_idx on public.blocks(blocked_id);

alter table public.blocks enable row level security;
create policy blocks_own on public.blocks for all to authenticated
    using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

create table if not exists public.reports (
    id               uuid primary key default gen_random_uuid(),
    reporter_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
    reported_user_id uuid not null references auth.users(id) on delete cascade,
    context_type     text,
    context_id       uuid,
    reason           text not null,
    detail           text,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);
create index if not exists reports_reporter_idx on public.reports(reporter_id);
create index if not exists reports_reported_idx on public.reports(reported_user_id);
create index if not exists reports_created_idx on public.reports(created_at desc);

alter table public.reports enable row level security;
create policy reports_own on public.reports for all to authenticated
    using (reporter_id = auth.uid()) with check (reporter_id = auth.uid());
