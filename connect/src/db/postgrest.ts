// Supabase の PostgREST を service role で叩く薄いクライアント。
// service role は RLS を素通りするので、このクラスを直接使ってよいのは repo.ts だけにする
// （利用者ごとに絞る条件を 1 か所に集めるため。AGENTS.md「DB に触れる場所」）。

export class PostgrestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | undefined,
    message: string,
  ) {
    super(message);
  }
}

export interface PostgrestConfig {
  url: string;
  serviceKey: string;
  fetch?: typeof fetch;
}

type Query = Record<string, string | number | boolean | undefined>;

export class Postgrest {
  private readonly base: string;
  private readonly doFetch: typeof fetch;

  constructor(private readonly config: PostgrestConfig) {
    this.base = `${config.url.replace(/\/$/, "")}/rest/v1`;
    // Workers では fetch を別のオブジェクトのメソッドとして呼ぶと Illegal invocation になるので、関数で包む。
    this.doFetch = config.fetch ?? ((input, init) => fetch(input, init));
  }

  private headers(extra: Record<string, string> = {}): Headers {
    const h = new Headers({ apikey: this.config.serviceKey, "Content-Type": "application/json", ...extra });
    // 旧来の service_role は JWT。新しい secret key（sb_secret_…）は apikey だけで通る。
    if (this.config.serviceKey.startsWith("eyJ")) h.set("Authorization", `Bearer ${this.config.serviceKey}`);
    return h;
  }

  private url(path: string, query: Query = {}): string {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(query)) if (v !== undefined) params.append(k, String(v));
    const qs = params.toString();
    return `${this.base}/${path}${qs ? `?${qs}` : ""}`;
  }

  private async send<T>(method: string, path: string, query: Query, body?: unknown, prefer?: string): Promise<T> {
    const res = await this.doFetch(this.url(path, query), {
      method,
      headers: this.headers(prefer ? { Prefer: prefer } : {}),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    if (!res.ok) {
      let code: string | undefined;
      let message = text.slice(0, 300);
      try {
        const parsed = JSON.parse(text) as { code?: string; message?: string };
        code = parsed.code;
        message = parsed.message ?? message;
      } catch {
        // 本文が JSON でないときはそのまま使う
      }
      throw new PostgrestError(res.status, code, `${method} ${path}: ${res.status} ${message}`);
    }
    return (text ? JSON.parse(text) : null) as T;
  }

  select<T>(table: string, query: Query): Promise<T[]> {
    return this.send<T[]>("GET", table, query);
  }

  insert<T>(table: string, rows: unknown, options: { onConflict?: string; ignoreDuplicates?: boolean; returning?: boolean } = {}): Promise<T[]> {
    const prefer = [
      options.returning === false ? "return=minimal" : "return=representation",
      options.onConflict ? (options.ignoreDuplicates ? "resolution=ignore-duplicates" : "resolution=merge-duplicates") : undefined,
    ]
      .filter(Boolean)
      .join(",");
    return this.send<T[]>("POST", table, options.onConflict ? { on_conflict: options.onConflict } : {}, rows, prefer).then(
      (r) => r ?? [],
    );
  }

  update<T>(table: string, query: Query, patch: unknown): Promise<T[]> {
    return this.send<T[]>("PATCH", table, query, patch, "return=representation");
  }

  delete(table: string, query: Query): Promise<unknown> {
    return this.send("DELETE", table, query, undefined, "return=minimal");
  }

  rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
    return this.send<T>("POST", `rpc/${fn}`, {}, args);
  }
}

/** PostgREST のフィルタ値（eq.<uuid> など）に入れる前に、uuid の形かを確かめる。 */
export function assertUuid(value: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new PostgrestError(400, "invalid_uuid", "uuid の形ではない");
  }
  return value.toLowerCase();
}
