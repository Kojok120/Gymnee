-- フレンドごとの通知ON/OFF（監査外・ユーザー要望）。
-- follower→followee の follow 行に notify を持たせ、send-push は notify=true のフォロワーにのみ送る。
-- 本番には supabase db query で適用済み（ここは履歴）。
alter table public.follows add column if not exists notify boolean not null default true;
