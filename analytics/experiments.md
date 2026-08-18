# 実験 PDCA 台帳 (experiments)

Gymnee のグロース実験を PDCA で管理する台帳。`growth-strategist` が `/growth-experiment` で **status: proposed** で起票し、
実装・リリース後に `/growth-measure <id>` で **status: completed** に更新して勝敗 (win/loss/flat) を記録する。

**原則**:
- 各実験は必ず「実在ファイルパス」に接地する (抽象施策は起票しない)。
- baseline (起票時のスナップショット値) を必ず転記する (無いと効果測定できない)。
- 成功指標はスナップショットの実フィールド名で書く (例 `supabase.activation.activatedWorkout`)。
- 小 N なので目標は絶対数でも表現する (例 "活性化 3→5/7")。
- 既に否定された仮説は再提案しない。

## エントリ書式

各実験は以下のブロックで記述する。追記時は既存ブロックを消さない。

```
### EXP-YYYYMMDD-<短いkebab>
- status: proposed | running | completed
- ボトルネック: <ファネルのどの段か>
- 仮説: 〜すれば、〜が改善する。なぜなら〜。
- 変更内容: <実在ファイルパス付きの最小差分>
- 主要成功指標: <snapshot の実フィールド名>
- baseline: <起票時の値・スナップショット日付>
- 目標: <現実的な改善幅 (絶対数)>
- 計測窓: <日数 or N 到達基準>
- ガードレール: <悪化を許さない指標>
- 工数: S | M | L
- ICE: Impact=_ / Confidence=_ / Ease=_ (合計 _)
- result: (completed 時に追記) 判定 / start値 → end値 / lift / 所感 / 測定日
```

## 進行中・完了した実験

### EXP-20260818-notification-permission-after-workout
- status: proposed
- ボトルネック: 通知の到達母数
- 仮説: 記録完了後の成長祝いを見せた直後に通知許諾を尋ねれば、カレンダー画面に依存するより許諾率が上がる。利用者が通知の価値を体験した直後だから。
- 変更内容: Gymnee/Features/Character/CharacterRoomView.swift で成長祝いの終了後にプリパーミッションを表示し、Gymnee/Features/Calendar/CalendarHomeView.swift の表示を撤去。scripts/analytics/pull-supabase.mjs に到達率を追加。
- 主要成功指標: supabase.features.pushReachableRate
- baseline: 30% (3/10、2026-08-18 の Issue #109 調査)
- 目標: 60%以上 (少なくとも 6/10)
- 計測窓: リリース後30日または対象10人のどちらか早い方
- ガードレール: supabase.activation.activatedWorkout と supabase.retention.returnedAfterDay0 を悪化させない
- 工数: S
- ICE: Impact=8 / Confidence=7 / Ease=8 (合計 23)
- result: (completed 時に追記)
