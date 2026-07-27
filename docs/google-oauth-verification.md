# Google OAuth 確認審査（Google カレンダー連携の本番化）

Google カレンダー連携で出る「このアプリは Google で確認されていません」を消すための手順書。

## 結論（先に読む）

- 警告の原因は **`calendar.events` が sensitive scope** であること。OAuth 同意画面を「テスト」から「本番」に切り替えるだけでは**警告は消えない**
- 消すには **Google の確認審査（sensitive scope verification）を通す**必要がある。公称の審査期間は最大 10 日
- 未確認のまま本番公開した場合の制限は以下の 2 つ
  - 警告画面が全ユーザーに表示される（「詳細」→「Gymnee（安全ではないページ）に移動」で続行はできる）
  - **累計 100 ユーザー**までしか認可できない（超えると連携不可）
- テスト状態のままだと、テストユーザー以外は連携そのものがブロックされ、リフレッシュトークンも 7 日で失効する

## 対象

| 項目 | 値 |
| --- | --- |
| GCP プロジェクト | `gen-lang-client-0041171849`（Gymnee / project number 447522057780） |
| オーナー | kojokamo120@gmail.com |
| 要求スコープ | `https://www.googleapis.com/auth/calendar.events`（sensitive） |
| ホームページ | https://gymnee.app/ |
| プライバシーポリシー | https://gymnee.app/privacy-policy.html |
| 利用規約 | https://gymnee.app/terms-of-service.html |
| 実装 | `Gymnee/Core/Services/GoogleCalendarService.swift`（GoogleSignIn SDK + Calendar REST） |

## 事前チェック（申請前に潰す）

- [ ] プライバシーポリシーに Google ユーザーデータの取扱いが明記されている → **対応済み**（第 4 章）
- [ ] ホームページでカレンダー連携機能を説明している → **対応済み**（AI 週次計画セクション）
- [ ] Search Console で `gymnee.app` のドメイン所有権を確認済み
- [ ] OAuth 同意画面のアプリ名・サポートメール・ロゴ・ホームページ / ポリシー URL が設定済み
- [ ] **承認済みドメインに自分が所有していないドメインが入っていないか**（後述のリスク参照）
- [ ] デモ動画（YouTube・限定公開）を用意

### リスク: 承認済みドメインに `supabase.co` が入っている場合

Supabase の Google サインイン（Web OAuth クライアント）を使っているため、リダイレクト先が
`https://<ref>.supabase.co/auth/v1/callback` になっている。同意画面の「承認済みドメイン」に
`supabase.co` を登録していると、**所有権を証明できないドメイン**として差し戻される可能性がある。

根本解決は、Google サインインを Web リダイレクト方式から **ネイティブ方式**（GoogleSignIn SDK で
取得した ID トークンを Supabase の `signInWithIdToken` に渡す）へ寄せて、Web OAuth クライアントと
`supabase.co` へのリダイレクトを使わないこと。申請前に同意画面の承認済みドメインを確認し、
`supabase.co` が入っていたら別 Issue で対応する。

## 手順

### 1. Search Console でドメイン所有権を確認（ブラウザ操作）

1. https://search.google.com/search-console で `gymnee.app` を **ドメインプロパティ**として追加
2. 表示された TXT レコードの値を控える（DNS は Cloudflare。TXT の追加はこちら側で API から実行可能）
3. TXT 反映後に「確認」を押す

### 2. OAuth 同意画面の設定（ブラウザ操作）

Google Cloud Console → 該当プロジェクト → **Google Auth Platform**（旧 OAuth 同意画面）

- アプリ名: `Gymnee`
- ユーザーサポートメール / デベロッパー連絡先: kojokamo120@gmail.com
- アプリのロゴ: App Store と同じアイコン（120×120 以上の PNG）
- アプリのホームページ: `https://gymnee.app/`
- プライバシーポリシー: `https://gymnee.app/privacy-policy.html`
- 利用規約: `https://gymnee.app/terms-of-service.html`
- 承認済みドメイン: `gymnee.app`
- データアクセス（スコープ）: `https://www.googleapis.com/auth/calendar.events` が登録されていること
- 対象: 外部 / 公開ステータス: **本番環境**

### 3. 確認審査を申請（ブラウザ操作）

「確認センター」から申請。入力する内容は以下をそのまま使う。

**スコープの正当化（英語・そのまま貼れる）**

> Gymnee is an iOS workout-logging app. Its weekly planner overlays the user's existing calendar
> events on the workout schedule so the user can plan training on days they are actually free, and
> it writes the confirmed plan back to the user's calendar as all-day events titled
> "Gymnee: <plan name>".
>
> We request https://www.googleapis.com/auth/calendar.events because this feature needs both
> capabilities: reading existing events (to avoid scheduling training on busy days) and creating
> events (to put the confirmed workout plan on the user's calendar).
>
> Narrower scopes are not sufficient. calendar.events.readonly cannot create the plan events.
> calendar.app.created only grants access to a secondary calendar created by our app, which cannot
> read the user's existing events that the planner must avoid. We do not read or modify calendar
> metadata, sharing settings, or ACLs, so we do not request the broader
> https://www.googleapis.com/auth/calendar scope.
>
> Calendar data is never stored on our servers. Events are held in memory on the device for display
> only. When the user explicitly asks the in-app assistant to generate a weekly plan, the event
> title, date, and all-day flag for the target week are sent to our stateless backend function and
> then to the Gemini API solely to produce that plan; nothing is persisted or used for advertising,
> and no human reviews the data.

**機能ドキュメントのリンク（最大 3 件）**

- https://gymnee.app/
- https://gymnee.app/privacy-policy.html

### 4. デモ動画（YouTube・限定公開）

要件: 英語（または英語字幕）、OAuth 同意画面にアプリ名が出ていること、各スコープが実際に何に
使われるかを映すこと。

台本:

1. Google Cloud Console → 認証情報 → iOS OAuth クライアントを開き、**クライアント ID を画面に映す**
   （ネイティブアプリは同意画面にアドレスバーが出ないため、ここでクライアント ID を示す）
2. Gymnee を起動 → 設定 → カレンダー連携 → 「Google カレンダーと連携」をタップ
3. Google の同意画面を表示（アプリ名 `Gymnee` とカレンダーの権限が読めるように）→ 許可
4. 設定画面に連携中のメールアドレスが表示されるところ
5. 週プランナーを開き、**Google カレンダーの既存の予定が重なって表示される**ところ（= 読み取りの用途）
6. AI に週の計画を作らせ、**予定が入っている日が休養日になっている**ところ
7. 「この計画で確定」→ Google カレンダー（Web）を開き、**`Gymnee: ...` の予定が追加されている**ところ
   （= 書き込みの用途）
8. 設定 → 「Google 連携を解除」で権限が外れるところ

端末の言語は英語にして撮ると差し戻しが減る。

## 審査が通るまでの暫定運用

- 警告画面は「詳細」→「Gymnee（安全ではないページ）に移動」で続行できる。TestFlight / 社内検証はこれで回る
- 一般ユーザーには連携を勧めない。100 ユーザーの上限に達すると誰も連携できなくなる

## 参考

- [Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [未確認のアプリ](https://support.google.com/cloud/answer/7454865)
- [Google API サービスのユーザーデータに関するポリシー](https://developers.google.com/terms/api-services-user-data-policy)
