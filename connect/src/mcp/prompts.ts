// MCP の決まった問いかけ（prompts）。Claude などでは「/」や「＋」のメニューから選ぶだけで使える。
// 何をどう聞けばいいか分からない人のために、よく使う 3 つを用意する。

export interface PromptDef {
  name: string;
  title: string;
  description: string;
  arguments?: { name: string; description: string; required?: boolean }[];
  text: (args: Record<string, string>) => string;
}

export const PROMPTS: PromptDef[] = [
  {
    name: "weekly_review",
    title: "今週のふりかえり",
    description: "今週の記録を先週と比べて、よかったことと来週の一手をまとめる",
    text: () =>
      [
        "Gymnee の記録で、今週のふりかえりをしてほしい。",
        "1. get_summary で今週と先週の回数・セット数・総量・部位を読む。",
        "2. 必要なら list_workouts で今週の中身を見る。",
        "3. 次の 3 つを、短く日本語でまとめる: よかったこと（数字で）/ 偏っている部位や空いた日 / 来週の一手（1 つだけ）。",
        "責めない口調で。記録にないことは書かない。",
      ].join("\n"),
  },
  {
    name: "plan_next_week",
    title: "来週のメニューを組む",
    description: "週の目標と最近の記録から、来週のメニューを組んでアプリに届ける",
    arguments: [{ name: "focus", description: "重点にしたいこと（例: 胸を伸ばしたい / 時間がない）", required: false }],
    text: (args) =>
      [
        "Gymnee の記録をもとに、来週のメニューを組んでほしい。",
        args.focus ? `重点: ${args.focus}` : "",
        "1. get_summary で週の目標（回数）と最近の部位の偏りを見る。",
        "2. よくやる種目は get_exercise_history で直近の重量・回数を確かめる。",
        "3. 週の目標の回数ぶん、1 回ごとのメニュー（種目・セット・回数・重量）を組む。重量は直近から地続きに。",
        "4. 一覧を見せて、利用者が良いと言ったら、最初の 1 回分を propose_menu でアプリのコーチ画面に届ける。",
      ]
        .filter(Boolean)
        .join("\n"),
  },
  {
    name: "plateau_check",
    title: "伸び悩みを見る",
    description: "ある種目の伸びを履歴で確かめ、停滞していれば原因の候補と次の一手を出す",
    arguments: [{ name: "exercise", description: "種目名（例: ベンチプレス）", required: true }],
    text: (args) =>
      [
        `Gymnee の記録で、「${args.exercise ?? "種目"}」が伸び悩んでいないか見てほしい。`,
        "1. list_exercises で種目を探し、get_exercise_history で履歴を読む。",
        "2. 推定 1RM と総量の推移を、日付つきで短く示す。",
        "3. 停滞していれば、頻度・回数の帯・休みの取り方など、記録から言える原因の候補と、次の 2〜3 週の一手を出す。",
        "記録が少なければ、そう言う。医療的な判断はしない。",
      ].join("\n"),
  },
];

export function renderPrompt(name: string, args: Record<string, string>) {
  const def = PROMPTS.find((p) => p.name === name);
  if (!def) return null;
  for (const a of def.arguments ?? []) {
    if (a.required && !args[a.name]) return null;
  }
  return {
    description: def.description,
    messages: [{ role: "user" as const, content: { type: "text" as const, text: def.text(args) } }],
  };
}
