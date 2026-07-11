# アイデンティティ / 環境分離 設計メモ（恒久対策）

作成: 2026-07-10 / 更新: 2026-07-11

> **【2026-07-11 決定の更新・最重要】匿名認証（Phase 2）は撤去した。**
> 実装後の多エージェント・コードレビューで、匿名認証は (1) native Apple の id_token リンクが
> 全経路をクリーンにできない (2) 匿名セッション状態機械の失敗面（uid 分裂・PK 衝突による
> 42501 outbox 永久滞留・returning-user 削除失敗の孤児化）(3) authenticated ロールが匿名にも
> 開くサーバー攻撃面（Gemini 課金・progress_photos public・チェックイン push 漏洩・reports
> メール爆撃・avatars ファイルホスティング）を持ち込む一方、**漏洩の恒久対策そのものは
> `IdentityAdoptionPolicy`（ゲスト/恒久の区別ガード）が担っており匿名認証は不要**（複数端末の
> uid 統一も端末ごとに別匿名アカウントができ達成できていなかった）と判明。よって匿名認証を撤去し、
> **ガード一本化**（下記 Phase 0 相当）を恒久策とした。以下の Phase 2 記述は経緯として残すが不採用。
> あわせて**公開面は「feed_item が在る＝公開・作成は明示操作のみ」の fail-closed** に転換した（§公開面の設計）。

## 0. 目的

Gymnee はこれまで「環境をまたぐデータ混入」「別 uid の孤児データ」「プリセット重複」「削除が伝播しない」といった問題を、
発生のたびに個別対処してきた。これらは**場当たりで塞ぐ種類のバグではなく、2〜3個の土台の欠落から出る症状**である。
本メモは、症状ではなく根に手を入れるための現状分析・業界標準・移行設計を記録する。

きっかけ: 2026-07-10、App Store 版（Release→PROD）でログインするとソーシャル公開フィードに DEV 時代のデモ人格
「Taiga Aizawa」の6月の記録が表示された（詳細は memory `gymnee-prod-dev-data-leak`）。調査の結果、
App Store ビルドの接続先は正しく PROD だったが、**PROD DB に DEV 由来データが実在**していた。

## 1. 現状の設計（as-is）

### 1.1 アイデンティティ（所有者）

- ローカルは `MockAuthProvider` が userId を採番。
  - ゲスト（未サインイン / 手動 `signIn`）＝ランダム UUID を UserDefaults に保存。
  - ローカル Apple 経路＝Apple の userIdentifier から決定的 UUID。
- バックエンドサインイン成功時、`AuthService.establishBackendSession` が
  `provider.persistSession(userId: remote.userId, …)` で**ローカル uid を Supabase uid に上書き**する。
- サインイン成功フック `onBackendSignIn(oldUserId, newUserId)`（`AppEnvironment.swift`）が
  `LocalDataMigrator.reassign(from:old, to:new)` を呼び、**「直前セッションが所有するローカルデータ全部」を
  新 uid に付け替えて outbox で再送出**する。`oldUserId = session?.userId`。
- `reassign` は record の UUID / createdAt を保持し、updatedAt のみ `.now`。

### 1.2 環境分離

- XcodeGen の config で分離済み: Debug→dev / Release→prod、bundle id `com.gymnee.app(.dev)`、App Group も分離。
- 接続先は `Config/Secrets.{dev,prod}.xcconfig`（`SUPABASE_HOST` / `SUPABASE_KEY`）→ Info.plist →
  `SupabaseConfig.load()`。
- **強制する仕組みは無い**（規約のみ）。Release ビルドを dev host に向けても起動時に検知・遮断されない。

### 1.3 今回の混入メカニズム

1. どこかの時点で本番 bundle（`com.gymnee.app`）のビルドが DEV バックエンドに接続し、
   デモ人格 Taiga（dev uid `92487649`）のデータをローカルストアに保持した
   （dev アプリ `.dev` とは別コンテナ。デモ生成は DEBUG ハーネス由来）。
2. その端末で PROD アプリに Apple サインイン（新 prod uid `b6130f13`）。
3. `oldUserId = 92487649` として `reassign` が全ローカルデータを `b6130f13` に付け替え、PROD へ push。
   - createdAt=6月のまま / updatedAt=当日 / photoRef に dev uid `92487649` が残存、が指紋。
4. `feed_items_select` RLS は `visibility='public'` を全 authenticated に開放するため、
   新規ユーザー全員のフィードに Taiga の投稿が出た。

## 2. 何が問題か（共通の根）

| 症状（過去インシデント） | これまでの対処 | 本当の根 |
| --- | --- | --- |
| 複数サインイン方法で別 uid→孤児 / 同期 RLS 42501 | 手動統合手順 | アイデンティティ土台の不在 |
| dev→prod データ混入（本件） | 手動削除＋reassign ガード | アイデンティティ土台＋環境不変条件 |
| プリセット種目が同名別 id 膨張 | 決定的 UUIDv5＋cleanup migration | マスタデータ土台（per-user push） |
| 差分 pull で削除が伝播しない（tombstone 無） | 一部テーブルだけフル再取得 | 同期土台（削除表現） |

**核心**: ユーザーの所有者 uid を「自前の後付け付け替え（`reassign`）」で確定している。
`reassign` はプラットフォーム標準では「既存の別アカウントへ**マージする例外操作**」に相当するが、
Gymnee はこれを**毎サインインの通常経路**に使っている。だから脆く、環境や別アカウントのデータまで巻き込む。

## 3. 業界標準（一次情報）

Supabase も Firebase も、ゲスト→本登録を自前付け替えでは解かない。共通設計:

1. 最初から全ユーザーに安定 uid を与える（**匿名認証** anonymous sign-in / `signInAnonymously()`）。
2. データは uid に紐づけて保存する。
3. サインイン＝**クレデンシャルを既存 uid にリンク**する（Supabase `linkIdentity()` / `updateUser()`、
   Firebase `linkWithCredential()`）。**uid は変わらない**ので、付け替え不要で本人のデータになる。

- Firebase: 「The UID will remain the same … all data the user has already created … is still accessible」。
  データは**安定 UID に対して保存せよ**と明記。
- Supabase: 匿名→本登録で **user id は不変**。RLS は JWT の `is_anonymous` クレームで匿名/本登録を区別可能。
- 「user_id を別 uid に付け替える（reassign）」は**既存アカウントへマージする場合だけ**の手段として紹介。

環境分離: iOS 標準（Config/Scheme/xcconfig を環境ごとに分け、bundle id・鍵・アプリ名を分離）は
**Gymnee は既にほぼ実践済み**。欠けているのは「規約」ではなく「**不変条件**」としての強制と、
デモデータを prod 到達経路に置かない運用。

出典:
- Supabase Anonymous Sign-Ins: https://supabase.com/docs/guides/auth/auth-anonymous
- Supabase blog (Anonymous Sign-ins): https://supabase.com/blog/anonymous-sign-ins
- Firebase Best Practices for Anonymous Authentication: https://firebase.blog/posts/2023/07/best-practices-for-anonymous-authentication/
- iOS environments: https://sarunw.com/posts/how-to-set-up-ios-environments/ , https://thoughtbot.com/blog/let-s-setup-your-ios-environments

## 4. offline-first の折衷方針

匿名認証は初回起動オンラインを前提とするが、Gymnee はオフラインでも記録を作れるため、その瞬間に
サーバー uid を発行できない。よって offline-first 版の**不変条件**をこう定める:

> **reassign（付け替え）は「ゲスト→最初の本人アイデンティティ確定」の 1 回だけに封じ込める。**
> 一度でもバックエンド認証（または匿名認証）されたローカルデータは、別のアイデンティティが吸い上げない。
> 別アカウント切替・環境切替・2 回目以降のサインインでは絶対に付け替えない。

## 5. 目標アーキテクチャ（to-be）

- **F1 アイデンティティの一本化**: 匿名認証で安定 uid を持ち、サインイン＝`linkIdentity()`（uid 不変）。
  付け替えは「ゲスト→初回確定」の 1 回だけ。以後は付け替えゼロ。
- **F2 環境の不変条件化**: `GYMNEE_ENV` を xcconfig に持たせ、bundle サフィックスと接続先の整合を起動時に強制。
  ズレたらリモート同期を無効化。デモ/シード人格は DEBUG 専用パスに隔離。
- **F3 マスタ/同期の土台**: プリセット種目は `created_by IS NULL` のマスタ扱いで per-user push を止める。
  削除は tombstone/ソフトデリートで全テーブルに伝播（offline-first では本質的に難しく、専用機構が要る領域）。

## 6. 移行設計（段階）

### Phase 0 — 即時ガード（小・低リスク / F1 の頭金）

`reassign` を「所有者が一度もバックエンド/匿名認証されていない（＝真のゲスト由来）データ」に限定する。

- **耐久性のある由来マーカーを持つ**。`isBackendAuthenticated`（メモリ）や `hasPersistedBackendSession`
  （Keychain refresh token）は **signOut で消える**ため、`signOut → 別アカウントsignin` の切替で
  由来判定が漏れる（穴が残る）。よって **UserDefaults 等に耐久フラグ**
  `gymnee.localData.boundToBackendAccount`（初回バックエンド確定時に true、`deleteAccount` /
  明示的ローカルデータ全消去でのみ false）を持つ。
- サインイン各経路（`completeSignInWithApple` / `verifyEmailCode` / `signInWithGoogle` と
  ローカル Apple フォールバック）で、`establishBackendSession` へ渡す old を次のように決める:
  ```
  let adoptGuestData = !boundToBackendAccount        // 由来がゲストの時だけ付け替える
  let oldUserId = adoptGuestData ? session?.userId : nil
  … establishBackendSession(remote, …, oldUserId: oldUserId)
  // 初回バックエンド確定時に boundToBackendAccount=true を永続化
  ```
- 効果: 別アカウント/別環境のローカルデータが新規サインインに吸い上げられる経路を塞ぐ。
  ゲスト→初回サインインの正規引き継ぎ・同一ユーザー再認証（old==new）・セッション復元（old=nil）は従来どおり。

### Phase 1 — 環境の不変条件化（F2）【実装済み・2026-07-12・feature/environment-invariant】

- **実装した方式（GYMNEE_ENV は使わず、より直接的に）**: `EnvironmentGuard`（Core/Domain）に
  本番の正規ホスト定数 `prodHost` を持ち、`SupabaseConfig.load` で
  `allowsRemote(bundleIdentifier:host:)` を判定。破っていたら nil を返し**リモート同期を無効化**
  （ローカルのみで動作）。Debug 構成では `assertionFailure` で loud に、Release は no-op で安全側に倒す。
  - bundle id サフィックス（`.dev` 有無＝コンパイル時に焼き込まれ実行時偽装不可）でビルド種別を判定。
  - **Release（無印 bundle）は prodHost にのみ接続可**（別ホストなら nil＝ローカル化）。
  - **Debug（`.dev` bundle）は prodHost へ接続不可**（dev 検証・デモが prod を汚さない）。
  - GYMNEE_ENV 方式は「prod 用ファイルに dev host を貼った」実際の failure を捕まえられないため不採用。
    正規ホスト定数との突合が実インシデントを直接遮断する。prod 移行時は定数を更新（漏れても安全側）。
- デモ/シード生成（`DemoData` / `-gymneeDemo` ハーネス）は `#if DEBUG` で Release バイナリから
  完全除外済み（確認済み）。上記ガード（Debug が prod に繋がらない）と合わせ「デモが本番到達」は二重に遮断。
- テスト: `EnvironmentGuardTests`（Release⇒prodのみ / Debug⇒prod拒否 / ホスト正規化）。

### Phase 2 — 匿名認証 + linkIdentity（F1 本体）

- Supabase プロジェクトで anonymous sign-in を有効化（`setup_supabase_prod.sh` の auth 設定に追加）。
- 起動フロー:
  - オンライン & 未サインイン → `signInAnonymously()` で uid A（`is_anonymous=true`）を取得。
    それ以前にオフラインで作ったゲストデータがあれば **1 回だけ** A に付け替え（Phase 0 の正規経路）。
  - オフライン起動 → ローカルゲスト uid のまま。初回接続時に上記を実施。
  - 「Apple / Google / メールでサインイン」→ `linkIdentity()` / `updateUser()` で **同一 uid A に本人性を付与**
    （`is_anonymous=false` 化）。**付け替え・再 push は一切不要**。
  - `linkIdentity` が「別ユーザーに既にリンク済み（他端末で先にサインイン）」を返す場合＝**マージ例外**。
    ここだけ明示的なコンフリクト解決（ローカル優先/リモート優先を選ぶ）で `reassign`/merge を許可する。
- RLS に `is_anonymous` ゲートを追加:
  - 公開系（`feed_items` の `visibility='public'` insert、`follows`、`comments`）を
    `NOT (auth.jwt()->>'is_anonymous')::boolean` に限定 → **匿名/ゲストの内容は公開フィードに出せない**
    （デモ/ゲストデータの露出を構造的に防ぐ二重の安全網）。
  - `handle_new_user()` は匿名ユーザーにも profile を作るため、匿名の表示名の扱い（「ゲスト」）と
    stale 匿名アカウントの定期削除（>30日・未リンク）を運用に加える。
- 効果: **初回アイデンティティ確定後は reassign が二度と走らない**。`LocalDataMigrator` の用途は
  「ゲスト→初回確定」と「明示マージ例外」だけに縮小。多重 ID 孤児（`gymnee-multi-identity-orphans`）も解消。

### Phase 2 実装確定事項（2026-07-11 検証済み）

GoTrue の REST 仕様を dev プロジェクトへの実リクエストと supabase/auth ソースで確認した。
Gymnee は自前 REST クライアント（`SupabaseClient`）のため、Swift SDK 未実装
（supabase-swift #588: `linkIdentityWithIdToken` 未提供）の制約を受けない。

- **匿名サインアップ**: `POST /auth/v1/signup`・body `{}`（apikey のみ）→
  `access_token` / `refresh_token` / `user.is_anonymous=true`（JWT claim にも `is_anonymous`）。
  要 `external_anonymous_users_enabled: true`（Management API `PATCH /config/auth`。dev 適用済み）。
  IP あたり 30 件/時のレート制限（`rate_limit_anonymous_users`）。
- **Apple ネイティブリンク**: `POST /auth/v1/token?grant_type=id_token`・
  body `{provider:"apple", id_token, nonce, link_identity: true}`・**Authorization: Bearer =
  現在の匿名セッション**。GoTrue の `IdTokenGrantParams.LinkIdentity` がサーバー実装済みで、
  成功時は同一 uid のまま `is_anonymous=false` に遷移する（`linkIdentityToUser`）。
  要 `security_manual_linking_enabled: true`（dev 適用済み）。
- **Google リンク（PKCE web）**: `GET /auth/v1/user/identities/authorize?provider=google&
  redirect_to=…&code_challenge=…&code_challenge_method=s256&skip_http_redirect=true`・
  Bearer 付き → `{url}` が返る（実測で accounts.google.com の URL を確認）。
  それを `ASWebAuthenticationSession` で開き、callback の code を既存
  `exchangeCodeForSession`（`grant_type=pkce`）で交換すると同一 uid のセッションが返る。
- **メールリンク**: `PUT /auth/v1/user`・body `{email}`（Bearer 付き）で email_change OTP を送信し、
  `POST /auth/v1/verify`・`{type:"email_change", email, token}` で確定（uid 不変）。
  email_change メールテンプレート（`mailer_templates_email_change_content`）に
  `{{ .Token }}` 入りテンプレの設定が必要（magic_link と同様）。
- **エラーコード**: 対象 identity が既に（同一/別）ユーザーへリンク済み → **422
  `identity_already_exists`**。メールが既存ユーザーのもの → `email_exists`。

**returning-user 切替（マージ例外）の手順**（既存アカウント保持者が新端末/再インストールで
匿名期間を経てからサインインするケース）:

1. リンク試行 → `identity_already_exists` / `email_exists` で失敗。
2. **通常サインインを先に完了**して既存アカウント B のセッションを取得
   （この時点ではクライアントの保持トークンはまだ匿名 X のまま）。
3. X の Bearer で `delete_account` RPC を実行（best-effort）。X のサーバー行が CASCADE で消え、
   ローカル行（record UUID が X のサーバー行と同一）を B として再 push しても PK/RLS 衝突しない。
4. B のセッションを確立し、削除が成功した場合のみ X→B の付け替え（採用）を実行。
   削除に失敗した場合は採用しない（outbox 詰まり防止。行はローカルに残るが非表示）。

匿名 X はこの端末しかトークンを持たず、匿名は公開投稿・フォロー・コメント不可（RLS ゲート）
のため他者の反応が X の行にぶら下がることはなく、削除で失われるものはローカルに全部ある。

**前提修正（Phase 3 の一部を前倒し）**: プリセット種目はサーバー側マスタ
（`created_by IS NULL`・決定的 UUIDv5 id）に一本化し、クライアントの起動時 backfill を
`is_custom=true` のみに限定する。現状は「最初のユーザーがプリセット 43 件を自分所有で push →
2 人目以降の同 id upsert が RLS(42501) で拒否 → **outbox 永久滞留**」という既存バグがあり
（prod 実データで確認: プリセット id は `uuid_generate_v5` 一致・ゲスト所有）、
匿名セッション導入で「全ゲスト起動」が同経路を踏むため、Phase 2 より先に必須。

### 公開面の fail-closed 設計（2026-07-11 追加・ユーザー指摘起点）

Phase 2 実装後も、公開面は「同期は全部して、悪いものが出ないよう個別に堰き止める」
ブロックリスト型（fail-open）だった。ゲスト期間の記録も feed_item 化され、サインアップ時に
過去記録が既定 visibility（public）で一括発行される＝「投稿するつもりの無かった過去の記録が
ネットに上がる」挙動が 1.0 から存在していた。これをアローリスト型（fail-closed）に反転する:

> **公開されるのは「恒久アカウントが、サインアップ後に作った記録」だけ。
> それ以前のものはすべて明示的に非公開。**

- **非恒久（ゲスト/匿名）は feed_item を一切作らない**（`FeedPublisher.publishOwnPosts` の
  guard）。同期されるのは RLS で本人のみの記録データだけになる。
- **恒久化の遷移時**（リンクによる本登録化・ゲスト/匿名データの採用を伴うサインイン）に、
  その時点で存在する本人の記録を `PostVisibilityStore` で明示 **private** にマークする
  （`FeedPublisher.markGuestRecordsPrivate`・`AuthService.onBecamePermanent` フック）。
  過去記録は「非公開の自分の記録」のまま残り、投稿メニュー（公開範囲）から個別に公開できる。
  同一恒久アカウントの再認証・別端末での既存アカウントサインインでは発火しない。
- **既存投稿の visibility は「明示選択 > 現状維持 > 既定」で解決**（`FeedVisibilityPolicy`）。
  明示選択は端末ローカル保存のため、既定値で解決すると別端末の再発行で private が public に
  巻き戻る（既存バグ・本変更で修正）。`PostVisibilityStore` はインスタンス内キャッシュを廃止し
  UserDefaults を読み書きの正とする（画面の @State と一括マークのインスタンス間不整合の防止）。
- これにより防御は「IdentityAdoptionPolicy → RLS(0031) → 公開面の設計」の三層になり、
  仮に identity 層で回帰が起きても被害は本人の非公開領域に閉じる。
  匿名 public の RLS ゲート・FeedPublisher の friends キャップ（撤去済み）が担っていた役割は
  guard に置き換わり、RLS はサーバー側の防御として残す。

**その他の実装決定**:
- サインアウトはローカル識別（userId）を破棄して次回ゲストを新規 uid にする
  （旧アカウント uid のローカルデータが次のサインインで別アカウントに吸われる残穴を塞ぐ）。
- 匿名セッションの生成タイミングは「起動時のセッション復元後」と「ゲスト開始（オンボーディング
  完了）直後」。オフラインなら次回起動で再試行。
- UI の「サインイン済み」判定は `isPermanentAccount`（backend 認証済み かつ 非匿名）に統一。
  匿名はゲスト扱い（ソーシャル/AI はサインイン促し）。
- オンボーディングの「記録は端末に保存」文言は、匿名自動同期後は不正確になるため
  「クラウドに自動バックアップ」へ更新する。**プライバシーポリシーの記述も要確認**
  （ゲスト記録がサインイン前にサーバー保存される旨）。

### Phase 3 — マスタ/同期の土台（F3・余力に応じて）

- プリセット種目は `is_custom=false` を per-user push しない。サーバー側 `created_by IS NULL` マスタとして
  一度だけ投入し、`backfillExercisesIfNeeded` は `is_custom=true` のみ対象にする
  （現状はサインインごとに 40 数件のプリセットが prod に増える）。
- 削除の tombstone 化（`gymnee-sync-delete-propagation` の恒久化）。

## 7. 各インシデントの写像（どの Phase が閉じるか）

- dev→prod 混入（本件）: Phase 0（ガード）＋ Phase 1（環境不変条件）＝二重で遮断。
- 多重 ID 孤児 / 42501: Phase 2（linkIdentity で uid 不変）。
- プリセット膨張: Phase 3。
- 削除非伝播: Phase 3。

## 8. リスク・テスト観点

- サインイン中核（`AuthService` / `AppEnvironment.onBackendSignIn` / `LocalDataMigrator`）を触るため、
  変更は**別ブランチ・別コミット**、`xcodebuild build` / `test` を各段で通す。
- 回帰テスト観点:
  - ゲスト→初回サインインで記録が正しく引き継がれる（付け替え 1 回）。
  - サインイン済み A → サインアウト → 別アカウント B サインインで、**A のデータが B に付かない**。
  - 同一ユーザー再認証（トークン失効復帰）でデータ重複・欠落なし。
  - Release ビルドが dev host に繋がると同期が無効化される（Phase 1）。
  - 匿名ユーザーは public feed_items を作成できない（Phase 2, RLS）。

## 9. 未決事項

- ~~F1 の実装方式: 段階的か一気か~~ → ~~決定（2026-07-10）: 一気に Phase 2（匿名認証）へ移行~~
  → **再決定（2026-07-11）: 匿名認証は撤去。ガード（IdentityAdoptionPolicy）一本化を恒久策とする**
  （理由は冒頭の注記）。実装: `AuthService` は匿名/link/email_change/cleanUp を持たず、サインインは
  Apple(id_token)/Google(PKCE)/メール(OTP) の素直な形。付け替えは「ゲスト→初回サインインのみ・
  恒久アカウント切替は不可」を `IdentityAdoptionPolicy` が保証。`LocalDataMigrator` の子行再送出は
  親所有者が新 uid の行のみ。公開面は fail-closed（§参照）。prod は匿名認証 OFF（2026-07-11 確認）。
  migration 0031（匿名 RLS）は適用済みだが匿名ユーザーが存在しないため無作用（多重防御として残置）。
- 匿名認証採用時の abuse 対策: IP 30件/時のデフォルトレート制限で開始。CAPTCHA/Turnstile は必要になったら。
  stale 匿名（>30日・identity 未リンク）の定期削除は運用 SQL（将来 pg_cron 化を検討）。
- 既存 prod ユーザー（現状は実質ゼロ＝クリーン移行しやすい）への影響評価。
- リリース時の prod 作業: migration（プリセットマスタ化・匿名 RLS ゲート）適用と
  auth config PATCH（anonymous / manual linking / email_change テンプレート）。
