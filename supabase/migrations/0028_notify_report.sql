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
