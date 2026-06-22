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
