-- プッシュ通知の種類別 ON/OFF（ユーザー要望）。
-- send-push は投稿者/受信者の profiles 設定を見て、いいね/フレンドのチェックイン通知を抑制する。
alter table public.profiles add column if not exists notify_likes boolean not null default true;
alter table public.profiles add column if not exists notify_friend_checkin boolean not null default true;
