-- Gymnee 一括セットアップ（SQL Editor に貼って Run）。初回のみ実行。
-- migrations/*.sql を番号順に取り込んだ手保守ファイル（専用の生成スクリプトは無い）。【ルール】新しい migration を追加/変更したら、必ずここへ番号順で同内容を追記し、dev DB にも適用すること。

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
    notify_likes boolean not null default true,
    notify_friend_checkin boolean not null default true,
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
    -- stats_json は本来 migration 0020 で後付けだが、先行するストレージポリシー(visit-photos)が
    -- f.stats_json を参照するため、fresh DB 用に CREATE 時から含める（0020 の add column は no-op になる）。
    stats_json          text,
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
-- exercises : 本人専用＋共有プリセット(created_by null)のみ参照、作成者のみ書込。
-- 他人のカスタム種目が見えないようにする（プライバシー）。
-- =========================================================
alter table public.exercises enable row level security;
create policy exercises_select_own on public.exercises for select to authenticated
    using (created_by = auth.uid() or created_by is null);
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

-- 来店写真: 本人が書込。読取は本人に加え、「その写真を参照する来店投稿(feed_items.type='visit')」が
-- 閲覧者から見える（public、または friends かつフォロー中）場合に限り許可（0025）。
-- フォルダ単位でなく当該オブジェクトに厳密一致（photoRef = bucket_id || '/' || name）。
create policy "visit read own or via feed" on storage.objects for select to authenticated
    using (
        bucket_id = 'visit-photos'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1 from public.feed_items f
                where f.user_id::text = (storage.foldername(name))[1]
                  and f.type = 'visit'
                  and (f.stats_json::jsonb ->> 'photoRef') = bucket_id || '/' || name
                  and (
                      f.visibility = 'public'
                      or (f.visibility = 'friends' and public.is_following(f.user_id))
                  )
            )
        )
    );
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
-- migrations/0007_moderation.sql
-- ============================================================
-- Gymnee モデレーション（UGC安全 / App Store ガイドライン1.2.5）
-- 0001〜0006 の後に適用する。
-- blocks: 迷惑ユーザーのブロック（blocker が blocked を非表示・関係遮断。クライアントで一覧/検索から除外）。
-- reports: 不適切なユーザー/コンテンツの通報（運営が確認・対応）。

-- =========================================================
-- blocks : 実行者(blocker)本人のみ参照・作成・削除。
-- =========================================================
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

-- =========================================================
-- reports : 通報者(reporter)本人のみ作成・参照（運営は service role で確認）。
-- =========================================================
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

-- ============================================================
-- migrations/0008_push_on_visit.sql
-- ============================================================
-- フレンドのチェックイン通知（§6.10 / §6.11）。
-- visits への新規 insert を起点に Edge Function `send-push` を非同期で呼び、
-- 訪問者のフォロワーへ「〇〇さんがジムに行きました」を APNs 送信する。
-- 0001〜0007 の後に適用する。
--
-- 接続情報（Function URL と共有シークレット）は public.push_config（1行）に持つ。
-- Supabase の postgres ロールは `alter database ... set` が権限不足になるため GUC ではなくテーブルで保持する。
-- 値は適用後に別途 upsert する（秘密のためコミットしない。手順は docs/apns-push-setup.md）:
--   insert into public.push_config (id, send_push_url, push_secret)
--   values (1, 'https://<ref>.supabase.co/functions/v1/send-push', '<PUSH_SHARED_SECRET と同じ値>')
--   on conflict (id) do update
--     set send_push_url = excluded.send_push_url, push_secret = excluded.push_secret;

create extension if not exists pg_net;

-- 接続設定（単一行）。RLS 有効かつポリシー無し＝クライアントからは不可視。
-- 参照は security definer の関数（所有者 = postgres）だけが行う。
create table if not exists public.push_config (
    id            int primary key default 1,
    send_push_url text,
    push_secret   text,
    constraint push_config_singleton check (id = 1)
);
alter table public.push_config enable row level security;

create or replace function public.notify_friend_checkin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_config;
begin
  select * into cfg from public.push_config where id = 1;

  -- 未設定なら何もしない（縮退：ローカル/未構成環境でも insert は成功させる）。
  if cfg.send_push_url is null or cfg.send_push_url = '' then
    return new;
  end if;

  -- 過去来店の一括同期（バックフィル）で通知が暴発しないよう、直近のチェックインだけ通知する。
  if new.visited_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'friend_checkin', 'visitId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_checkin on public.visits;
create trigger trg_notify_friend_checkin
  after insert on public.visits
  for each row execute function public.notify_friend_checkin();

-- ============================================================
-- migrations/0009_weight_mode.sql
-- ============================================================
-- ③ 重量の数え方（両側/片側）。種目に既定、セットで上書き。
-- 本番には supabase db query で適用済み（ここは履歴として保持）。
alter table public.exercises add column if not exists weight_mode text not null default 'both';
alter table public.exercise_sets add column if not exists weight_mode_override text;

-- ============================================================
-- migrations/0017_record_redesign.sql
-- ============================================================
-- 記録リデザイン（タップ式）。計測タイプ(weight/bodyweight/time)と時間種目の継続秒数。
alter table public.exercises add column if not exists measurement_type text not null default 'weight';
alter table public.exercise_sets add column if not exists duration_seconds integer;

-- ============================================================
-- migrations/0010_post_reactions.sql
-- ============================================================
-- ⑨ いいね。投稿(feed_items)へのリアクション。本番には supabase db query で適用済み。
create table if not exists public.post_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_item_id uuid not null references public.feed_items(id) on delete cascade,
  kind text not null check (kind in ('like')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, feed_item_id, kind)
);
create index if not exists post_reactions_feed_idx on public.post_reactions(feed_item_id);

alter table public.post_reactions enable row level security;
-- 参照: 見える投稿(本人/public/friends&フォロー)へのリアクションは見える。書込は本人のみ。
create policy post_reactions_select on public.post_reactions for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.feed_items f where f.id = feed_item_id
      and (f.user_id = auth.uid() or f.visibility = 'public'
           or (f.visibility = 'friends' and public.is_following(f.user_id))))
  );
create policy post_reactions_modify_own on public.post_reactions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- migrations/0011_block_rls.sql
-- ============================================================
-- 監査S: ブロックを RLS に連動（クライアント除外依存をやめ、サーバ側で被ブロックを遮断）。
-- 本番には supabase db query で適用済み（ここは履歴）。
create or replace function public.is_blocked(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = auth.uid() and blocked_id = other)
       or (blocker_id = other and blocked_id = auth.uid())
  );
$$;

drop policy if exists feed_items_select on public.feed_items;
create policy feed_items_select on public.feed_items for select to authenticated using (
  user_id = auth.uid()
  or (not public.is_blocked(user_id) and (visibility = 'public' or (visibility = 'friends' and public.is_following(user_id))))
);

drop policy if exists progress_photos_select on public.progress_photos;
create policy progress_photos_select on public.progress_photos for select to authenticated using (
  user_id = auth.uid()
  or (not public.is_blocked(user_id) and (visibility = 'public' or (visibility = 'friends' and public.is_following(user_id))))
);

-- プロフィールはブロック相手には不可視（自分は常に可視）。
drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_all on public.profiles for select to authenticated using (
  id = auth.uid() or not public.is_blocked(id)
);

-- ============================================================
-- migrations/0012_gym_rls.sql
-- ============================================================
-- 監査S: ユーザー作成ジム（lat/lng・メモ含む）を全公開にしない。own＋preset のみ参照可。
-- 本番には supabase db query で適用済み（ここは履歴）。
drop policy if exists gyms_select_all on public.gyms;
create policy gyms_select on public.gyms for select to authenticated using (
  created_by = auth.uid() or source = 'preset'
);

drop policy if exists gym_equipment_select_all on public.gym_equipment;
create policy gym_equipment_select on public.gym_equipment for select to authenticated using (
  created_by = auth.uid()
  or exists (select 1 from public.gyms g where g.id = gym_equipment.gym_id and (g.created_by = auth.uid() or g.source = 'preset'))
);

-- ============================================================
-- migrations/0013_push_on_reaction.sql
-- ============================================================
-- いいね/応援 → 投稿者へ push（監査T1c / ソーシャルループを閉じる）。
-- post_reactions への新規 insert を起点に Edge Function `send-push` を呼び、
-- 投稿者へ「〇〇さんがいいね/応援しました」を APNs 送信する。push_config を流用。
create or replace function public.notify_post_reaction()
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
  -- バックフィル/一括同期での暴発を防ぐため直近の反応のみ通知。
  if new.created_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'reaction', 'reactionId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_post_reaction on public.post_reactions;
create trigger trg_notify_post_reaction
  after insert on public.post_reactions
  for each row execute function public.notify_post_reaction();

-- ============================================================
-- migrations/0014_follow_notify.sql
-- ============================================================
-- フレンドごとの通知ON/OFF（監査外・ユーザー要望）。
-- follower→followee の follow 行に notify を持たせ、send-push は notify=true のフォロワーにのみ送る。
-- 本番には supabase db query で適用済み（ここは履歴）。
alter table public.follows add column if not exists notify boolean not null default true;


-- ============================================================
-- migrations/0015_reactions_like_only.sql
-- ============================================================
-- 応援(cheer)を廃止し、いいね(like)のみにする（ユーザー要望）。
-- 既存の cheer 行を削除し、CHECK 制約を like のみに付け替える。
delete from public.post_reactions where kind = 'cheer';

alter table public.post_reactions drop constraint if exists post_reactions_kind_check;
alter table public.post_reactions add constraint post_reactions_kind_check check (kind in ('like'));


-- ============================================================
-- migrations/0016_notify_prefs.sql
-- ============================================================
-- プッシュ通知の種類別 ON/OFF（ユーザー要望）。
-- send-push は投稿者/受信者の profiles 設定を見て、いいね/フレンドのチェックイン通知を抑制する。
alter table public.profiles add column if not exists notify_likes boolean not null default true;
alter table public.profiles add column if not exists notify_friend_checkin boolean not null default true;


-- ============================================================
-- migrations/0018_reactions_multi_and_comments.sql
-- ============================================================
-- ③ マルチリアクション（筋トレ絵文字）＋ 公開コメント
-- 公開投稿(feed_items)への反応/コメント。1対1の私信(DM)ではない＝「オープンな場」。

-- 1) リアクション種別を like のみ → like/strong/fire/clap に拡張（0015 の制約を付け替え）。
--    クライアントは 1ユーザー1投稿1種別（付け替えは旧削除＋新規）なので unique(user,feed,kind) は維持で衝突しない。
alter table public.post_reactions drop constraint if exists post_reactions_kind_check;
alter table public.post_reactions add constraint post_reactions_kind_check
  check (kind in ('like','strong','fire','clap'));

-- 2) 公開コメント。可視な feed_item にのみ付与でき、参照可否は post_reactions と同条件
--    （本人 / public / friends かつフォロー中）。書込は本人のみ。
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_item_id uuid not null references public.feed_items(id) on delete cascade,
  author_display_name text,
  text text not null check (char_length(text) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists comments_feed_idx on public.comments(feed_item_id, created_at);

alter table public.comments enable row level security;

create policy comments_select on public.comments for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.feed_items f
      where f.id = feed_item_id
        and (f.user_id = auth.uid()
             or f.visibility = 'public'
             or (f.visibility = 'friends' and public.is_following(f.user_id)))
    )
  );

create policy comments_modify_own on public.comments for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ============================================================
-- migrations/0019_push_on_comment.sql
-- ============================================================
-- コメント → 投稿者へ push（ソーシャルループ）。post_reactions の通知（0013）をミラー。
-- comments への新規 insert を起点に Edge Function `send-push` を { event:'comment', commentId } で呼ぶ。

-- コメント通知の ON/OFF（send-push が投稿者の設定を見て抑制）。既定 ON。
alter table public.profiles add column if not exists notify_comments boolean not null default true;

create or replace function public.notify_comment()
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
  -- バックフィル/一括同期での暴発を防ぐため直近のコメントのみ通知。
  if new.created_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'comment', 'commentId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_comment on public.comments;
create trigger trg_notify_comment
  after insert on public.comments
  for each row execute function public.notify_comment();


-- ============================================================
-- migrations/0020_feed_items_stats.sql
-- ============================================================
-- ⑦E フィードの構造化スタッツ。ワークアウト投稿の種目/セット/ボリューム/時間/PR/部位を
-- JSON 文字列で保持し、フォロワー側でもリッチカードを描けるようにする。
-- text で持つ（サーバ側で検索しないため jsonb 不要・PostgREST 型の取り回しも単純）。
alter table public.feed_items add column if not exists stats_json text;


-- ============================================================
-- migrations/0021_exercise_load_mode.sql
-- ============================================================
-- 自重種目の荷重スタイル（自重のみ/荷重/補助）。懸垂等で「荷重(自重＋kg)」と「補助(自重−kg)」を
-- 明示的に区別する。bodyweight のときだけ意味を持つ。記録される weight は常に正の大きさ。
alter table public.exercises add column if not exists load_mode text not null default 'none';


-- ============================================================
-- migrations/0022_device_token_rebind.sql
-- ============================================================
-- デバイストークンを「現在ログイン中のユーザー」へ確実に紐付け直す（いいね/コメント/チェックイン通知の不達修正）。
--
-- 背景: device_tokens.token は全体 unique かつ RLS は本人行のみ更新可。
-- クライアントが token だけを upsert(on_conflict=token) していたため、
--   ① user_id は最初の登録者に固定され、後からサインイン/別アカウント切替で現在のユーザーへ付け替わらない
--   ② 他ユーザーの行は RLS で更新できず upsert が実質失敗
-- → 後発アカウントの device_tokens が作られず、そのユーザー宛の push が一切届かない欠陥だった。
--
-- 対策: SECURITY DEFINER 関数で「同一トークンの他ユーザー行を剥がして auth.uid() に付け替える」。
-- 1端末＝現在ログイン中の1アカウントに通知を寄せる（バックグラウンドの旧アカウントには送らない）。
-- 0021 までの後に適用する。Edge Function の再デプロイは不要（SQL のみ）。
create or replace function public.set_device_token(p_token text, p_platform text default 'ios')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- 同じトークンが別ユーザーに紐付いていたら剥がす（端末を現在のアカウントへ移譲）。
  delete from public.device_tokens where token = p_token and user_id <> auth.uid();

  -- 現在のユーザーへ upsert（既に自分の行があれば更新）。
  insert into public.device_tokens (user_id, token, platform, updated_at)
  values (auth.uid(), p_token, coalesce(p_platform, 'ios'), now())
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.set_device_token(text, text) from public;
grant execute on function public.set_device_token(text, text) to authenticated;

-- ============================================================
-- migrations/0023_exercise_set_distance.sql
-- ============================================================
-- 有酸素種目（cardio）の距離km。距離km ＋ 時間（duration_seconds に分×60で保存）で記録する。
alter table public.exercise_sets add column if not exists distance_km double precision;
-- 距離は 0 以上のみ許可（負値が同期 payload 経由で全端末へ複製されるのを防ぐ）。
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'exercise_sets_distance_km_non_negative'
  ) then
    alter table public.exercise_sets
      add constraint exercise_sets_distance_km_non_negative
      check (distance_km is null or distance_km >= 0);
  end if;
end $$;

-- ============================================================
-- migrations/0026_push_on_follow.sql
-- ============================================================
-- フォロー → フォローされた人へ push（ソーシャルループ）。comments の通知（0019）をミラー。
-- follows への新規 insert を起点に Edge Function `send-push` を { event:'follow', followId } で呼ぶ。
create or replace function public.notify_follow()
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
  -- バックフィル/一括同期での暴発を防ぐため直近のフォローのみ通知。
  if new.created_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'follow', 'followId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_follow on public.follows;
create trigger trg_notify_follow
  after insert on public.follows
  for each row execute function public.notify_follow();

-- ============================================================
-- migrations/0027_workout_duration.sql
-- ============================================================
-- ワークアウト総合時間（秒）。完了時にライブ経過から確定、またはユーザーが手動で登録/修正する。
-- null は未計測（過去日の後追い記録など）。負値が同期 payload 経由で複製されるのを防ぐ。
alter table public.workouts add column if not exists duration_seconds integer;
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'workouts_duration_seconds_non_negative'
  ) then
    alter table public.workouts
      add constraint workouts_duration_seconds_non_negative
      check (duration_seconds is null or duration_seconds >= 0);
  end if;
end $$;

-- ============================================================
-- migrations/0028_notify_report.sql
-- ============================================================
-- 通報 → 運営へメール通知。reports への新規 insert を起点に Edge Function `send-push` を
-- { event:'report', reportId } で呼び、send-push が Resend で運営宛にメールを送る（0019 のコメント通知をミラー）。
-- 宛先/送信元/APIキーは send-push のシークレット（REPORT_NOTIFY_TO / REPORT_NOTIFY_FROM / RESEND_API_KEY）で設定する。

create or replace function public.notify_report()
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

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'report', 'reportId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_report on public.reports;
create trigger trg_notify_report
  after insert on public.reports
  for each row execute function public.notify_report();

-- ============================================================
-- migrations/0029_dedup_exercises_deterministic.sql
-- ============================================================
-- 種目マスタの重複掃除＋決定的id化（同名別idのプリセット増殖を根治）。
-- プリセット名は決定的id（uuid_generate_v5(ns, name)＝クライアント SeedData.presetId と一致）へ収束させ、
-- 同名の参照（workout_exercises / personal_records / routine_exercises）を付け替えてから重複を削除する。
-- カスタム種目（プリセット名以外）の同名重複は、参照最多の1件へマージ（id はそのまま）。
-- 冪等: 新規DBは exercises 空で no-op。単一 DO ブロックで原子的に実行する。

create extension if not exists "uuid-ossp";

do $$
declare
  ns constant uuid := '1b671a64-40d5-491e-99b0-da01ff1f3341';
  preset_names text[] := array[
    'ベンチプレス','インクラインベンチプレス','ダンベルプレス','チェストプレス','ペックフライ',
    'スミスマシンベンチプレス','ディップス','デッドリフト','ベントオーバーロウ','ラットプルダウン',
    'シーテッドロウ','懸垂','スクワット','スミスマシンスクワット','レッグプレス',
    'レッグエクステンション','レッグカール','ルーマニアンデッドリフト','カーフレイズ','ショルダープレス',
    'ダンベルショルダープレス','スミスマシンショルダープレス','サイドレイズ','リアレイズ','アップライトロウ',
    'バーベルカール','ダンベルカール','ハンマーカール','トライセプスプレスダウン','スカルクラッシャー',
    'クランチ','シットアップ','レッグレイズ','ケーブルクランチ','アブローラー',
    'プランク','ヒップスラスト','バーピー','ケトルベルスイング','クリーン&ジャーク',
    'ウォーキング','ランニング','バイシクル'
  ];
  nm text;
  cid uuid;
  mg text;
  eq text;
  r record;
  keeper uuid;
begin
  -- (1) プリセット名 → 決定的id へ収束
  foreach nm in array preset_names loop
    cid := uuid_generate_v5(ns, nm);
    select e.muscle_group, e.equipment into mg, eq
      from public.exercises e where e.name = nm order by e.updated_at desc limit 1;
    -- 既存の同名行が1件も無い（新規DB等）なら何もしない＝空DBで bogus 行を作らず no-op。
    if cid is not null and exists (select 1 from public.exercises where name = nm) then
      insert into public.exercises (id, name, muscle_group, equipment, is_custom, created_by, updated_at)
        values (cid, nm, coalesce(mg, 'chest'), coalesce(eq, 'barbell'), false, null, now())
        on conflict (id) do nothing;
      update public.workout_exercises w set exercise_id = cid
        from public.exercises e where w.exercise_id = e.id and e.name = nm and e.id <> cid;
      update public.personal_records p set exercise_id = cid
        from public.exercises e where p.exercise_id = e.id and e.name = nm and e.id <> cid;
      update public.routine_exercises rr set exercise_id = cid
        from public.exercises e where rr.exercise_id = e.id and e.name = nm and e.id <> cid;
      delete from public.exercises e where e.name = nm and e.id <> cid;
    end if;
  end loop;

  -- (2) カスタム（プリセット名以外）の同名重複 → 参照最多の1件へマージ
  for r in
    select name from public.exercises
    where name <> all(preset_names)
    group by name having count(*) > 1
  loop
    select e.id into keeper from public.exercises e
      where e.name = r.name
      order by (select count(*) from public.workout_exercises w where w.exercise_id = e.id)
             + (select count(*) from public.routine_exercises rr where rr.exercise_id = e.id)
             + (select count(*) from public.personal_records p where p.exercise_id = e.id) desc,
             e.updated_at asc
      limit 1;
    update public.workout_exercises w set exercise_id = keeper
      from public.exercises e where w.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    update public.personal_records p set exercise_id = keeper
      from public.exercises e where p.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    update public.routine_exercises rr set exercise_id = keeper
      from public.exercises e where rr.exercise_id = e.id and e.name = r.name and e.id <> keeper;
    delete from public.exercises e where e.name = r.name and e.id <> keeper;
  end loop;
end $$;

-- ============================================================
-- migrations/0030_preset_exercises_master.sql
-- ============================================================
-- プリセット種目のサーバーマスタ化（created_by IS NULL・決定的id）。
--
-- 背景: クライアントの起動時 backfill が全プリセットを created_by=自分 で push していたため、
-- 最初のユーザーがプリセット43件を「所有」し、2人目以降の同 id upsert（決定的idで全端末同一）が
-- RLS(exercises_update_own) で拒否（42501）→ outbox に永久滞留していた。
-- 本migrationでプリセットをマスタ行（created_by IS NULL）へ収束し、クライアント側は
-- is_custom=true のみ push する（SwiftDataSyncStore.payload / AppEnvironment.backfill）。
--
-- 内容:
--   (1) 43プリセットを決定的id（uuid_generate_v5・SeedData.presetId と同値）で upsert。
--       既存の所有付き同id行は in-place でマスタへ収束（created_by=null / 属性を正準値へ）。
--   (2) 同名の非マスタ・プリセット行（旧ランダムid）から参照を付け替えて削除（0029と同パターン）。
--       ユーザー作成（is_custom=true）の同名行には触れない。
-- 冪等: 再実行しても (1) の updated_at が進む以外は無影響。

create extension if not exists "uuid-ossp";

do $$
declare
  ns constant uuid := '1b671a64-40d5-491e-99b0-da01ff1f3341';
  cid uuid;
  p record;
begin
  for p in
    select * from (values
      -- 胸
      ('ベンチプレス',             'chest',     'barbell',    'weight',     'both',    'none'),
      ('インクラインベンチプレス', 'chest',     'barbell',    'weight',     'both',    'none'),
      ('ダンベルプレス',           'chest',     'dumbbell',   'weight',     'perSide', 'none'),
      ('チェストプレス',           'chest',     'machine',    'weight',     'none',    'none'),
      ('ペックフライ',             'chest',     'machine',    'weight',     'none',    'none'),
      ('スミスマシンベンチプレス', 'chest',     'machine',    'weight',     'both',    'none'),
      ('ディップス',               'chest',     'bodyweight', 'bodyweight', 'none',    'assisted'),
      -- 背中
      ('デッドリフト',             'back',      'barbell',    'weight',     'both',    'none'),
      ('ベントオーバーロウ',       'back',      'barbell',    'weight',     'both',    'none'),
      ('ラットプルダウン',         'back',      'cable',      'weight',     'none',    'none'),
      ('シーテッドロウ',           'back',      'cable',      'weight',     'none',    'none'),
      ('懸垂',                     'back',      'bodyweight', 'bodyweight', 'none',    'assisted'),
      -- 脚
      ('スクワット',               'legs',      'barbell',    'weight',     'both',    'none'),
      ('スミスマシンスクワット',   'legs',      'machine',    'weight',     'both',    'none'),
      ('レッグプレス',             'legs',      'machine',    'weight',     'none',    'none'),
      ('レッグエクステンション',   'legs',      'machine',    'weight',     'none',    'none'),
      ('レッグカール',             'legs',      'machine',    'weight',     'none',    'none'),
      ('ルーマニアンデッドリフト', 'legs',      'barbell',    'weight',     'both',    'none'),
      ('カーフレイズ',             'legs',      'machine',    'weight',     'none',    'none'),
      -- 肩
      ('ショルダープレス',         'shoulders', 'machine',    'weight',     'none',    'none'),
      ('ダンベルショルダープレス', 'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('スミスマシンショルダープレス', 'shoulders', 'machine', 'weight',    'both',    'none'),
      ('サイドレイズ',             'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('リアレイズ',               'shoulders', 'dumbbell',   'weight',     'perSide', 'none'),
      ('アップライトロウ',         'shoulders', 'barbell',    'weight',     'both',    'none'),
      -- 腕
      ('バーベルカール',           'arms',      'barbell',    'weight',     'both',    'none'),
      ('ダンベルカール',           'arms',      'dumbbell',   'weight',     'perSide', 'none'),
      ('ハンマーカール',           'arms',      'dumbbell',   'weight',     'perSide', 'none'),
      ('トライセプスプレスダウン', 'arms',      'cable',      'weight',     'none',    'none'),
      ('スカルクラッシャー',       'arms',      'barbell',    'weight',     'both',    'none'),
      -- 腹
      ('クランチ',                 'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('シットアップ',             'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('レッグレイズ',             'abs',       'bodyweight', 'bodyweight', 'none',    'none'),
      ('ケーブルクランチ',         'abs',       'cable',      'weight',     'none',    'none'),
      ('アブローラー',             'abs',       'other',      'bodyweight', 'none',    'none'),
      -- 体幹
      ('プランク',                 'core',      'bodyweight', 'time',       'none',    'none'),
      -- 臀部
      ('ヒップスラスト',           'glutes',    'barbell',    'weight',     'none',    'none'),
      -- 全身
      ('バーピー',                 'full_body', 'bodyweight', 'bodyweight', 'none',    'none'),
      ('ケトルベルスイング',       'full_body', 'kettlebell', 'weight',     'none',    'none'),
      ('クリーン&ジャーク',        'full_body', 'barbell',    'weight',     'both',    'none'),
      -- 有酸素
      ('ウォーキング',             'cardio',    'other',      'cardio',     'none',    'none'),
      ('ランニング',               'cardio',    'other',      'cardio',     'none',    'none'),
      ('バイシクル',               'cardio',    'other',      'cardio',     'none',    'none')
    ) as v(name, muscle_group, equipment, measurement_type, weight_mode, load_mode)
  loop
    cid := uuid_generate_v5(ns, p.name);

    -- (1) マスタ行を upsert。既存の所有付き同id行も in-place でマスタへ収束する。
    insert into public.exercises
      (id, name, muscle_group, equipment, is_custom, created_by,
       weight_mode, measurement_type, load_mode, updated_at)
    values
      (cid, p.name, p.muscle_group, p.equipment, false, null,
       p.weight_mode, p.measurement_type, p.load_mode, now())
    on conflict (id) do update
      set created_by       = null,
          is_custom        = false,
          name             = excluded.name,
          muscle_group     = excluded.muscle_group,
          equipment        = excluded.equipment,
          weight_mode      = excluded.weight_mode,
          measurement_type = excluded.measurement_type,
          load_mode        = excluded.load_mode,
          updated_at       = now();

    -- (2) 同名の非マスタ・プリセット行（旧ランダムid）→ 参照を付け替えて削除。
    --     ユーザー作成（is_custom=true）は対象外。
    update public.workout_exercises w set exercise_id = cid
      from public.exercises e
      where w.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    update public.personal_records pr set exercise_id = cid
      from public.exercises e
      where pr.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    update public.routine_exercises rr set exercise_id = cid
      from public.exercises e
      where rr.exercise_id = e.id and e.name = p.name and e.id <> cid and e.is_custom = false;
    delete from public.exercises e
      where e.name = p.name and e.id <> cid and e.is_custom = false;
  end loop;
end $$;

-- ============================================================
-- migrations/0031_anonymous_restrictions.sql
-- ============================================================
-- 匿名（is_anonymous）ユーザーの公開系書き込みを RLS で禁止する。
--
-- 背景: 匿名認証（Phase 2・docs/identity-environment-design.md）でゲストにも安定 uid を発行し
-- 記録を同期するが、公開フィード・ソーシャル操作は本人性のあるアカウント限定とする。
--   - ゲスト/デモ由来のデータが公開フィードへ露出する事故（2026-07-10 の dev データ混入と同種）の二重防御
--   - 匿名の使い捨てアカウントによるスパム・荒らしの抑止
--
-- restrictive policy は既存の permissive policy と AND 結合されるため、既存の所有チェックは
-- そのまま生きる。select は制限しない（匿名でも公開フィードの閲覧は可）。
-- JWT の is_anonymous claim で判定する（クレームが無い旧トークンは非匿名として扱う）。

create or replace function public.is_anonymous_user()
returns boolean
language sql stable as $$
    select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
$$;

-- 公開フィードへの投稿は本登録のみ（friends/private の同期は匿名でも可）。
drop policy if exists feed_items_no_anonymous_public on public.feed_items;
create policy feed_items_no_anonymous_public on public.feed_items
    as restrictive for insert to authenticated
    with check (not (public.is_anonymous_user() and visibility = 'public'));
drop policy if exists feed_items_no_anonymous_public_update on public.feed_items;
create policy feed_items_no_anonymous_public_update on public.feed_items
    as restrictive for update to authenticated
    with check (not (public.is_anonymous_user() and visibility = 'public'));

-- フォロー・リアクション・コメントは本登録のみ。
drop policy if exists follows_no_anonymous on public.follows;
create policy follows_no_anonymous on public.follows
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
drop policy if exists post_reactions_no_anonymous on public.post_reactions;
create policy post_reactions_no_anonymous on public.post_reactions
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
drop policy if exists comments_no_anonymous on public.comments;
create policy comments_no_anonymous on public.comments
    as restrictive for insert to authenticated
    with check (not public.is_anonymous_user());
