---
description: マーケ施策 (ASO変更/価格変更/SNS/紹介など) を analytics/campaigns.md に記録する。後の相関・帰属分析の土台
argument-hint: "<施策の説明 (例: X で beta 募集ポスト / App Store スクショ刷新)>"
disable-model-invocation: true
allowed-tools: Read, Edit
---

実施したマーケ施策を `analytics/campaigns.md` の台帳に 1 行追記する。アプリ側の変更は不要。**施策をやったらすぐ記録する**のがループの精度を左右する。

## 手順

1. `analytics/campaigns.md` を読み、フォーマット (列定義) を把握する。
2. `$ARGUMENTS` から以下を埋める。不足は簡潔に確認する (過剰な質問はしない):
   - **date** (JST・施策実施日。「昨日」等は今日の日付から換算)
   - **channel** (aso / price / social / referral / influencer / pr / community / other)
   - **detail** (何をしたか)
   - **quantity** (投稿数・配布数・対象数など、あれば)
   - **cost** (概算、あれば)
   - **area/target** (エリアやセグメント、あれば)
   - **notes** (キャンペーンリンク/招待コードの有無、狙いなど)
3. 台帳末尾に追記する (Edit)。既存行は消さない。
4. 追記した行を提示し、「次の `/growth-report` でこの施策日と登録スパイク (`registration.byDayJst`) の相関を見る」と案内する。

## 注意

- 現状 DL→施策の**帰属は未計装** (キャンペーンリンク / オンボ内 "どこで知った" は未導入)。この台帳は**相関の手掛かり**。断定材料にはしない。
- 帰属を本格化したくなったら docs/growth-harness.md の「保留中: 帰属計装」を参照 (Apple キャンペーンリンク / 招待コード / オンボ 1 問)。
