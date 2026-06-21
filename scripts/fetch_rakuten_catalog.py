#!/usr/bin/env python3
"""
楽天 Ichiba Item Search API でキュレーション商品の「実商品ディープリンク＋実価格＋画像」を取得し、
Supabase products テーブル更新用の UPDATE SQL を生成する。

使い方:
  RAKUTEN_APP_ID=<楽天アプリID> python3 scripts/fetch_rakuten_catalog.py > supabase/catalog_from_rakuten.sql
  （affiliateId は既定で Gymnee の楽天アフィリエイトIDを使用。RAKUTEN_AFFILIATE_ID で上書き可）
  生成された SQL を psql で Supabase に流す。

API キー（applicationId）はアプリに埋め込まず、ここ（サーバ側生成）に留める。
"""
import os, sys, json, time
from urllib.parse import urlencode
from urllib.request import urlopen, Request

APP_ID = os.environ.get("RAKUTEN_APP_ID", "").strip()
AFFILIATE_ID = os.environ.get("RAKUTEN_AFFILIATE_ID", "5519a6c7.399a4850.5519a6c8.91d431bc").strip()
ENDPOINT = "https://app.rakuten.co.jp/services/api/IchibaItem/Search/20220601"

# キュレーション: (Supabaseの商品名=キー, 検索キーワード)
CURATED = [
    ("ホエイプロテイン 1kg", "ホエイプロテイン 1kg"),
    ("ソイプロテイン 1kg", "ソイプロテイン 1kg"),
    ("クレアチン 500g", "クレアチン モノハイドレート"),
    ("EAA 500g", "EAA アミノ酸 粉末"),
    ("マルトデキストリン 1kg", "マルトデキストリン 1kg"),
    ("リストラップ", "リストラップ 筋トレ"),
    ("トレーニングベルト", "トレーニングベルト リフティング"),
]

def sql_escape(s):
    return (s or "").replace("'", "''")

def search(keyword):
    params = {
        "applicationId": APP_ID,
        "affiliateId": AFFILIATE_ID,
        "keyword": keyword,
        "hits": 5,
        "sort": "+reviewCount",   # レビュー数の多い＝信頼できる商品優先（"-reviewCount"で降順）
        "availability": 1,        # 在庫あり
        "imageFlag": 1,           # 画像ありのみ
        "format": "json",
    }
    req = Request(ENDPOINT + "?" + urlencode(params), headers={"User-Agent": "Gymnee/1.0"})
    with urlopen(req, timeout=20) as r:
        return json.load(r)

def pick_best(items):
    # レビュー数×平均が高い、在庫ありの先頭を採用。降順に並べ替え。
    scored = []
    for it in items:
        item = it.get("Item", it)
        score = (item.get("reviewCount", 0) or 0) * (item.get("reviewAverage", 0) or 0)
        scored.append((score, item))
    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0][1] if scored else None

def main():
    if not APP_ID:
        sys.stderr.write("ERROR: RAKUTEN_APP_ID を環境変数で渡してください。\n")
        sys.exit(1)
    print("-- 楽天 Ichiba Item Search API から生成（実商品ディープリンク＋実価格＋画像）")
    print("-- 再実行で最新に更新できる。Supabase products を商品名キーで UPDATE。")
    for name, keyword in CURATED:
        try:
            data = search(keyword)
        except Exception as e:
            sys.stderr.write(f"WARN {name}: API失敗 {e}\n"); continue
        item = pick_best(data.get("Items", []))
        if not item:
            sys.stderr.write(f"WARN {name}: 商品なし\n"); continue
        aff_url = item.get("affiliateUrl") or item.get("itemUrl")
        price = item.get("itemPrice") or 0
        imgs = item.get("mediumImageUrls") or []
        img = ""
        if imgs:
            img = imgs[0].get("imageUrl", "") if isinstance(imgs[0], dict) else str(imgs[0])
            img = img.replace("?_ex=128x128", "")  # サイズ指定を外して原寸寄りに
        shop = item.get("shopName") or "楽天市場"
        print(
            f"update public.products set "
            f"affiliate_url='{sql_escape(aff_url)}', price={int(price)}, "
            f"image_url='{sql_escape(img)}', merchant='{sql_escape(shop)}', updated_at=now() "
            f"where name='{sql_escape(name)}';"
        )
        sys.stderr.write(f"OK {name}: {item.get('itemName','')[:30]}… ¥{price}\n")
        time.sleep(0.4)  # API レート制限に配慮

if __name__ == "__main__":
    main()
