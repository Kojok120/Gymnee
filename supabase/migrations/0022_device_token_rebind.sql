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
