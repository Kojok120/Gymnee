-- ⑦E フィードの構造化スタッツ。ワークアウト投稿の種目/セット/ボリューム/時間/PR/部位を
-- JSON 文字列で保持し、フォロワー側でもリッチカードを描けるようにする。
-- text で持つ（サーバ側で検索しないため jsonb 不要・PostgREST 型の取り回しも単純）。
alter table public.feed_items add column if not exists stats_json text;
