---
description: 最新レポートの第1ボトルネックから、実在プロダクト面に紐づく実験を growth-strategist で起票する
argument-hint: "[ボトルネック or 空]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Task
---

診断されたボトルネックを「打てる実験」に翻訳し、`analytics/experiments.md` に起票する。`/growth-report` の後に使う。

## 手順

1. `analytics/reports/` の最新レポートを読む。無ければ「先に `/growth-report`」と伝えて停止。
2. `growth-strategist` サブエージェントを Task で起動する。
   - 引数 `$ARGUMENTS` があればそれを対象ボトルネックとして渡す。
   - 空なら「最新レポートの第 1 ボトルネックを対象に実験を設計・起票せよ」と渡す。
3. strategist が `analytics/experiments.md` に status:proposed で起票する。
4. 起票結果 (id・仮説・成功指標・baseline・工数・ICE) をユーザーに提示し、次の流れを案内する:
   - 実装は人間 or 実装エージェントが担当 (strategist は起票のみ)。SwiftUI の View / Core/Domain / Localizable.xcstrings / supabase を最小差分で。
   - 実装・リリース後、計測窓が終わったら `/growth-measure <id>` で効果測定。

## 注意

- 施策は必ず実在ファイル名付き (strategist の責務)。抽象的な提案なら差し戻す。
- 既に否定済みの仮説の再提案になっていないか、experiments.md と突き合わせる。
- 活性化・継続が薄いうちは課金最適化より上流 (登録→初回記録→習慣化) を優先する。
