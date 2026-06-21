-- Gymnee サーバ側プリセット投入（任意）。products は RLS でクライアント書込不可のため、
-- カタログはここ（またはEdge Function/管理）から投入する。
-- affiliate_url は楽天アフィリエイト計測リダイレクト（ID: 5519a6c7...）。クリック経由の購入で手数料が発生。

insert into public.products (name, description, price, category, goal_tags, merchant, affiliate_url, servings_per_unit)
values
    ('ホエイプロテイン 1kg', '高純度ホエイ。増量・維持の基本。', 3980, 'プロテイン', array['bulk','maintain'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%9B%E3%82%A8%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg%2F', 33),
    ('ソイプロテイン 1kg', '植物性。減量フェーズに。', 3580, 'プロテイン', array['cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%82%BD%E3%82%A4%E3%83%97%E3%83%AD%E3%83%86%E3%82%A4%E3%83%B3%201kg%2F', 33),
    ('クレアチン 500g', '高強度トレの定番サプリ。', 2480, 'サプリ', array['strength','bulk'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%82%AF%E3%83%AC%E3%82%A2%E3%83%81%E3%83%B3%20%E3%83%A2%E3%83%8E%E3%83%8F%E3%82%A4%E3%83%89%E3%83%AC%E3%83%BC%E3%83%88%2F', 100),
    ('EAA 500g', 'トレ中のアミノ酸補給。', 4280, 'サプリ', array['maintain','cut'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2FEAA%20%E3%82%A2%E3%83%9F%E3%83%8E%E9%85%B8%2F', 50),
    ('マルトデキストリン 1kg', '増量期のカロリー補給に。', 1880, 'カーボ', array['bulk'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%9E%E3%83%AB%E3%83%88%E3%83%87%E3%82%AD%E3%82%B9%E3%83%88%E3%83%AA%E3%83%B3%201kg%2F', 20),
    ('リストラップ', '高重量プレス系の手首保護。', 1980, 'ギア', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%AA%E3%82%B9%E3%83%88%E3%83%A9%E3%83%83%E3%83%97%20%E7%AD%8B%E3%83%88%E3%83%AC%2F', null),
    ('トレーニングベルト', 'スクワット/デッドの体幹サポート。', 5980, 'ギア', array['strength'], '楽天市場', 'https://hb.afl.rakuten.co.jp/hgc/5519a6c7.399a4850.5519a6c8.91d431bc/?pc=https%3A%2F%2Fsearch.rakuten.co.jp%2Fsearch%2Fmall%2F%E3%83%88%E3%83%AC%E3%83%BC%E3%83%8B%E3%83%B3%E3%82%B0%E3%83%99%E3%83%AB%E3%83%88%2F', null)
on conflict do nothing;
