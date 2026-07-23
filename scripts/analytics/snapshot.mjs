#!/usr/bin/env node
// グロース・ハーネス: スナップショット収集オーケストレータ (Gymnee)。
//
// App Store Connect (DL/課金) と 本番 Supabase (獲得〜継続〜課金〜ソーシャルのファネル) を
// 1 本で集め、JST 日時付き JSON を analytics/snapshots/<JST日時>.json に保存する。
// この履歴が傾向分析と実験の前後比較 (lift) の土台になる。決定論スクリプト・依存ゼロ。
// 手元で週 1 回叩く運用が基本 (nihongo の snapshot.ts と同じ思想)。
//
//   node scripts/analytics/snapshot.mjs [windowDays=30]
//
// 契約 (nihongo 準拠): 標準出力の最終行 = 保存パス 1 行、標準エラー = 要約。
//   どちらのソースも best-effort (失敗しても error フィールドを載せて続行)。
//   出力は { schema, generatedAtUtc, windowDays, appstore, supabase }。集計値のみ (個人情報なし)。
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pullAppStore } from './pull-appstore.mjs';
import { pullSupabase } from './pull-supabase.mjs';

async function main() {
    const windowDays = Number(process.argv[2] ?? 30) || 30;

    // どちらも best-effort。片方が失敗しても snapshot は保存する (error フィールドで残す)。
    const appstore = await pullAppStore({ windowDays: Math.min(windowDays, 30) });
    const supabase = await pullSupabase({ windowDays });

    const generatedAt = new Date();
    const snapshot = {
        schema: 1,
        generatedAtUtc: generatedAt.toISOString(),
        windowDays,
        appstore,
        supabase,
    };

    const scriptDir = dirname(fileURLToPath(import.meta.url));
    const outDir = resolve(scriptDir, '../../analytics/snapshots');
    mkdirSync(outDir, { recursive: true });
    // ファイル名は JST の日時 (分解能・分)。同日複数回実行しても上書きしない。字句順=時系列順。
    const jst = new Date(generatedAt.getTime() + 9 * 60 * 60 * 1000);
    const stamp = jst.toISOString().slice(0, 16).replace('T', '_').replace(':', '');
    const outPath = resolve(outDir, `${stamp}.json`);
    writeFileSync(outPath, JSON.stringify(snapshot, null, 2) + '\n');

    // 標準エラーに要約 (標準出力はパス 1 行のみ = 後段のコマンドが拾いやすい)。
    const sb = supabase;
    const asc = appstore;
    const reg = sb.registration ?? {};
    const act = sb.activation ?? {};
    const acty = sb.activity ?? {};
    const mon = sb.monetization ?? {};
    process.stderr.write(
        [
            `snapshot 保存: ${outPath}`,
            `期間: 直近 ${windowDays} 日 (JST ${stamp})`,
            sb.configured
                ? `Supabase: 登録 累計${reg.totalUsers}/期間内${reg.inWindow} · 活性化(初WO) ${act.activatedWorkout}/${act.cohortSize} · DAU ${acty.dau}/WAU ${acty.wau}/MAU ${acty.mau} · 課金 ${mon.paidActive}`
                : `Supabase: skip (${sb.error})`,
            asc.configured
                ? `App Store: ${asc.app?.name ?? asc.app?.label ?? 'OK'}${asc.downloads?.totals ? ` · DL新規 ${asc.downloads.totals.firstDownloads}` : asc.downloads?.error ? ' · DL取得不可' : ''}`
                : `App Store: skip (${asc.error})`,
        ].join('\n') + '\n',
    );
    process.stdout.write(outPath + '\n');
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
