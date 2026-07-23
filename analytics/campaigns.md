# マーケ施策 台帳 (campaigns)

Gymnee のマーケ施策 (ASO / 価格 / SNS / 紹介 / インフルエンサー / コミュニティ等) を時系列で 1 行ずつ記録する。
`growth-analyst` がこの台帳の施策日と `registration.byDayJst` / DL の登録スパイクの**相関**を見る土台。
**帰属は未計装**なので、これは相関の手掛かりであって因果の断定材料ではない。

施策をやったら `/campaign-log <説明>` で即追記する (やった当日に記録するほどループの精度が上がる)。

## 書式

パイプ区切りの表に 1 行追記する。既存行は消さない。日付は JST。

| 列 | 意味 |
|---|---|
| date | 施策実施日 (JST, YYYY-MM-DD) |
| channel | `aso` / `price` / `social` / `referral` / `influencer` / `pr` / `community` / `other` |
| detail | 何をしたか (簡潔に) |
| quantity | 投稿数・配布数・対象数など (あれば) |
| cost | 概算コスト (あれば、通貨明記) |
| area/target | エリア・セグメント (あれば) |
| notes | キャンペーンリンク/招待コードの有無・狙い・相関で見たい指標 |

## 台帳

| date | channel | detail | quantity | cost | area/target | notes |
|------|---------|--------|----------|------|-------------|-------|
| (まだ施策の記録はありません。`/campaign-log` で追記します) | | | | | | |
