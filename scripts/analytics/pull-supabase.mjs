#!/usr/bin/env node
// グロース分析ハーネス — Gymnee 本番 Supabase ファネル収集 (依存ゼロ / Node 標準モジュールのみ)
//
// Gymnee はオフラインファースト (SwiftData がローカルの正) だが、同期・認証・課金・ソーシャルを
// Supabase 本番 DB に集約するため、サーバ側に獲得〜継続〜課金〜ソーシャルのファネルが集まる。
// 本スクリプトはそれを **集計値だけ** 1 往復で取り、日付付き JSON に落とす決定論スクリプト。
//
// 設計原則 (P0 の pull-appstore.mjs を踏襲):
//   - LLM を使わない。資格情報やネットワークが無くても snapshot 全体を止めないよう、失敗は
//     例外で止めず configured:false / error フィールドに載せて best-effort 継続する。
//   - 標準出力は集計 JSON のみ、進捗・要約は標準エラーへ。
//   - **個人情報・生 ID・メールは一切取らない。COUNT / date_trunc グルーピングの集計値のみ**。
//   - SQL は SELECT ホワイトリスト (DML/DDL キーワードを含むクエリは実行前に拒否)。
//
// 集計経路: Supabase Management API のクエリエンドポイント
//   POST https://api.supabase.com/v1/projects/{ref}/database/query
//   → postgres 権限で走り RLS を無視できるため、集計値だけを 1 往復で取れる。
//
// 認証: SUPABASE_ACCESS_TOKEN (PAT sbp_...)。env 優先、無ければ macOS keychain の
//       `supabase login` トークン (setup_supabase_prod.sh と同じ読み方)。→ 新規秘密ゼロ。
// PROD_REF: env SUPABASE_PROD_REF 優先、無ければ secrets/.env の SUPABASE_PROD_HOST から抽出。
//
// 使い方:
//   node scripts/analytics/pull-supabase.mjs [days=30]
//   node scripts/analytics/pull-supabase.mjs --days 7
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const MGMT_BASE = 'https://api.supabase.com';

// ---- secrets/.env の簡易パーサ (pull-appstore.mjs と同型) ----
function parseEnvFile(path) {
    const kv = {};
    if (!existsSync(path)) return kv;
    for (const line of readFileSync(path, 'utf8').split('\n')) {
        if (line.trim().startsWith('#')) continue;
        const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
        if (m) kv[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
    return kv;
}

// ---- PROD_REF の解決 (env → secrets/.env の SUPABASE_PROD_HOST から [ref].supabase.co を剥がす) ----
function resolveProjectRef() {
    if (process.env.SUPABASE_PROD_REF) return process.env.SUPABASE_PROD_REF.trim();
    const scriptDir = dirname(fileURLToPath(import.meta.url));
    const repoSecrets = parseEnvFile(resolve(scriptDir, '../../secrets/.env'));
    const host = process.env.SUPABASE_PROD_HOST ?? repoSecrets.SUPABASE_PROD_HOST;
    if (!host) return null;
    // "abcd1234.supabase.co" でも "abcd1234" でも先頭ラベルを ref とする。
    return host.trim().replace(/^https?:\/\//, '').split('.')[0];
}

// ---- access token の解決 (env → macOS keychain "Supabase CLI"。setup_supabase_prod.sh と同じ) ----
function resolveAccessToken() {
    if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
    // macOS keychain フォールバック (このマシン限定)。値は go-keyring が base64 で符号化して保存する。
    try {
        let raw = execFileSync(
            'security',
            ['find-generic-password', '-s', 'Supabase CLI', '-a', 'supabase', '-w'],
            { encoding: 'utf8' },
        ).trim();
        raw = raw.replace(/^go-keyring-encoded:/, '').replace(/^go-keyring-base64:/, '');
        const decoded = Buffer.from(raw, 'base64').toString('utf8');
        // base64 デコードが妥当 (sbp_ で始まる PAT) ならそれを、そうでなければ生値を返す。
        return decoded.startsWith('sbp_') ? decoded : (raw.startsWith('sbp_') ? raw : decoded || raw);
    } catch {
        return null;
    }
}

// ---- SELECT ホワイトリスト (防御的。SQL はスクリプト内固定だが念のため) ----
const FORBIDDEN = /\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|copy|merge|call|do|vacuum|reindex)\b/i;
function assertReadOnly(sql) {
    const trimmed = sql.trim().toLowerCase();
    if (!trimmed.startsWith('with') && !trimmed.startsWith('select')) {
        throw new Error('SQL は SELECT / WITH のみ許可');
    }
    if (FORBIDDEN.test(sql)) throw new Error('SQL に禁止キーワードが含まれる (SELECT 集計のみ許可)');
}

async function runQuery(ref, token, sql) {
    assertReadOnly(sql);
    const res = await fetch(`${MGMT_BASE}/v1/projects/${ref}/database/query`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: sql, read_only: true }),
    });
    if (!res.ok) {
        let detail = '';
        try { detail = JSON.stringify(await res.json()); } catch { detail = (await res.text()).slice(0, 200); }
        throw new Error(`Management API HTTP ${res.status}: ${detail.slice(0, 300)}`);
    }
    return res.json();
}

// ---- ファネル集計 SQL (SELECT のみ・全指標ゼロでも壊れない・JST 日付でグルーピング) ----
// 活性化・活動の代理は workouts(date) と visits(visited_at) の union。
// スキーマ実体 (supabase/setup_all.sql) の実カラム名に厳密に合わせている:
//   profiles.created_at / workouts.date / visits.visited_at / exercise_sets.created_at /
//   subscriptions.tier+status+started_at / follows.created_at / feed_items.created_at /
//   personal_records.achieved_at / body_metrics.date / progress_photos.date / supply_logs.date /
//   post_reactions.created_at / comments.created_at / device_tokens(user_id) / routines(no created_at)
function buildFunnelSql(windowDays) {
    const n = Number(windowDays);
    if (!Number.isInteger(n) || n < 1 || n > 365) throw new Error(`windowDays 不正: ${windowDays}`);
    return `
with
params as (select (now() - make_interval(days => ${n}))::timestamptz as since),
cohort as (
  select p.id, (p.created_at at time zone 'Asia/Tokyo')::date as reg_day, p.created_at
  from public.profiles p, params
  where p.created_at >= params.since
),
act as (
  select user_id, date       as ts, (date       at time zone 'Asia/Tokyo')::date as d from public.workouts
  union all
  select user_id, visited_at as ts, (visited_at at time zone 'Asia/Tokyo')::date as d from public.visits
)
select json_build_object(
  'registration', json_build_object(
    'totalUsers', (select count(*) from public.profiles),
    'inWindow',   (select count(*) from cohort),
    'byDayJst',   (select coalesce(json_agg(json_build_object('day', d, 'count', c) order by d), '[]'::json)
                   from (select reg_day d, count(*) c from cohort group by reg_day) t)
  ),
  'activation', json_build_object(
    'cohortSize',       (select count(*) from cohort),
    'activatedWorkout', (select count(*) from cohort c where exists (select 1 from public.workouts w where w.user_id = c.id)),
    'activatedAny',     (select count(*) from cohort c where exists (select 1 from act a where a.user_id = c.id))
  ),
  'retention', json_build_object(
    'returnedAfterDay0', (select count(*) from cohort c where exists (select 1 from act a where a.user_id = c.id and a.d > c.reg_day)),
    'd7EligibleCohort',  (select count(*) from cohort c where c.created_at <= now() - interval '7 days'),
    'd7Retained',        (select count(*) from cohort c where c.created_at <= now() - interval '7 days'
                            and exists (select 1 from act a where a.user_id = c.id and a.d >= c.reg_day + 7)),
    'habitWeek3plus',    (select count(*) from (select user_id from public.workouts
                            where date >= now() - interval '7 days' group by user_id having count(*) >= 3) t)
  ),
  'activity', json_build_object(
    'dau', (select count(distinct user_id) from act where ts >= now() - interval '1 day'),
    'wau', (select count(distinct user_id) from act where ts >= now() - interval '7 days'),
    'mau', (select count(distinct user_id) from act where ts >= now() - interval '30 days'),
    'activeUsersInWindow', (select count(distinct a.user_id) from act a, params where a.ts >= params.since),
    'byDayJst', (select coalesce(json_agg(json_build_object('day', d, 'activeUsers', c) order by d), '[]'::json)
                 from (select a.d, count(distinct a.user_id) c from act a, params where a.ts >= params.since group by a.d) t)
  ),
  'engagement', json_build_object(
    'workoutsInWindow',     (select count(*) from public.workouts w,      params where w.date       >= params.since),
    'visitsInWindow',       (select count(*) from public.visits v,        params where v.visited_at  >= params.since),
    'exerciseSetsInWindow', (select count(*) from public.exercise_sets s, params where s.created_at  >= params.since)
  ),
  'monetization', json_build_object(
    'paidActive', (select count(*) from public.subscriptions where tier <> 'free' and status = 'active'),
    'byTier',     (select coalesce(json_agg(json_build_object('tier', tier, 'status', status, 'count', c) order by tier, status), '[]'::json)
                   from (select tier, status, count(*) c from public.subscriptions group by tier, status) t)
  ),
  'social', json_build_object(
    'followsTotal',      (select count(*) from public.follows),
    'followsInWindow',   (select count(*) from public.follows f, params where f.created_at >= params.since),
    'distinctFollowers', (select count(distinct follower_id) from public.follows),
    'feedItemsInWindow', (select count(*) from public.feed_items f, params where f.created_at >= params.since),
    'feedItemsByType',   (select coalesce(json_agg(json_build_object('type', type, 'count', c) order by type), '[]'::json)
                          from (select fi.type, count(*) c from public.feed_items fi, params where fi.created_at >= params.since group by fi.type) t),
    'reactionsInWindow', (select count(*) from public.post_reactions r, params where r.created_at >= params.since),
    'commentsInWindow',  (select count(*) from public.comments cm, params where cm.created_at >= params.since),
    'socialActiveUsers', (select count(distinct fi.user_id) from public.feed_items fi, params where fi.created_at >= params.since)
  ),
  'features', json_build_object(
    'personalRecordsInWindow', (select count(*) from public.personal_records pr, params where pr.achieved_at >= params.since),
    'bodyMetricsInWindow',     (select count(*) from public.body_metrics bm,     params where bm.date       >= params.since),
    'progressPhotosInWindow',  (select count(*) from public.progress_photos pp,  params where pp.date       >= params.since),
    'supplyLogsInWindow',      (select count(*) from public.supply_logs sl,      params where sl.date       >= params.since),
    'routinesTotal',           (select count(*) from public.routines),
    'pushReachableUsers',      (select count(distinct user_id) from public.device_tokens)
  )
) as result;`;
}

export async function pullSupabase(opts = {}) {
    const windowDays = opts.windowDays ?? 30;
    const ref = resolveProjectRef();
    if (!ref) {
        return { configured: false, error: 'PROD_REF 未解決 (secrets/.env の SUPABASE_PROD_HOST か env SUPABASE_PROD_REF を設定)' };
    }
    const token = resolveAccessToken();
    if (!token) {
        return {
            configured: false,
            projectRef: ref,
            error: 'SUPABASE_ACCESS_TOKEN 未取得 (env に PAT sbp_... を設定するか `supabase login` を実行)',
        };
    }

    try {
        const sql = buildFunnelSql(windowDays);
        const rows = await runQuery(ref, token, sql);
        // Management API は行の配列を返す。1 行 1 列 (result) を取り出す。
        const row = Array.isArray(rows) ? rows[0] : rows;
        let result = row?.result ?? row;
        if (typeof result === 'string') { try { result = JSON.parse(result); } catch { /* keep string */ } }
        return { configured: true, projectRef: ref, windowDays, ...result };
    } catch (err) {
        return { configured: false, projectRef: ref, windowDays, error: err.message };
    }
}

// ---- CLI ----
function parseArgs(argv) {
    const args = { windowDays: 30 };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--days') args.windowDays = Number(argv[++i]) || args.windowDays;
        else if (/^\d+$/.test(a)) args.windowDays = Number(a);
    }
    return args;
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const data = await pullSupabase(args);
    if (!data.configured) {
        process.stderr.write(`[Gymnee] Supabase 収集 skip: ${data.error}\n`);
    } else {
        const r = data.registration ?? {};
        const a = data.activation ?? {};
        const ac = data.activity ?? {};
        const m = data.monetization ?? {};
        process.stderr.write(
            [
                `[Gymnee] Supabase 収集 (直近 ${data.windowDays} 日 / ref ${data.projectRef})`,
                `  登録: 累計 ${r.totalUsers ?? '?'} / 期間内 ${r.inWindow ?? '?'}`,
                `  活性化 (初ワークアウト): ${a.activatedWorkout ?? '?'}/${a.cohortSize ?? '?'}`,
                `  活動: DAU ${ac.dau ?? '?'} / WAU ${ac.wau ?? '?'} / MAU ${ac.mau ?? '?'}`,
                `  課金 (有効): ${m.paidActive ?? '?'}`,
            ].join('\n') + '\n',
        );
    }
    process.stdout.write(JSON.stringify(data, null, 2) + '\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch((err) => {
        console.error(err);
        process.exit(1);
    });
}
