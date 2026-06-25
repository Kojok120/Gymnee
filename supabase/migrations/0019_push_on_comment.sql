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
