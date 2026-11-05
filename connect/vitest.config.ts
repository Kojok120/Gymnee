import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// ドメインの純粋関数と、HTTP の入口を偽の DB で確かめる。Workers の実行環境は使わない
// （Web Crypto・fetch・Request/Response は Node 24 にもある）。`cloudflare:workers` だけ代役を当てる。
export default defineConfig({
  resolve: {
    alias: { "cloudflare:workers": fileURLToPath(new URL("./test/stubs/cloudflare-workers.ts", import.meta.url)) },
  },
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    server: { deps: { inline: ["@cloudflare/workers-oauth-provider"] } },
  },
});
