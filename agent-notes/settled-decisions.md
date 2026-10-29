# 撤去・不採用にしたものと、意図的に残しているもの

コーディングエージェント向けの補足（`AGENTS.md` の「決定済みの事項」から参照）。
撤去・不採用を再提案する前、残置物やデッドコードを消す前に読む。

## 撤去・不採用

- チェックイン / ジム: 撤去済み。活動の単位は完了したワークアウトだけで、活動日は `Workout.completedAt`。位置情報も使わない
- カスタムセット（Routine）: 撤去済み。「今日の計画」は記録画面のカテゴリタブ先頭のチップで、計画の種目は `PlannedWorkout.detailJSON` だけが持つ
- サブスク（Premium）: 撤去済みで、`SubscriptionService` / `PaywallView` もソースごと消した。再導入するなら IAP 商品を作り、審査用スクショを付けて新バイナリと同時に審査へ出す（導線だけ戻すとガイドライン 2.1(b) で却下される）。審査メモの「アプリ内課金なし」も直す。`StoreService` はペットなど単発 IAP 用で別物
- 記録画面の左カテゴリレール: 不採用。横のタブバー＋2 列が正（`docs/record-redesign-spec.md`）。ルーラーの上で部位の横スワイプが効かない制約は受け入れ済み
- 匿名認証: 撤去済み（`AGENTS.md` の「アイデンティティと環境の不変条件」）

## 意図的に残しているもの

- 本番 DB の visits / visit_partners / gyms / gym_equipment / routines / routine_exercises と visit-photos バケットは drop していない。消す migration は人の明示確認を取ってから。type='visit' の feed_items はクライアントが取り込み時に捨てる
- `Subscription` モデルと `WorkoutExercise.restSeconds`: 未使用だが、消すにはスキーマの版上げが要り、データ消失のリスクに見合わない
- `AuthProviding` + `MockAuthProvider`: 名前に反して本番のローカル ID 永続化そのもの。畳み込み・改名は認証まわりなので単独 PR で
- `CharacterScene.depthScale` は定数 0.80 を返す / `Localizable.xcstrings` は実効の翻訳ゼロ / `scripts/analytics/pull-supabase.mjs` の visits・subscriptions 指標は固定値（指標を変えるときは人に確認する）

## デッドコードの洗い出し

- Swift は未使用の private も警告しないので、whole-word の参照数が 1 の識別子を機械的に拾う（protocol 準拠と CaseIterable は除外）
- 拾ったものが上の「意図的に残しているもの」に当たらないか確かめてから消す
