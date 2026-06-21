-- Gymnee サーバ側プリセット投入（任意）。
-- products は RLS でクライアント書込不可のため、カタログはここ（またはEdge Function/管理画面）から投入する。
-- affiliate_url は提携先の検索ページ（計測タグ無し）。ASP登録後に計測タグ付きURLへ差し替えること。

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
values
    ('ホエイプロテイン 1kg', '高純度ホエイ。増量・維持の基本。', 3980, 'プロテイン', array['bulk','maintain'], '楽天市場', 'https://search.rakuten.co.jp/search/mall/%E3%83%9B%E3%82%A8%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg/', 33),
    ('ソイプロテイン 1kg', '植物性。減量フェーズに。', 3580, 'プロテイン', array['cut'], '楽天市場', 'https://search.rakuten.co.jp/search/mall/%E3%82%BD%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg/', 33),
    ('クレアチン 500g', '高強度トレの定番サプリ。', 2480, 'サプリ', array['strength','bulk'], 'iHerb', 'https://jp.iherb.com/search?kw=creatine%20monohydrate', 100),
    ('EAA 500g', 'トレ中のアミノ酸補給。', 4280, 'サプリ', array['maintain','cut'], 'iHerb', 'https://jp.iherb.com/search?kw=eaa', 50),
    ('マルトデキストリン 1kg', '増量期のカロリー補給に。', 1880, 'カーボ', array['bulk'], '楽天市場', 'https://search.rakuten.co.jp/search/mall/%E3%83%9E%E3%83%AB%E3%83%88%E3%83%87%E3%82%AD%E3%82%B9%E3%83%88%E3%83%AA%E3%83%B3%201kg/', 20),
    ('リストラップ', '高重量プレス系の手首保護。', 1980, 'ギア', array['strength'], '楽天市場', 'https://search.rakuten.co.jp/search/mall/%E3%83%AA%E3%82%B9%E3%83%88%E3%83%A9%E3%83%83%E3%83%97%20%E7%AD%8B%E3%83%88%E3%83%AC/', null),
    ('トレーニングベルト', 'スクワット/デッドの体幹サポート。', 5980, 'ギア', array['strength'], '楽天市場', 'https://search.rakuten.co.jp/search/mall/%E3%83%88%E3%83%AC%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0%E3%83%99%E3%83%AB%E3%83%88/', null)
on conflict do nothing;
