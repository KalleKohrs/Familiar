// Lädt alle Objekte der genannten Storage-Buckets herunter (Supabase Storage REST-API).
// Aufruf: node download-storage.mjs <zielordner> <bucket> [<bucket> …]
// Umgebung: SUPABASE_URL, SUPABASE_SERVICE_KEY (nur als GitHub-Secret).
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const [target, ...buckets] = process.argv.slice(2);
const base = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_KEY;
if (!target || buckets.length === 0 || !base || !key) {
  console.error("Aufruf: node download-storage.mjs <ziel> <bucket…> mit SUPABASE_URL und SUPABASE_SERVICE_KEY");
  process.exit(1);
}
const headers = { apikey: key, Authorization: `Bearer ${key}` };

async function list(bucket, prefix) {
  const files = [];
  for (let offset = 0; ; offset += 1000) {
    const response = await fetch(`${base}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }),
    });
    if (!response.ok) throw new Error(`list ${bucket}/${prefix}: ${response.status}`);
    const entries = await response.json();
    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      // Ordner haben keine id; deren Inhalt rekursiv lesen.
      if (entry.id === null) files.push(...await list(bucket, path));
      else files.push(path);
    }
    if (entries.length < 1000) return files;
  }
}

let count = 0;
for (const bucket of buckets) {
  for (const path of await list(bucket, "")) {
    const response = await fetch(`${base}/storage/v1/object/${bucket}/${path.split("/").map(encodeURIComponent).join("/")}`, { headers });
    if (!response.ok) throw new Error(`download ${bucket}/${path}: ${response.status}`);
    const file = join(target, bucket, path);
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, Buffer.from(await response.arrayBuffer()));
    count++;
  }
}
console.log(`${count} Dateien gesichert`);
