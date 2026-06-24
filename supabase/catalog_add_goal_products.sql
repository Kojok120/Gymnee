-- 目標固有のアフィリエイト商品を追加（既存ライブDB向け・冪等）。
-- products.name に一意制約が無いため on conflict が効かない → 名前で未登録チェックして追加する。
-- 適用: Supabase SQL Editor に貼り付けて実行。再実行しても重複しない。
-- 画像/実価格は後から catalog_from_rakuten 同様の name 一致 UPDATE で差し替え可能。

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'L-カルニチン 1000mg', '脂肪をエネルギーに変える代謝サポート。減量期に。', 2680, 'サプリ', array['cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2FL%2D%E3%82%AB%E3%83%AB%E3%83%8B%E3%83%81%E3%83%B3%20%E3%82%B5%E3%83%97%E3%83%AA%2F', 60
where not exists (select 1 from public.products where name = 'L-カルニチン 1000mg');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'CLA 共役リノール酸', '体脂肪対策の定番サプリ。減量と併用。', 2480, 'サプリ', array['cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2FCLA%20%E5%85%B1%E5%BD%B9%E3%83%AA%E3%83%8E%E3%83%BC%E3%83%AB%E9%85%B8%2F', 90
where not exists (select 1 from public.products where name = 'CLA 共役リノール酸');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select '難消化性デキストリン 500g', '食物繊維。糖の吸収をおだやかに・満腹感。', 1280, 'サプリ', array['cut','maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E9%9B%A3%E6%B6%88%E5%8C%96%E6%80%A7%E3%83%87%E3%82%AD%E3%82%B9%E3%83%88%E3%83%AA%E3%83%B3%2F', 50
where not exists (select 1 from public.products where name = '難消化性デキストリン 500g');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'マルチビタミン&ミネラル', '不足しがちな微量栄養素の土台。', 1980, 'サプリ', array['maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%83%9E%E3%83%AB%E3%83%81%E3%83%93%E3%82%BF%E3%83%9F%E3%83%B3%20%E3%83%9F%E3%83%8D%E3%83%A9%E3%83%AB%2F', 60
where not exists (select 1 from public.products where name = 'マルチビタミン&ミネラル');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'フィッシュオイル オメガ3', 'EPA/DHA。日々のコンディション維持に。', 1780, 'サプリ', array['maintain','cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%83%95%E3%82%A3%E3%83%83%E3%82%B7%E3%83%A5%E3%82%AA%E3%82%A4%E3%83%AB%20%E3%82%AA%E3%83%A1%E3%82%AC3%20EPA%20DHA%2F', 90
where not exists (select 1 from public.products where name = 'フィッシュオイル オメガ3');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'ビタミンD3', '骨・免疫・ホルモンの土台。', 980, 'サプリ', array['maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%83%93%E3%82%BF%E3%83%9F%E3%83%B3D3%20%E3%82%B5%E3%83%97%E3%83%AA%2F', 120
where not exists (select 1 from public.products where name = 'ビタミンD3');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'ウエイトゲイナー 3kg', '高カロリー。食が細い人の増量に。', 5480, 'プロテイン', array['bulk'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%82%A6%E3%82%A8%E3%82%A4%E3%83%88%E3%82%B2%E3%82%A4%E3%83%8A%E3%83%BC%20%E5%A2%97%E9%87%8F%2F', 30
where not exists (select 1 from public.products where name = 'ウエイトゲイナー 3kg');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'カゼインプロテイン 1kg', '就寝前のゆっくり供給。維持・増量に。', 4280, 'プロテイン', array['bulk','maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%82%AB%E3%82%BC%E3%82%A4%E3%83%B3%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%2F', 33
where not exists (select 1 from public.products where name = 'カゼインプロテイン 1kg');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'ベータアラニン 200g', '高強度の粘り。筋力・高レップに。', 2280, 'サプリ', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%83%99%E3%83%BC%E3%82%BF%E3%82%A2%E3%83%A9%E3%83%8B%E3%83%B3%2F', 60
where not exists (select 1 from public.products where name = 'ベータアラニン 200g');

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
select 'パワーグリップ', '引く種目の握力補助。背中・デッドに。', 2980, 'ギア', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519c310.d841aa29.5519c311.eac66aa0/?pc=https%3A%2F%2Fsearch%2Erakuten%2Eco%2Ejp%2Fsearch%2Fmall%2F%E3%83%91%E3%83%AF%E3%83%BC%E3%82%B0%E3%83%AA%E3%83%83%E3%83%97%20%E7%AD%8B%E3%83%88%E3%83%AC%2F', null
where not exists (select 1 from public.products where name = 'パワーグリップ');

