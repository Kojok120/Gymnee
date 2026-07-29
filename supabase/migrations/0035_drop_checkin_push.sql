-- 0035: チェックイン廃止に伴い、フレンドのチェックイン通知を止める
-- クライアントから visits への書き込みは無くなるためトリガは発火しないが、
-- 旧バージョンのアプリが残っている端末からの insert で通知が飛ぶのを防ぐため明示的に落とす。
--
-- 注意: visits / visit_partners / gyms / gym_equipment の各テーブルと visit-photos バケットは
-- **drop しない**。クライアントが参照しなくなればユーザー影響はゼロで、drop は不可逆なため。
-- 実データの削除はリリース後に問題がないと確認できてから別途行う。
drop trigger if exists trg_notify_friend_checkin on public.visits;
drop function if exists public.notify_friend_checkin();

-- profiles.notify_friend_checkin は送信元が無くなったので参照されない。
-- 列自体は既存行の互換のため残す（既定 true のまま無害）。
