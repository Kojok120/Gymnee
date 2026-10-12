-- ライブ中の応援を、そのワークアウトの投稿の応援として引き継ぐ（issue #148）。
--
-- これまで: ライブ中の応援（session_cheers）は記録中の画面に出るだけで、記録を終えて投稿すると
-- 応援した人は消えていた（投稿の応援 post_reactions とは別のテーブルで、つながりも無い）。
-- これから: ライブを始めるときに記録中のワークアウトの id を live_sessions に持たせ、
-- そのワークアウトの投稿（feed_items, type='workout', ref_id=ワークアウト id）ができたら、
-- ライブ中に応援した人を投稿の応援として写す。投稿のあとに届いた応援（完了画面を開いている間）も写す。
--
-- - 1人1件。アプリは「1投稿につき1人1種類」の前提なので、同じ人が複数の種類で応援していたら最後の1つにする
-- - すでにその投稿へ応援している人には写さない（本人の選んだ応援を優先）
-- - 投稿者とブロックし合っている人は写さない
-- - 写した行では「〇〇さんが応援しました」の通知を送らない（ライブ中に応援の通知は届いている）
-- - updated_at は写した時刻にする（応援した時刻にすると、差分の取り込みの基準より古くて他の端末に届かない）

-- 1) ライブの間に記録していたワークアウト。下書きはサーバーに無いので外部キーは張らない。
alter table public.live_sessions add column if not exists workout_id uuid;
create index if not exists live_sessions_workout_idx
  on public.live_sessions (user_id, workout_id) where workout_id is not null;

-- 2) 引き継ぎの本体。投稿 1 件に、そのワークアウトのライブ中の応援を写す（何度呼んでも同じ結果）。
create or replace function public.copy_live_cheers_to_post(p_feed_item_id uuid, p_owner uuid, p_workout_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('gymnee.copying_live_cheers', 'on', true);
  insert into public.post_reactions (user_id, feed_item_id, kind, created_at, updated_at)
  select distinct on (c.user_id) c.user_id, p_feed_item_id, c.kind, c.created_at, now()
  from public.session_cheers c
  join public.live_sessions s on s.id = c.session_id
  where s.workout_id = p_workout_id
    and s.user_id = p_owner
    and c.user_id <> p_owner
    and not exists (
      select 1 from public.post_reactions r
      where r.feed_item_id = p_feed_item_id and r.user_id = c.user_id
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = p_owner and b.blocked_id = c.user_id)
         or (b.blocker_id = c.user_id and b.blocked_id = p_owner)
    )
  order by c.user_id, c.created_at desc
  on conflict (user_id, feed_item_id, kind) do nothing;
  perform set_config('gymnee.copying_live_cheers', 'off', true);
end;
$$;

-- 投稿の応援を作れてしまうので、アプリからは呼べなくする（トリガーからだけ使う）。
revoke all on function public.copy_live_cheers_to_post(uuid, uuid, uuid) from public, anon, authenticated;

-- 3) 投稿ができたとき（「ソーシャルに投稿」や公開範囲の変更で feed_item が作られたとき）。
create or replace function public.copy_live_cheers_on_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type = 'workout' then
    perform public.copy_live_cheers_to_post(new.id, new.user_id, new.ref_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_copy_live_cheers_on_post on public.feed_items;
create trigger trg_copy_live_cheers_on_post
  after insert on public.feed_items
  for each row execute function public.copy_live_cheers_on_post();

-- 4) 投稿のあとに届いたライブの応援（完了画面を開いている間はライブが続いている）。
create or replace function public.copy_cheer_to_existing_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_workout uuid;
  v_item uuid;
begin
  select s.user_id, s.workout_id into v_owner, v_workout
  from public.live_sessions s where s.id = new.session_id;
  if v_workout is null then
    return new;
  end if;
  select f.id into v_item
  from public.feed_items f
  where f.type = 'workout' and f.ref_id = v_workout and f.user_id = v_owner
  limit 1;
  if v_item is not null then
    perform public.copy_live_cheers_to_post(v_item, v_owner, v_workout);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_copy_cheer_to_existing_post on public.session_cheers;
create trigger trg_copy_cheer_to_existing_post
  after insert on public.session_cheers
  for each row execute function public.copy_cheer_to_existing_post();

-- 5) 応援の通知（0013）。写した行では送らない。それ以外は 0013 と同じ。
create or replace function public.notify_post_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.push_config;
begin
  -- ライブ中の応援を写した行（上の copy_live_cheers_to_post）。通知はライブ中に届いている。
  if current_setting('gymnee.copying_live_cheers', true) = 'on' then
    return new;
  end if;
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
