#!/usr/bin/env python3
"""
楽天 Ichiba Item Search API でキュレーション商品の「実商品ディープリンク＋実価格＋画像」を取得し、
Supabase products テーブル更新用の UPDATE SQL を生成する。

使い方:
  RAKUTEN_APP_ID=<applicationId(UUID)> RAKUTEN_ACCESS_KEY=<accessKey> \
    python3 scripts/fetch_rakuten_catalog.py > supabase/catalog_from_rakuten.sql
  （affiliateId は既定で Gymnee の楽天アフィリエイトIDを使用。RAKUTEN_AFFILIATE_ID で上書き可）
  生成された SQL を psql で Supabase に流す。

2026年2月の楽天ウェブサービス刷新に対応:
  - エンドポイントが openapi.rakuten.co.jp（旧 app.rakuten.co.jp は 2026/5/13 停止）
  - applicationId が UUID 形式
  - accessKey が必須（ここではヘッダーで渡し URL/ログに残さない）

API キー（applicationId / accessKey）はアプリに埋め込まず、ここ（サーバ側生成）に留める。
"""
import os, sys, json, time
from urllib.parse import urlencode
from urllib.request import urlopen, Request

APP_ID = os.environ.get("RAKUTEN_APP_ID", "").strip()
ACCESS_KEY = os.environ.get("RAKUTEN_ACCESS_KEY", "").strip()
AFFILIATE_ID = os.environ.get("RAKUTEN_AFFILIATE_ID", "5519c310.d841aa29.5519c311.eac66aa0").strip()
ENDPOINT = "https://openapi.rakuten.co.jp/ichibams/api/IchibaItem/Search/20220601"

# キュレーション。各商品で「人気順に取得 → must を含み ng を含まず価格帯に収まる物」を採用。
#   name      : Supabase products の商品名キー
#   keyword   : 検索キーワード
#   must      : itemName にこのいずれかが含まれること（的外れ商品を排除）
#   ng        : itemName にこれらが含まれたら除外（5kg大容量・別カテゴリ等）
#   price     : (下限, 上限) 円。バルク/多袋セットや異常価格を除外
CURATED = [
    {"name": "ホエイプロテイン 1kg", "keyword": "ホエイプロテイン 1kg",
     "must": ["ホエイ", "プロテイン"], "ng": ["5kg", "3kg", "ソイ", "お試し", "ゲイナー", "セット"],
     "price": (1500, 7000)},
    {"name": "ソイプロテイン 1kg", "keyword": "ソイプロテイン 1kg",
     "must": ["ソイ"], "ng": ["ホエイ", "5kg", "3kg", "お試し", "セット"],
     "price": (1500, 7000)},
    {"name": "クレアチン 500g", "keyword": "クレアチン モノハイドレート 500g",
     "must": ["クレアチン"], "ng": ["タブレット", "1kg", "セット", "4個"],
     "price": (1000, 5000)},
    {"name": "EAA 500g", "keyword": "EAA 粉末 500g",
     "must": ["EAA"], "ng": ["BCAA", "カプセル", "タブレット", "セット"],
     "price": (1500, 8000)},
    {"name": "マルトデキストリン 1kg", "keyword": "マルトデキストリン 1kg",
     "must": ["マルトデキストリン", "粉飴"], "ng": ["5kg", "10袋", "3kg", "セット"],
     "price": (800, 4000)},
    {"name": "リストラップ", "keyword": "リストラップ 手首 筋トレ",
     "must": ["リストラップ"], "ng": ["バトルロープ", "ニーラップ", "ニースリーブ", "肘"],
     "price": (700, 4000)},
    {"name": "トレーニングベルト", "keyword": "トレーニングベルト リフティング",
     "must": ["ベルト"], "ng": ["加圧", "ダイエット", "腹", "EMS"],
     "price": (1500, 13000)},
    # --- 目標固有の追加商品（catalog_add_goal_products.sql で投入済みの name と一致させること） ---
    {"name": "L-カルニチン 1000mg", "keyword": "L-カルニチン サプリ",
     "must": ["カルニチン"], "ng": ["ペット", "犬", "猫", "セット"],
     "price": (1000, 5000)},
    {"name": "CLA 共役リノール酸", "keyword": "CLA 共役リノール酸 サプリ",
     "must": ["CLA", "共役リノール酸"], "ng": ["セット"],
     "price": (1000, 5000)},
    {"name": "難消化性デキストリン 500g", "keyword": "難消化性デキストリン 500g",
     "must": ["難消化性デキストリン", "デキストリン"], "ng": ["2kg", "5kg", "セット", "10袋"],
     "price": (700, 3500)},
    {"name": "マルチビタミン&ミネラル", "keyword": "マルチビタミン ミネラル サプリ",
     "must": ["マルチビタミン"], "ng": ["子供", "キッズ", "ペット", "犬", "猫"],
     "price": (700, 4500)},
    {"name": "フィッシュオイル オメガ3", "keyword": "フィッシュオイル オメガ3 EPA DHA",
     "must": ["オメガ", "フィッシュオイル", "EPA", "DHA"], "ng": ["クリル", "ペット", "犬", "猫"],
     "price": (800, 4500)},
    {"name": "ビタミンD3", "keyword": "ビタミンD3 サプリ",
     "must": ["ビタミンD"], "ng": ["子供", "キッズ", "ペット", "クリーム"],
     "price": (500, 3500)},
    {"name": "ウエイトゲイナー 3kg", "keyword": "ウエイトゲイナー 増量 プロテイン",
     "must": ["ゲイナー"], "ng": ["お試し", "1kg"],
     "price": (2000, 9000)},
    {"name": "カゼインプロテイン 1kg", "keyword": "カゼインプロテイン 1kg",
     "must": ["カゼイン"], "ng": ["ホエイ", "お試し", "セット", "3kg"],
     "price": (2000, 8000)},
    {"name": "ベータアラニン 200g", "keyword": "ベータアラニン パウダー",
     "must": ["ベータアラニン", "βアラニン", "βーアラニン"], "ng": ["カプセル", "セット"],
     "price": (1000, 5000)},
    {"name": "パワーグリップ", "keyword": "パワーグリップ 筋トレ",
     "must": ["パワーグリップ"], "ng": ["ニーラップ", "リストラップ", "ベルト"],
     "price": (1000, 6000)},
]

def sql_escape(s):
    return (s or "").replace("'", "''")

def search(keyword):
    params = {
        "applicationId": APP_ID,
        "affiliateId": AFFILIATE_ID,
        "keyword": keyword,
        "hits": 30,
        "sort": "-reviewCount",   # レビュー数の多い＝人気・定番を上位に（"-"で降順）
        "availability": 1,        # 在庫あり
        "imageFlag": 1,           # 画像ありのみ
        "format": "json",
    }
    # accessKey はクエリではなくヘッダーで渡し、URL/ログに秘密情報を残さない。
    headers = {"User-Agent": "Gymnee/1.0", "accessKey": ACCESS_KEY}
    url = ENDPOINT + "?" + urlencode(params)
    # 登録QPSが低い（=1）ため 429 はバックオフして数回リトライ。
    for attempt in range(4):
        try:
            req = Request(url, headers=headers)
            with urlopen(req, timeout=20) as r:
                return json.load(r)
        except Exception as e:
            code = getattr(e, "code", None)
            if code == 429 and attempt < 3:
                wait = 3 * (2 ** attempt)  # 3, 6, 12s
                sys.stderr.write(f"  429: {wait}s 待って再試行…\n")
                time.sleep(wait)
                continue
            raise
    return {}

def _name_of(item):
    return item.get("itemName", "") or ""

def pick_best(spec, raw_items):
    """人気順に取得した候補から、must/ng/価格帯で絞り、レビュー数×平均が最大の物を選ぶ。
    厳しすぎて0件なら段階的に条件を緩める（価格 → must/ng）。"""
    items = [it.get("Item", it) for it in raw_items]
    lo, hi = spec["price"]
    must, ng = spec.get("must", []), spec.get("ng", [])

    def passes(item, use_price=True, use_text=True):
        nm = _name_of(item)
        if use_text and must and not any(m in nm for m in must):
            return False
        if use_text and any(g in nm for g in ng):
            return False
        if use_price:
            p = item.get("itemPrice") or 0
            if p < lo or p > hi:
                return False
        return True

    def best(cands):
        scored = [((it.get("reviewCount", 0) or 0) * max(it.get("reviewAverage", 0) or 0, 1.0), it)
                  for it in cands]
        scored.sort(key=lambda x: x[0], reverse=True)
        return scored[0][1] if scored else None

    for use_price, use_text in ((True, True), (False, True), (False, False)):
        cands = [it for it in items if passes(it, use_price, use_text)]
        if cands:
            return best(cands)
    return items[0] if items else None

def main():
    if not APP_ID:
        sys.stderr.write("ERROR: RAKUTEN_APP_ID(applicationId/UUID) を環境変数で渡してください。\n")
        sys.exit(1)
    if not ACCESS_KEY:
        sys.stderr.write("ERROR: RAKUTEN_ACCESS_KEY(accessKey) を環境変数で渡してください（2026新API必須）。\n")
        sys.exit(1)
    print("-- 楽天 Ichiba Item Search API（新openapi）から生成: 実商品ディープリンク＋実価格＋画像")
    print("-- 再実行で最新に更新できる。Supabase products を商品名キーで UPDATE。")
    for spec in CURATED:
        name = spec["name"]
        try:
            data = search(spec["keyword"])
        except Exception as e:
            sys.stderr.write(f"WARN {name}: API失敗 {e}\n"); continue
        item = pick_best(spec, data.get("Items", []))
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
        rc = item.get("reviewCount", 0); ra = item.get("reviewAverage", 0)
        sys.stderr.write(f"OK {name}: {_name_of(item)[:34]}… ¥{price}（★{ra}/{rc}件）\n")
        time.sleep(1.5)  # 登録QPS=1 を順守

if __name__ == "__main__":
    main()
