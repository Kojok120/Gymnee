# グロース KPI ツリー / ベースライン (Gymnee)

`growth-analyst` が診断に使う**唯一の物差し**。獲得ファネルの定義・現状ベースライン・暫定目標を置く。
数字は `analytics/snapshots/*.json` の実フィールドに紐づく。四半期に一度など、実態に合わせて見直す。

Gymnee は筋トレ記録アプリ (オフラインファースト / SwiftData がローカルの正、Supabase に同期・認証・課金・ソーシャルを集約)。
**配信直後で N が 1 桁**。率より実数を追う段階。

## North Star Metric (今の段階)

**週あたり「習慣化した記録ユーザー数」** = 直近 7 日で 3 回以上ワークアウトを記録したユーザー数 (`supabase.retention.habitWeek3plus`)。
筋トレアプリの価値は「続けて記録する」ことにあるため、登録・初回記録だけでなく **週3記録の習慣**が North Star。
その手前の律速は **活性化 (初回ワークアウト記録)** = 登録して実際に 1 回でも記録した人数 (`supabase.activation.activatedWorkout`)。
健全性ガードレールは **D7 継続** (`supabase.retention.d7Retained`) — 記録しても 1 週間後に戻らなければ意味がない。

## ファネル定義とベースライン

計測: 直近 30 日コホート / 2026-07-23 スナップショット時点。**コホート N=7 と小さく、率は参考値** (1 人で約 14% 動く)。実数で読む。

| 段 | フィールド | 現状 (2026-07-23) | 暫定目標 | メモ |
|---|---|---|---|---|
| DL (新規) | `appstore.downloads.totals.firstDownloads` | 6 (直近30日) | ASO/告知で母数増 | 更新 9 / 再DL 0。ASC 共有キーで自動取得済み |
| 登録 (signup) | `supabase.registration.inWindow` (累計 `registration.totalUsers`) | 7 (累計 7) | 施策で母数を増やす | DL 6 ≒ 登録 7 (知人招待含む)。取りこぼしは小 |
| 活性化 (初回ワークアウト) | `supabase.activation.activatedWorkout` / `cohortSize` | 3/7 (43%) | 5/7+ | 初回記録到達。**現状の主要ボトルネック候補**。何らかの活動込みは `activatedAny` 4/7 |
| 習慣化 (週3記録) | `supabase.retention.habitWeek3plus` | 3 | 5+ | 直近7日で workouts>=3。**North Star** |
| D7 継続 | `supabase.retention.d7Retained` / `d7EligibleCohort` | 3/7 (43%) | 4/7+ | 登録7日後以降の再活動。**最重要の健全性**。翌日以降の再来は `returnedAfterDay0` 3/7 |
| DAU/WAU/MAU | `supabase.activity.dau/wau/mau` | 3 / 3 / 4 | WAU 右肩上がり | workouts∪visits の distinct user。テスト/知人混入込みの上限 |
| ソーシャル | `supabase.social.followsTotal` / `distinctFollowers` / `feedItemsInWindow` | 9 / 4 / 35 | 招待で follow 増 | reactions 9 / comments 0。フィード投稿は活発 (pr9/visit9/workout17) |
| 課金 (有効サブスク) | `supabase.monetization.paidActive` (ASC は `appstore.subscriptions.latest`) | 0 (ASC 0) | 最初の 1 人 | tier=pro/elite かつ active。まず活性化・習慣化を積んでから |

補助指標 (機能利用の深さ、テスト混入込みの全体活動):

| 指標 | フィールド | 現状 (2026-07-23) | メモ |
|---|---|---|---|
| 期間内ワークアウト数 | `supabase.engagement.workoutsInWindow` | 19 | 1 人あたりで割って偏りを見る |
| 期間内セット数 | `supabase.engagement.exerciseSetsInWindow` | 234 | 少数ヘビー利用で跳ねる。新規体験の代表値ではない |
| 期間内来店 | `supabase.engagement.visitsInWindow` | 9 | チェックイン利用 |
| PR 達成 | `supabase.features.personalRecordsInWindow` | 28 | 自己ベスト更新の頻度 |
| プッシュ到達母数 | `supabase.features.pushReachableUsers` | 3 | device_tokens 登録者。通知施策の母数 |
| 身体記録 / 写真 / サプリ | `body/progress/supplyLogsInWindow` | 0 / 0 / 0 | 未利用。導線を要検討 (収益導線=supply) |

## 全体活動数字の扱い(誤読注意)

`supabase.engagement` / `activity` / `social` / `features` は**全ユーザー**の活動で、オーナー自身・招待した知人・テストアカウントが混ざる。
2026-07-23 時点: 期間内 exercise_sets 234 / activeUsersInWindow 4 人 = **1 人あたり約 58 件**。
これは少数のヘビー利用が押し上げた値で、**新規ユーザー体験の代表値ではない**。
アプリの利用の厚み・難易度を語る時は、コホート (新規登録者) の数字か、テストアカウントを除外した分析を使う。

**オフラインファーストの補正**: 記録はローカル (SwiftData) に残り同期が後追いのことがある。
Supabase の件数は「同期済みの下限」であり、実利用はこれ以上の可能性がある (過小評価方向の誤差)。

## 目標の考え方

- 小 N のうちは**率より実数の増加**を追う (活性化 3→5 人、週3記録 3→5 人、のように)。
- North Star (週3記録ユーザー数) を右肩上がりに保ちつつ、D7 継続が崩れていないかをセットで見る。
- 活性化・習慣化が薄いうちは課金より上流 (登録→初回記録→習慣化) を優先する。
- ここの目標値は暫定。N が 50-100 を超えたら業界水準と突き合わせて更新する。
