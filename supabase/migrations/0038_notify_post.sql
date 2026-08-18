-- フォロー中ユーザーの新規投稿通知。
-- 投稿内容・公開範囲を通知文に含めず、可視性は Edge Function でも必ず再検証する。

alter table public.profiles add column if not exists notify_post boolean not null default true;

create or replace function public.notify_post()
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
  -- 自分だけの投稿と、バックフィル・一括同期での暴発は送らない。
  if new.visibility = 'private' or new.created_at < now() - interval '10 minutes' then
    return new;
  end if;

  perform net.http_post(
    url     := cfg.send_push_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'X-Push-Secret', coalesce(cfg.push_secret, '')
               ),
    body    := jsonb_build_object('event', 'post', 'postId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_post on public.feed_items;
create trigger trg_notify_post
  after insert on public.feed_items
  for each row execute function public.notify_post();
