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
