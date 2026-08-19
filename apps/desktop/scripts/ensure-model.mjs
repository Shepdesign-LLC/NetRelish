// The embedding model is ~90MB and lives outside git. This runs before
// dev and build (npm pre-hooks) and fetches it once per checkout.
import { createWriteStream, existsSync, statSync, mkdirSync } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dir = join(root, "src-tauri", "models");
const HF = "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main";

const files = [
  { name: "all-MiniLM-L6-v2.onnx", url: `${HF}/onnx/model.onnx`, minBytes: 80_000_000 },
  { name: "tokenizer.json", url: `${HF}/tokenizer.json`, minBytes: 100_000 },
];

mkdirSync(dir, { recursive: true });
for (const f of files) {
  const path = join(dir, f.name);
  if (existsSync(path) && statSync(path).size >= f.minBytes) continue;
  console.log(`[ensure-model] fetching ${f.name}…`);
  const res = await fetch(f.url);
  if (!res.ok) {
    console.error(`[ensure-model] ${f.url} → HTTP ${res.status}`);
    process.exit(1);
  }
  await pipeline(Readable.fromWeb(res.body), createWriteStream(path));
  console.log(`[ensure-model] ${f.name} ready (${statSync(path).size} bytes)`);
}
