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
