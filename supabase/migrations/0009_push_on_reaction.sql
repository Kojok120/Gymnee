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
