-- 0036: AI コーチとの会話履歴（#79）
-- 端末をまたいで会話が続くようにサーバーへ持つ。ただし**本人以外には一切見せない**：
-- フィードにも出さず、公開範囲(visibility)の概念も持たせない。RLS は本人のみ全権。
create table if not exists public.coach_messages (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- true = コーチの発言 / false = ユーザーの発言
  is_from_coach boolean not null,
  body text not null,
  -- コーチの返答に添えられたメニュー提案（[{name,sets,reps,weightKg}] の JSON）。無ければ null。
  proposal jsonb,
  -- 提案を実際に取り込んだか（同じ提案を二度適用しないための印）
  is_applied boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 会話の取得は「自分の・新しい順」しかしないので、その形の索引だけ張る。
create index if not exists coach_messages_user_created_idx
  on public.coach_messages (user_id, created_at desc);

-- 差分 pull（updated_at 基準）用。
create index if not exists coach_messages_user_updated_idx
  on public.coach_messages (user_id, updated_at desc);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'coach_messages_body_length') then
    alter table public.coach_messages
      add constraint coach_messages_body_length
      check (char_length(body) <= 4000);
  end if;
end $$;

alter table public.coach_messages enable row level security;

-- 本人のみ全権。他人の会話は select すらできない。
drop policy if exists coach_messages_owner_select on public.coach_messages;
create policy coach_messages_owner_select on public.coach_messages
  for select using (user_id = auth.uid());

drop policy if exists coach_messages_owner_insert on public.coach_messages;
create policy coach_messages_owner_insert on public.coach_messages
  for insert with check (user_id = auth.uid());

drop policy if exists coach_messages_owner_update on public.coach_messages;
create policy coach_messages_owner_update on public.coach_messages
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists coach_messages_owner_delete on public.coach_messages;
create policy coach_messages_owner_delete on public.coach_messages
  for delete using (user_id = auth.uid());
