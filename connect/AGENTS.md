# connect/（外部連携の Worker）エージェント指示

`api.gymnee.app` で動く Cloudflare Worker `gymnee-connect`（#171）。Gymnee をアプリの外の道具とつなぐ。
リポジトリ直下の `AGENTS.md` の共通規約にも従う。

## 何を受け持つか

| 道 | 中身 | 認証 |
|---|---|---|
| `/mcp` | MCP サーバー（Streamable HTTP・状態を持たない） | OAuth のアクセストークンか PAT |
| `/v1/*` | REST API | OAuth のアクセストークンか PAT |
| `/authorize` ほか `/.well-known/*`・`/oauth/*` | OAuth 2.1 の認可サーバー（`@cloudflare/workers-oauth-provider`） | 承認は iPhone の Gymnee で行う |
| `/app/*` | iOS アプリ向け（連携の一覧・API キー・承認） | アプリのサインイン（Supabase のアクセストークン） |
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
pnpm exec wrangler dev --env local --port 8787 --ip 127.0.0.1
pnpm e2e:local                        # PAT・REST・MCP・OAuth（DCR → 承認 → トークン）を 36 項目
# DB の関数の検証（ローカル Supabase に対して。begin/rollback で何も残さない）
psql postgresql://postgres:postgres@127.0.0.1:54422/postgres -v ON_ERROR_STOP=1 -f ../scripts/sqltest/connect_local_test.sql
```

- `cloudflare:workers` は vitest（Node）に無いので、`test/stubs/` の代役を当てている
- Workers では `fetch` を別のオブジェクトのメソッドとして呼ぶと Illegal invocation になる。関数で包んで渡す（`src/db/postgrest.ts`）
- 承認画面の CSP に `form-action` を付けない（承認後のクライアントへのリダイレクトまで縛ってしまう）

## デプロイ（本番への反映は岡本さんの明示 OK のあと）

```bash
pnpm exec wrangler kv namespace create OAUTH_KV      # 初回だけ。id を wrangler.jsonc に書く
pnpm exec wrangler secret put SUPABASE_SERVICE_ROLE_KEY   # ほかの秘密も同じ（wrangler.jsonc のコメント）
pnpm exec wrangler deploy                            # api.gymnee.app（カスタムドメイン）
```

- DB の migration（0046 以降）を Worker より先に本番へ適用する
- 秘密の値は `secrets/connect.env`（gitignore 済み）と Supabase から。Git に入れない
