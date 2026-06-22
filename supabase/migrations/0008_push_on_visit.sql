-- フレンドのチェックイン通知（§6.10 / §6.11）。
-- visits への新規 insert を起点に Edge Function `send-push` を非同期で呼び、
-- 訪問者のフォロワーへ「〇〇さんがジムに行きました」を APNs 送信する。
-- 0001〜0007 の後に適用する。
--
-- 前提（DB 設定。秘密値はコミットしないため、適用後に一度だけ設定する。詳細は docs/apns-push-setup.md）:
--   alter database postgres set app.send_push_url = 'https://<project-ref>.supabase.co/functions/v1/send-push';
--   alter database postgres set app.push_secret   = '<Edge Function の PUSH_SHARED_SECRET と同じ値>';
-- 設定後は新規接続から有効（プール接続のため反映に少し時間がかかることがある）。

create extension if not exists pg_net;

create or replace function public.notify_friend_checkin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text := current_setting('app.send_push_url', true);
  secret text := current_setting('app.push_secret', true);
begin
  -- URL 未設定なら何もしない（縮退：ローカル/未構成環境でも insert は成功させる）。
  if fn_url is null or fn_url = '' then
    return new;
  end if;

  -- 過去来店の一括同期（LocalDataMigrator 等のバックフィル）で通知が暴発しないよう、
  -- 直近のチェックインだけ通知する。ON CONFLICT 更新は AFTER INSERT では発火しない。
  if new.visited_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := fn_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(secret, '')
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
