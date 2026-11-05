// 利用者ごとに絞った DB の読み書き。service role を使うのはここだけにする。
// どの関数も最初の引数に「認証で確かめた利用者 id」を取り、必ずその id で絞る。
// 呼び出し側（API・MCP・LINE）から来た値で、ほかの利用者の行に届く経路を作らない。

import { assertUuid, PostgrestError, type Postgrest } from "./postgrest.js";
import type { ExerciseInfo, LoadMode, MeasurementType, PersonalRecordRow, WorkoutRecord } from "../domain/types.js";

// ---- 行の形（PostgREST の返り値） ----

interface ExerciseRow {
  id: string;
  name: string;
  muscle_group: string;
  equipment: string;
  measurement_type: string | null;
  load_mode: string | null;
  is_custom: boolean;
}

interface SetRow {
  set_index: number;
  weight: number;
  reps: number;
  duration_seconds: number | null;
  distance_km: number | null;
  is_pr: boolean;
}

interface WorkoutRow {
  id: string;
  name: string;
  date: string;
  completed_at: string;
  duration_seconds: number | null;
  note: string | null;
  workout_exercises: {
    order_index: number;
    exercises: ExerciseRow | null;
    exercise_sets: SetRow[];
  }[];
}

const EXERCISE_COLUMNS = "id,name,muscle_group,equipment,measurement_type,load_mode,is_custom";
const WORKOUT_SELECT =
  `id,name,date,completed_at,duration_seconds,note,` +
  `workout_exercises(order_index,exercises(${EXERCISE_COLUMNS}),exercise_sets(set_index,weight,reps,duration_seconds,distance_km,is_pr))`;

function toExercise(row: ExerciseRow): ExerciseInfo {
  return {
    id: row.id,
    name: row.name,
    muscleGroup: row.muscle_group,
    equipment: row.equipment,
    measurementType: (row.measurement_type ?? "weight") as MeasurementType,
    loadMode: (row.load_mode ?? "none") as LoadMode,
    isCustom: row.is_custom,
  };
}

function toWorkout(row: WorkoutRow): WorkoutRecord {
  return {
    id: row.id,
    name: row.name,
    date: row.date,
    completedAt: row.completed_at,
    durationSeconds: row.duration_seconds,
    note: row.note,
    exercises: [...row.workout_exercises]
      .sort((a, b) => a.order_index - b.order_index)
      .map((we) => ({
        exercise: we.exercises ? toExercise(we.exercises) : null,
        sets: [...we.exercise_sets]
          .sort((a, b) => a.set_index - b.set_index)
          .map((s) => ({
            index: s.set_index,
            weightKg: s.weight,
            reps: s.reps,
            durationSeconds: s.duration_seconds,
            distanceKm: s.distance_km,
            isPR: s.is_pr,
          })),
      })),
  };
}

export interface ApiTokenRow {
  id: string;
  user_id: string;
  name: string;
  token_prefix: string;
  scopes: string[];
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export interface PairingRow {
  id: string;
  code: string;
  status: "pending" | "approved" | "denied" | "consumed";
  client_name: string;
  client_domain: string | null;
  redirect_host: string;
  redirect_is_loopback: boolean;
  scopes: string[];
  user_id: string | null;
  approved_scopes: string[] | null;
  created_at: string;
  expires_at: string;
}

export const DESTINATION_COLUMNS = "id,user_id,kind,label,events,consecutive_failures,disabled_at,disabled_reason,last_delivered_at,created_at";

export interface DestinationRow {
  id: string;
  user_id: string;
  kind: "slack" | "discord" | "webhook";
  label: string;
  events: string[];
  consecutive_failures: number;
  disabled_at: string | null;
  disabled_reason: string | null;
  last_delivered_at: string | null;
  created_at: string;
}

export interface DestinationSecretRow extends DestinationRow {
  target_ciphertext: string;
  signing_secret_ciphertext: string | null;
}

export interface DeliveryRow {
  id: string;
  destination_id: string;
  user_id: string;
  event_type: string;
  subject_key: string;
  subject_id: string | null;
  period_start: string | null;
  status: string;
  attempts: number;
  next_attempt_at: string;
}

export interface LineLinkRow {
  user_id: string;
  line_user_id: string;
  notify_mode: "off" | "lapse" | "daily" | "daily_menu";
  notify_hour: number;
  last_notified_on: string | null;
  linked_at: string;
  updated_at: string;
}

export interface PartyOverview {
  party_id: string;
  name: string | null;
  week_start: string;
  boss_id: string;
  hp: number;
  damage: number;
  defeated: boolean;
  member_count: number;
  my_hits: number;
  my_weekly_goal: number;
}

export class Repo {
  constructor(private readonly db: Postgrest) {}

  // ---- 利用者 ----

  async profile(userId: string): Promise<{ id: string; displayName: string } | null> {
    const rows = await this.db.select<{ id: string; display_name: string }>("profiles", {
      select: "id,display_name",
      id: `eq.${assertUuid(userId)}`,
    });
    const row = rows[0];
    return row ? { id: row.id, displayName: row.display_name } : null;
  }

  /** 週の目標。アプリの週目標はパーティに写されているので、そこから読む。無ければ 3（アプリの既定）。 */
  async weeklyGoal(userId: string): Promise<number> {
    const rows = await this.db.select<{ weekly_goal: number }>("party_members", {
      select: "weekly_goal",
      user_id: `eq.${assertUuid(userId)}`,
      order: "joined_at.desc",
      limit: 1,
    });
    return rows[0]?.weekly_goal ?? 3;
  }

  // ---- 記録 ----

  async completedWorkouts(
    userId: string,
    options: { from?: Date; to?: Date; limit?: number } = {},
  ): Promise<WorkoutRecord[]> {
    const query: Record<string, string | number> = {
      select: WORKOUT_SELECT,
      user_id: `eq.${assertUuid(userId)}`,
      is_planned: "is.false",
      order: "completed_at.desc",
      limit: Math.max(1, Math.min(options.limit ?? 50, 500)),
    };
    // completed_at の下限・上限。PostgREST は同じ列への複数条件を and=() で書く。
    const conditions = ["completed_at.not.is.null"];
    if (options.from) conditions.push(`completed_at.gte."${options.from.toISOString()}"`);
    if (options.to) conditions.push(`completed_at.lt."${options.to.toISOString()}"`);
    query.and = `(${conditions.join(",")})`;
    const rows = await this.db.select<WorkoutRow>("workouts", query);
    return rows.map(toWorkout);
  }

  async workout(userId: string, workoutId: string): Promise<WorkoutRecord | null> {
    const rows = await this.db.select<WorkoutRow>("workouts", {
      select: WORKOUT_SELECT,
      id: `eq.${assertUuid(workoutId)}`,
      user_id: `eq.${assertUuid(userId)}`,
      completed_at: "not.is.null",
    });
    return rows[0] ? toWorkout(rows[0]) : null;
  }

  /** 使える種目: プリセット（created_by が null）と本人の種目。 */
  async exercises(userId: string): Promise<ExerciseInfo[]> {
    const rows = await this.db.select<ExerciseRow>("exercises", {
      select: EXERCISE_COLUMNS,
      or: `(created_by.is.null,created_by.eq.${assertUuid(userId)})`,
      order: "name.asc",
      limit: 2000,
    });
    return rows.map(toExercise);
  }

  /** 種目ごとの過去のセット（自己ベストの判定と履歴に使う）。完了した記録のものだけ。 */
  async setsForExercises(
    userId: string,
    exerciseIds: string[],
  ): Promise<{ exerciseId: string; completedAt: string; workoutId: string; set: SetRow }[]> {
    if (exerciseIds.length === 0) return [];
    const ids = exerciseIds.map(assertUuid).join(",");
    const rows = await this.db.select<{
      id: string;
      completed_at: string;
      workout_exercises: { exercise_id: string; exercise_sets: SetRow[] }[];
    }>("workouts", {
      select: "id,completed_at,workout_exercises!inner(exercise_id,exercise_sets(set_index,weight,reps,duration_seconds,distance_km,is_pr))",
      user_id: `eq.${assertUuid(userId)}`,
      completed_at: "not.is.null",
      is_planned: "is.false",
      "workout_exercises.exercise_id": `in.(${ids})`,
      order: "completed_at.desc",
      limit: 500,
    });
    return rows.flatMap((w) =>
      w.workout_exercises.flatMap((we) =>
        we.exercise_sets.map((set) => ({ exerciseId: we.exercise_id, completedAt: w.completed_at, workoutId: w.id, set })),
      ),
    );
  }

  async personalRecords(userId: string): Promise<PersonalRecordRow[]> {
    const rows = await this.db.select<{
      exercise_id: string | null;
      type: string;
      value: number;
      achieved_at: string;
      workout_id: string | null;
      exercises: { name: string } | null;
    }>("personal_records", {
      select: "exercise_id,type,value,achieved_at,workout_id,exercises(name)",
      user_id: `eq.${assertUuid(userId)}`,
      order: "achieved_at.desc",
      limit: 500,
    });
    return rows.map((r) => ({
      exerciseId: r.exercise_id,
      exerciseName: r.exercises?.name ?? null,
      type: r.type,
      value: r.value,
      achievedAt: r.achieved_at,
      workoutId: r.workout_id,
    }));
  }

  async bodyMetrics(
    userId: string,
    options: { from?: Date; to?: Date; limit?: number } = {},
  ): Promise<{ date: string; weightKg: number | null; bodyFatPercent: number | null }[]> {
    const conditions: string[] = [];
    if (options.from) conditions.push(`date.gte."${options.from.toISOString()}"`);
    if (options.to) conditions.push(`date.lt."${options.to.toISOString()}"`);
    const rows = await this.db.select<{ date: string; weight: number | null; body_fat: number | null }>("body_metrics", {
      select: "date,weight,body_fat",
      user_id: `eq.${assertUuid(userId)}`,
      // ヘルスケア（HealthKit）から取り込んだ値は外へ出さない（プライバシーポリシー「健康・フィットネスデータの取扱い」）。
      from_health_kit: "is.false",
      ...(conditions.length ? { and: `(${conditions.join(",")})` } : {}),
      order: "date.desc",
      limit: Math.max(1, Math.min(options.limit ?? 90, 500)),
    });
    return rows.map((r) => ({ date: r.date, weightKg: r.weight, bodyFatPercent: r.body_fat }));
  }

  /** 記録を 1 トランザクションで書く（0046 の connect_log_workout）。 */
  logWorkout(userId: string, payload: Record<string, unknown>): Promise<{ workout_id: string; created: boolean }> {
    return this.db.rpc("connect_log_workout", { p_user: assertUuid(userId), p_workout: payload });
  }

  // ---- コーチ ----

  /** アプリのコーチ画面にメッセージ（と提案）を置く。アプリは差分 pull で受け取る。 */
  async addCoachMessage(
    userId: string,
    message: { body: string; isFromCoach: boolean; proposal?: unknown; channel?: "app" | "line" | "mcp" | "api" },
  ): Promise<{ id: string }> {
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    await this.db.insert(
      "coach_messages",
      {
        id,
        user_id: assertUuid(userId),
        is_from_coach: message.isFromCoach,
        body: message.body.slice(0, 4000),
        proposal: message.proposal ?? null,
        is_applied: false,
        ...(message.channel ? { channel: message.channel } : {}),
        created_at: now,
        updated_at: now,
      },
      { returning: false },
    );
    return { id };
  }

  /** 本人のコーチの提案（LINE の「やった！記録する」で使う）。 */
  async coachProposal(userId: string, messageId: string): Promise<{ title: string; exercises: { name: string; sets: number; reps: number; weightKg: number }[] } | null> {
    const rows = await this.db.select<{ proposal: { title?: string; exercises?: { name: string; sets: number; reps: number; weightKg: number }[] } | null }>("coach_messages", {
      select: "proposal",
      id: `eq.${assertUuid(messageId)}`,
      user_id: `eq.${assertUuid(userId)}`,
    });
    const p = rows[0]?.proposal;
    if (!p || !Array.isArray(p.exercises) || p.exercises.length === 0) return null;
    return { title: p.title ?? "今日のメニュー", exercises: p.exercises };
  }

  async recentCoachMessages(userId: string, limit = 12): Promise<{ isFromCoach: boolean; body: string; createdAt: string }[]> {
    const rows = await this.db.select<{ is_from_coach: boolean; body: string; created_at: string }>("coach_messages", {
      select: "is_from_coach,body,created_at",
      user_id: `eq.${assertUuid(userId)}`,
      order: "created_at.desc",
      limit,
    });
    return rows.reverse().map((r) => ({ isFromCoach: r.is_from_coach, body: r.body, createdAt: r.created_at }));
  }

  // ---- パーティ ----

  partyOverview(userId: string, now = new Date()): Promise<PartyOverview[]> {
    return this.db.rpc("connect_party_overview", { p_user: assertUuid(userId), p_now: now.toISOString() });
  }

  // ---- OAuth の承認待ち（ペアリング） ----
  // ペアリングの id は推測できない乱数（uuid v4）。ブラウザは id を知っているだけで、利用者 id は持たない。

  async createPairing(p: Omit<PairingRow, "id" | "status" | "user_id" | "approved_scopes" | "created_at" | "expires_at">): Promise<PairingRow> {
    const rows = await this.db.insert<PairingRow>("connect_oauth_pairings", p);
    return rows[0]!;
  }

  /** まだ切れていない承認待ち。 */
  async pairing(id: string): Promise<PairingRow | null> {
    const rows = await this.db.select<PairingRow>("connect_oauth_pairings", {
      select: "*",
      id: `eq.${assertUuid(id)}`,
      expires_at: `gt.${new Date().toISOString()}`,
    });
    return rows[0] ?? null;
  }

  /** アプリでの承認・拒否。まだ誰も決めていない承認待ちだけを動かす（先に決めた人が勝ち、上書きさせない）。 */
  async decidePairing(userId: string, id: string, decision: "approved" | "denied", scopes: string[]): Promise<boolean> {
    const rows = await this.db.update<PairingRow>(
      "connect_oauth_pairings",
      { id: `eq.${assertUuid(id)}`, status: "eq.pending", expires_at: `gt.${new Date().toISOString()}` },
      { status: decision, user_id: assertUuid(userId), approved_scopes: scopes, decided_at: new Date().toISOString() },
    );
    return rows.length > 0;
  }

  /** ブラウザが承認を受け取ったら使い切る（同じ承認で 2 回トークンを出さない）。 */
  async consumePairing(id: string): Promise<PairingRow | null> {
    const rows = await this.db.update<PairingRow>(
      "connect_oauth_pairings",
      { id: `eq.${assertUuid(id)}`, status: "in.(approved,denied)", expires_at: `gt.${new Date().toISOString()}` },
      { status: "consumed" },
    );
    return rows[0] ?? null;
  }

  async purgeExpiredPairings(): Promise<void> {
    await this.db.delete("connect_oauth_pairings", { expires_at: `lt.${new Date(Date.now() - 86_400_000).toISOString()}` });
  }

  // ---- 送り先（Slack / Discord / 汎用 Webhook） ----

  listDestinations(userId: string): Promise<DestinationRow[]> {
    return this.db.select<DestinationRow>("connect_destinations", {
      select: DESTINATION_COLUMNS,
      user_id: `eq.${assertUuid(userId)}`,
      order: "created_at.asc",
    });
  }

  async destination(userId: string, id: string): Promise<DestinationRow | null> {
    const rows = await this.db.select<DestinationRow>("connect_destinations", {
      select: DESTINATION_COLUMNS,
      id: `eq.${assertUuid(id)}`,
      user_id: `eq.${assertUuid(userId)}`,
    });
    return rows[0] ?? null;
  }

  async createDestination(
    userId: string,
    d: { kind: string; label: string; targetCiphertext: string; signingSecretCiphertext: string | null; events: string[] },
  ): Promise<DestinationRow> {
    const rows = await this.db.insert<DestinationRow>("connect_destinations", {
      user_id: assertUuid(userId),
      kind: d.kind,
      label: d.label.slice(0, 120),
      target_ciphertext: d.targetCiphertext,
      signing_secret_ciphertext: d.signingSecretCiphertext,
      events: d.events,
    });
    return rows[0]!;
  }

  async updateDestinationEvents(userId: string, id: string, events: string[]): Promise<DestinationRow | null> {
    const rows = await this.db.update<DestinationRow>(
      "connect_destinations",
      { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}` },
      { events, updated_at: new Date().toISOString() },
    );
    return rows[0] ?? null;
  }

  /** 止まった送り先を、利用者が「もう一度試す」で戻す。 */
  async resumeDestination(userId: string, id: string): Promise<DestinationRow | null> {
    const rows = await this.db.update<DestinationRow>(
      "connect_destinations",
      { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}` },
      { disabled_at: null, disabled_reason: null, consecutive_failures: 0, updated_at: new Date().toISOString() },
    );
    return rows[0] ?? null;
  }

  async deleteDestination(userId: string, id: string): Promise<void> {
    await this.db.delete("connect_destinations", { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}` });
  }

  async destinationSucceeded(userId: string, id: string): Promise<void> {
    await this.db.update(
      "connect_destinations",
      { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}` },
      { consecutive_failures: 0, last_delivered_at: new Date().toISOString() },
    );
  }

  /** 配信を諦めた回数を 1 つ数え、続けて失敗していれば止める。`disableReason` があれば数によらず止める。 */
  async destinationFailed(userId: string, id: string, failuresSoFar: number, disableAfter: number, disableReason?: string): Promise<void> {
    const failures = failuresSoFar + 1;
    const reason = disableReason ?? (failures >= disableAfter ? "続けて届かなかったので止めました" : null);
    await this.db.update(
      "connect_destinations",
      { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}` },
      {
        consecutive_failures: failures,
        ...(reason ? { disabled_at: new Date().toISOString(), disabled_reason: reason } : {}),
        updated_at: new Date().toISOString(),
      },
    );
  }

  // ---- 配信（cron のジョブが使う。どれも配信の行が持つ利用者 id で絞る） ----

  fanoutEvents(limit = 50): Promise<number> {
    return this.db.rpc("connect_fanout_events", { p_limit: limit });
  }

  enqueueWeekly(weekStart: Date): Promise<number> {
    return this.db.rpc("connect_enqueue_weekly", { p_week_start: weekStart.toISOString() });
  }

  claimDeliveries(limit = 25): Promise<DeliveryRow[]> {
    return this.db.rpc("connect_claim_deliveries", { p_limit: limit });
  }

  async finishDelivery(
    delivery: DeliveryRow,
    result: { status: "pending" | "succeeded" | "failed"; nextAttemptAt?: Date; httpStatus: number | null; error: string | null },
  ): Promise<void> {
    await this.db.update(
      "connect_deliveries",
      { id: `eq.${assertUuid(delivery.id)}`, user_id: `eq.${assertUuid(delivery.user_id)}` },
      {
        status: result.status,
        ...(result.nextAttemptAt ? { next_attempt_at: result.nextAttemptAt.toISOString() } : {}),
        last_status: result.httpStatus,
        last_error: result.error?.slice(0, 300) ?? null,
        updated_at: new Date().toISOString(),
      },
    );
  }

  /** 配信先を、配信の行の利用者 id とあわせて引く（秘密の暗号文を含む）。 */
  async destinationWithSecrets(userId: string, id: string): Promise<DestinationSecretRow | null> {
    const rows = await this.db.select<DestinationSecretRow>("connect_destinations", {
      select: `${DESTINATION_COLUMNS},target_ciphertext,signing_secret_ciphertext`,
      id: `eq.${assertUuid(id)}`,
      user_id: `eq.${assertUuid(userId)}`,
    });
    return rows[0] ?? null;
  }

  purge(): Promise<void> {
    return this.db.rpc("connect_purge", {});
  }

  // ---- LINE ----

  async lineLinkByUser(userId: string): Promise<LineLinkRow | null> {
    const rows = await this.db.select<LineLinkRow>("line_links", { select: "*", user_id: `eq.${assertUuid(userId)}` });
    return rows[0] ?? null;
  }

  /** LINE の利用者 id から持ち主を引く（webhook の入口。LINE の署名を確かめたあとだけ呼ぶ）。 */
  async lineLinkByLineUser(lineUserId: string): Promise<LineLinkRow | null> {
    if (!/^U[0-9a-f]{32}$/.test(lineUserId)) return null;
    const rows = await this.db.select<LineLinkRow>("line_links", { select: "*", line_user_id: `eq.${lineUserId}` });
    return rows[0] ?? null;
  }

  /** 連携コードを作る（前のコードは消す）。6 桁の数字。 */
  async createLinkCode(userId: string): Promise<{ code: string; expiresAt: string }> {
    await this.db.delete("line_link_codes", { user_id: `eq.${assertUuid(userId)}` });
    for (let i = 0; i < 5; i++) {
      const n = new Uint32Array(1);
      crypto.getRandomValues(n);
      const code = String(n[0]! % 1_000_000).padStart(6, "0");
      try {
        const rows = await this.db.insert<{ code: string; expires_at: string }>("line_link_codes", { code, user_id: assertUuid(userId) });
        return { code, expiresAt: rows[0]!.expires_at };
      } catch (error) {
        if (!(error instanceof PostgrestError && error.code === "23505")) throw error;
      }
    }
    throw new Error("連携コードを作れなかった");
  }

  /** 連携コードを使い切って持ち主を返す。切れている・無ければ null。 */
  async consumeLinkCode(code: string): Promise<string | null> {
    if (!/^[0-9]{6}$/.test(code)) return null;
    const rows = await this.db.select<{ user_id: string }>("line_link_codes", {
      select: "user_id",
      code: `eq.${code}`,
      expires_at: `gt.${new Date().toISOString()}`,
    });
    const userId = rows[0]?.user_id;
    if (!userId) return null;
    await this.db.delete("line_link_codes", { code: `eq.${code}` });
    return userId;
  }

  /** 連携コードの試行を数える（総当たりを止める）。この 1 時間の回数を返す。 */
  async recordLinkAttempt(lineUserId: string): Promise<number> {
    await this.db.insert("line_link_attempts", { line_user_id: lineUserId }, { returning: false });
    const rows = await this.db.select<{ line_user_id: string }>("line_link_attempts", {
      select: "line_user_id",
      line_user_id: `eq.${lineUserId}`,
      attempted_at: `gt.${new Date(Date.now() - 3_600_000).toISOString()}`,
    });
    return rows.length;
  }

  /** 紐付ける。この LINE が別のアカウントに付いていれば "already"。同じアカウントの前の LINE は付け替える。 */
  async linkLine(userId: string, lineUserId: string): Promise<"linked" | "already"> {
    const existing = await this.lineLinkByLineUser(lineUserId);
    if (existing && existing.user_id !== userId) return "already";
    await this.db.insert(
      "line_links",
      { user_id: assertUuid(userId), line_user_id: lineUserId, linked_at: new Date().toISOString(), updated_at: new Date().toISOString() },
      { onConflict: "user_id", returning: false },
    );
    return "linked";
  }

  async updateLineSettings(userId: string, settings: { notifyMode?: string; notifyHour?: number }): Promise<LineLinkRow | null> {
    const rows = await this.db.update<LineLinkRow>(
      "line_links",
      { user_id: `eq.${assertUuid(userId)}` },
      {
        ...(settings.notifyMode ? { notify_mode: settings.notifyMode } : {}),
        ...(settings.notifyHour !== undefined ? { notify_hour: settings.notifyHour } : {}),
        updated_at: new Date().toISOString(),
      },
    );
    return rows[0] ?? null;
  }

  async unlinkLine(userId: string): Promise<void> {
    await this.db.delete("line_links", { user_id: `eq.${assertUuid(userId)}` });
  }

  /** ブロック（友だち解除）されたら紐付けを消す。 */
  async unlinkLineUser(lineUserId: string): Promise<void> {
    if (!/^U[0-9a-f]{32}$/.test(lineUserId)) return;
    await this.db.delete("line_links", { line_user_id: `eq.${lineUserId}` });
  }

  claimLineNotifications(hour: number, day: string, limit = 20): Promise<LineLinkRow[]> {
    return this.db.rpc("connect_claim_line_notifications", { p_hour: hour, p_day: day, p_limit: limit });
  }

  takeAiQuota(userId: string, day: string, limit: number): Promise<boolean> {
    return this.db.rpc("connect_take_ai_quota", { p_user: assertUuid(userId), p_day: day, p_limit: limit });
  }

  async createPendingLog(userId: string, payload: unknown): Promise<string> {
    const rows = await this.db.insert<{ id: string }>("line_pending_logs", { user_id: assertUuid(userId), payload });
    return rows[0]!.id;
  }

  async pendingLog(userId: string, id: string): Promise<unknown | null> {
    const rows = await this.db.select<{ payload: unknown }>("line_pending_logs", {
      select: "payload",
      id: `eq.${assertUuid(id)}`,
      user_id: `eq.${assertUuid(userId)}`,
      consumed_at: "is.null",
      expires_at: `gt.${new Date().toISOString()}`,
    });
    return rows[0]?.payload ?? null;
  }

  async updatePendingLog(userId: string, id: string, payload: unknown): Promise<void> {
    await this.db.update("line_pending_logs", { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}`, consumed_at: "is.null" }, { payload });
  }

  /** 確認待ちを使い切る。先に押された方だけが true（二重に記録しない）。 */
  async consumePendingLog(userId: string, id: string): Promise<boolean> {
    const rows = await this.db.update<{ id: string }>(
      "line_pending_logs",
      { id: `eq.${assertUuid(id)}`, user_id: `eq.${assertUuid(userId)}`, consumed_at: "is.null", expires_at: `gt.${new Date().toISOString()}` },
      { consumed_at: new Date().toISOString() },
    );
    return rows.length > 0;
  }

  // ---- PAT ----

  async createApiToken(userId: string, token: { name: string; hash: string; prefix: string; scopes: string[] }): Promise<ApiTokenRow> {
    const rows = await this.db.insert<ApiTokenRow>("connect_api_tokens", {
      user_id: assertUuid(userId),
      name: token.name,
      token_hash: token.hash,
      token_prefix: token.prefix,
      scopes: token.scopes,
    });
    return rows[0]!;
  }

  listApiTokens(userId: string): Promise<ApiTokenRow[]> {
    return this.db.select<ApiTokenRow>("connect_api_tokens", {
      select: "id,user_id,name,token_prefix,scopes,created_at,last_used_at,revoked_at",
      user_id: `eq.${assertUuid(userId)}`,
      revoked_at: "is.null",
      order: "created_at.desc",
    });
  }

  async revokeApiToken(userId: string, tokenId: string): Promise<boolean> {
    const rows = await this.db.update<ApiTokenRow>(
      "connect_api_tokens",
      { id: `eq.${assertUuid(tokenId)}`, user_id: `eq.${assertUuid(userId)}`, revoked_at: "is.null" },
      { revoked_at: new Date().toISOString() },
    );
    return rows.length > 0;
  }

  /** トークンのハッシュから持ち主を引く（認証）。利用者 id を持たない唯一の入口なので、ハッシュ完全一致だけで引く。 */
  async apiTokenByHash(hash: string): Promise<ApiTokenRow | null> {
    if (!/^[0-9a-f]{64}$/.test(hash)) return null;
    const rows = await this.db.select<ApiTokenRow>("connect_api_tokens", {
      select: "id,user_id,name,token_prefix,scopes,created_at,last_used_at,revoked_at",
      token_hash: `eq.${hash}`,
      revoked_at: "is.null",
    });
    return rows[0] ?? null;
  }

  /** 最後に使った日時。一覧に日付で出すだけなので、1 時間に 1 回より細かくは書かない（呼び出しのたびに書き込まない）。 */
  async touchApiToken(tokenId: string): Promise<void> {
    const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
    await this.db.update(
      "connect_api_tokens",
      { id: `eq.${assertUuid(tokenId)}`, or: `(last_used_at.is.null,last_used_at.lt."${hourAgo}")` },
      { last_used_at: new Date().toISOString() },
    );
  }
}
