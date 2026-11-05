# connect/（外部連携の Worker）エージェント指示

`api.gymnee.app` で動く Cloudflare Worker `gymnee-connect`（#171）。Gymnee をアプリの外の道具とつなぐ。
リポジトリ直下の `AGENTS.md` の共通規約にも従う。

## 何を受け持つか

| 道 | 中身 | 認証 |
|---|---|---|
| `/mcp` | MCP サーバー（Streamable HTTP・状態を持たない） | OAuth のアクセストークンか PAT |
| `/v1/*` | REST API | OAuth のアクセストークンか PAT |
| `/authorize` ほか `/.well-known/*`・`/oauth/*` | OAuth 2.1 の認可サーバー（`@cloudflare/workers-oauth-provider`） | 承認は iPhone の Gymnee で行う |
| `/app/*` | iOS アプリ向け（連携の一覧・API キー・承認・送り先） | アプリのサインイン（Supabase のアクセストークン） |
| `/slack/callback`・`/discord/callback` | 「追加」ボタンの戻り先 | 署名した state |
| `/line/webhook` | LINE の Webhook（コーチ・記録・連携コード） | `X-Line-Signature` |
| cron（毎分） | 送り先への配信・週のふりかえり・LINE の毎日の通知・掃除 | — |
| `/openapi.json` | API の仕様 | なし |

## 不変条件（崩さない）

- **外部に渡すトークンは、アプリのログインより狭くする。** 権限は `read` / `workouts:write` / `coach:write` の 3 つだけ（`src/domain/scopes.ts`）。Supabase の JWT を外に出さない。投稿・フォロー・削除・編集の操作を外部に足さない（同期が削除を伝えない作り。足すなら削除の伝え方から決め直す）
- **DB に触れるのは `src/db/repo.ts` だけ。** service role は RLS を素通りするので、どの関数も「認証で確かめた利用者 id」を最初の引数に取り、必ずその id で絞る。呼び出し側から来た値（本文の user_id など）で絞り先を変えない。入力の zod は `.strict()` にして余計な項目を受け付けない
- 外部からの書き込みは DB の関数（`connect_*`。`supabase/migrations/0046_connect.sql`）で 1 トランザクションにする。関数は `service_role` にだけ実行を許す（anon / authenticated から呼べない）
- **操作の定義は `src/api/operations.ts` の 1 か所。** REST・MCP の道具・OpenAPI（`docs/connect/api/openapi.json`）はそこから作る。操作を足したら `pnpm openapi` で書き出し直してコミットする（CI の `openapi:check` がずれを止める）
- 自己ベストの判定（`src/domain/pr.ts`）はアプリの `PRDetector` / `OneRepMax` / `WorkoutMetrics.bests` の写し。どちらかを変えたら両方を同時に直す。週ボスの名前（`src/domain/party.ts`）も `PartyBoss.catalog` と SQL の `party_boss_id` の写し
- ヘルスケア（HealthKit）から取り込んだ値（`body_metrics.from_health_kit = true`）は外へ出さない（プライバシーポリシーの約束）
- パーティの情報は合計と本人の分だけを外へ出す。ほかのメンバーの名前と回数は出さない
- 記録の追加は冪等にする。Idempotency-Key（MCP は `idempotencyKey`）があれば、利用者 id と鍵から UUID v5 で id を作る（`src/domain/ids.ts`）
- 種目は既存のもの（プリセットと本人の種目）にだけ合わせる。知らない名前で種目を作らない。決まらなければ候補を返す

## 送り先への配信（Slack / Discord / 汎用 Webhook。2 段目）

- 流れ: `workouts` の完了をトリガー（0047）が `connect_events` に積む → cron（毎分）が `connect_fanout_events` で送り先ごとの `connect_deliveries` に展開 → `connect_claim_deliveries` で取り出して送る（`src/jobs/deliver.ts`）
- 知らせは完了から 2 分待ってから送る。アプリは workouts → workout_exercises → exercise_sets の順に送るので、完了の瞬間にはセットがまだ無い。本文は送るときにその時点のデータで作る
- 積むのは完了時刻が直近 24 時間以内の記録だけ（ゲストからの初回サインインで過去分がまとめて上がっても知らせない）。完了済みの記録を直しても積み直さない。送り先の無い人の分は積まない
- 送り先の URL と署名の鍵は `ENCRYPTION_KEY` で暗号化して保存する。鍵を替えると読めなくなる（控えは `secrets/connect.env`）
- 名前・記録名はチャンネル全体の呼び出しに化けさせない（Slack は `& < >` を実体参照、Discord は `allowed_mentions: {parse: []}` と `@` の無害化。`src/domain/notices.ts`）
- URL の確かめ（`src/domain/destinationUrl.ts`）: https だけ・IP 直書き・内部名・443 以外・資格情報入りは断る。送るときも転送（3xx）に付いていかない
- 再試行は 1・5・30・120・360 分あけて 6 回まで（`src/domain/deliveryPolicy.ts`）。Slack の 403/404/410・Discord の 401/404・汎用の 410 は送り先が消されたとみなしてすぐ止める。続けて 5 回諦めた送り先も止める
- 汎用 Webhook は Standard Webhooks の署名を付ける。`webhook-id` は配信の id（再試行でも同じ）
- 週のふりかえりは月曜 8 時台（JST）に先週分を積む（何度呼んでも 1 回分）。記録の無かった週は送らない。パーティは合計と本人の分だけ
- 「追加」ボタン（Slack の `incoming-webhook`・Discord の `webhook.incoming`）は `src/integrations/chatOAuth.ts`。state に利用者 id と用途を署名して載せ、別の用途の state を通さない。戻り先は `gymnee://connect/done`（アプリは ASWebAuthenticationSession で受ける）
- ローカルで cron を呼ぶ: `wrangler dev --env local --test-scheduled` で起動し `curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=*+*+*+*+*"`（`pnpm e2e:local` がやる）

## LINE（3 段目）

- 連携は LINE ログインを使わない。アプリが 6 桁の連携コード（`line_link_codes`。10 分・1 回きり）を作り、`https://line.me/R/oaMessage/<basic id>/?連携 123456` を開く。利用者がそのまま送ると webhook が紐付ける（`line_links`。1 つの LINE は 1 アカウントだけ）。総当たりは LINE の利用者ごとに 1 時間 10 回で止める
- グループ・トークルームからのイベントには答えない（個人の記録を他人に見せない）。ブロック（unfollow）で紐付けを消す
- 返事はすべて Reply API（通数に数えない）。通数に数えるのは毎日の通知（Push）だけ
- 文で来たら AI（`src/domain/lineCoach.ts`。人格は coach-chat の写し。変えるときは両方直す）が「記録・メニュー・相談」を見分ける
  - 記録: すぐには書かない。`line_pending_logs` に置いて「記録する／やめる」を出し、押されたら書く（先に押された 1 回だけ。鍵も確認待ちの id）。種目が決まらなければ候補のボタン（`pick:`）を出す
  - メニュー: `coach_messages.proposal`（channel=line）にも書き、アプリで取り込めるようにする。「やった！記録する」（`doneplan:`）で記録の確認に進む
  - 相談: 会話は `coach_messages` に channel=line で残す（アプリのコーチと会話を共有する）
- AI の呼び出しは LINE から 1 人 1 日 30 回まで（`connect_take_ai_quota`）。アプリの CoachQuota は端末だけなのでサーバーでも数える
- 毎日の通知（`src/jobs/lineDaily.ts`）: その時刻（JST）の人を、今日まだの人だけ取り出す（取り出した時点で今日は送った扱い）。今日もう記録した人には送らない。「途切れそう」は最後の記録から 3 日目から 3 日分（アプリの `ReengagementReminder` と同じ）。1 人 1 日 1 通で、`X-Line-Retry-Key` で二重に送らない
- 通数の残りが上限の 1 割（少なくとも 10 通）を切ったら、途切れそうな人への通知だけ送る（`allowPush`）。止めたら `OPS_ALERT_WEBHOOK_URL` に知らせる（1 日 1 回）
- 公式アカウントの初期設定（Webhook の URL・リッチメニュー）は `scripts/line-setup.mjs`。画像は `scripts/make-richmenu-image.py` で作る。本番への反映なので、流すのは岡本さんの OK のあと

## OAuth の承認の流れ

ログインの代わりに「iPhone の Gymnee で承認」する（利用者の多くが Apple サインインで、Web のログインを用意できないため）。

1. `/authorize` が承認待ち（`connect_oauth_pairings`。10 分で切れる）を作り、2 桁の番号と、アプリを開く QR / ボタンを出す
2. アプリは `/app/oauth/pairings/:id` で中身を読み、番号を見比べてから承認・拒否する（先に決めた人が勝ち、上書きできない）
3. 承認画面のブラウザが数秒おきに状態を見て、自分でフォームを送り、トークンを出してクライアントへ戻す。フォームを送れるのは画面を開いたブラウザだけ（ライブラリの cookie で縛る）。承認待ちは 1 回使うと `consumed` になる

承認待ちを KV に置かない（場所の違う読み取りで最大 60 秒ずれ、ブラウザが承認に気づかない）。

## 開発と確認

```bash
pnpm install
pnpm typecheck && pnpm test          # 純粋関数と入口（偽の DB）
pnpm openapi                          # docs/connect/api/openapi.json を書き出す
# 通し確認（ローカル Supabase と wrangler dev を立ててから）
cp .dev.vars.example .dev.vars.local  # 値は supabase status --output-format json と openssl rand
pnpm exec wrangler dev --env local --port 8787 --ip 127.0.0.1 --test-scheduled
pnpm e2e:local                        # PAT・REST・MCP・送り先と配信・OAuth（DCR → 承認 → トークン）を 45 項目
# DB の関数の検証（ローカル Supabase に対して。begin/rollback で何も残さない）
psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f ../scripts/sqltest/connect_local_test.sql
psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f ../scripts/sqltest/connect_webhooks_local_test.sql
psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f ../scripts/sqltest/connect_line_local_test.sql
```

- `cloudflare:workers` は vitest（Node）に無いので、`test/stubs/` の代役を当てている
- Workers では `fetch` を別のオブジェクトのメソッドとして呼ぶと Illegal invocation になる。関数で包んで渡す（`src/db/postgrest.ts`）
- 承認画面の CSP に `form-action` を付けない（承認後のクライアントへのリダイレクトまで縛ってしまう）
- テストに `whsec_…` などの鍵の形の文字列を接頭辞つきで直書きしない。公開の例の鍵でも GitHub の秘密検出が実在の鍵（Stripe など）と取り違えてアラートを出す（2026-11-05 に実例。接頭辞は実行時に付ける）

## デプロイ（本番への反映は岡本さんの明示 OK のあと）

```bash
pnpm exec wrangler kv namespace create gymnee-connect-oauth  # 作成済み（2026-11-05）。id は wrangler.jsonc
pnpm exec wrangler secret put SUPABASE_SERVICE_ROLE_KEY   # ほかの秘密も同じ（wrangler.jsonc のコメント）
pnpm exec wrangler deploy                            # api.gymnee.app（カスタムドメイン）
```

- DB の migration（0046 以降）を Worker より先に本番へ適用する
- service role の鍵は `supabase projects api-keys --remote=<ref> --reveal --output-format json` で取る。`--reveal` 無しだと伏せ字が返り、そのまま登録すると Invalid API key で 500 になる
- 秘密の値は `secrets/connect.env`（gitignore 済み）と Supabase から。Git に入れない
