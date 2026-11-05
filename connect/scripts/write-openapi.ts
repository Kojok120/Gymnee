// OpenAPI の文書を docs/connect/api/openapi.json に書き出す（ドキュメントのサイトが読む）。
//   pnpm openapi
// operations.ts を直したら流し直してコミットする。CI はずれていないかを確かめる（pnpm openapi:check）。
import { writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { openApiDocument } from "../src/api/openapi.js";

const out = join(dirname(fileURLToPath(import.meta.url)), "../../docs/connect/api/openapi.json");
const text = `${JSON.stringify(openApiDocument("https://api.gymnee.app"), null, 2)}\n`;
if (process.argv.includes("--check")) {
  const current = readFileSync(out, "utf8");
  if (current !== text) {
    console.error("docs/connect/api/openapi.json が operations.ts とずれている。pnpm openapi で書き出し直して");
    process.exit(1);
  }
  console.log("openapi.json は最新");
} else {
  writeFileSync(out, text);
  console.log(`書き出した: ${out}`);
}
