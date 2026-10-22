// Backblaze-B2-API v4 (native), nur was die Datensicherung braucht. Identische Kopie in
// backup/b2.ts. Doku: backblaze.com/apidocs (b2_authorize_account, b2_get_upload_url,
// b2_upload_file, b2_hide_file, b2_download_file_by_name, b2_list_file_names).
// Der Anwendungsschlüssel ist auf genau einen Bucket beschränkt; dessen ID und Name liefert
// b2_authorize_account in apiInfo.storageApi.allowed.buckets.

export interface B2 {
  apiUrl: string;
  downloadUrl: string;
  token: string;
  bucketId: string;
  bucketName: string;
  capabilities: string[];
  upload?: { url: string; token: string };
}

// Dateinamen prozentkodiert, Schrägstriche bleiben (b2_upload_file: X-Bz-File-Name).
export function encodeName(name: string): string {
  return name.split("/").map(encodeURIComponent).join("/");
}

async function check(response: Response, what: string): Promise<Response> {
  if (response.ok) return response;
  let detail = "";
  try {
    const body = await response.json();
    detail = `${body.code ?? ""} ${body.message ?? ""}`.trim();
  } catch {
    // kein JSON
  }
  throw new Error(`B2 ${what}: ${response.status} ${detail}`.trim());
}

export async function authorize(keyId: string, applicationKey: string): Promise<B2> {
  const response = await check(
    await fetch("https://api.backblazeb2.com/b2api/v4/b2_authorize_account", {
      headers: { Authorization: `Basic ${btoa(`${keyId}:${applicationKey}`)}` },
    }),
    "Anmeldung",
  );
  const body = await response.json();
  const api = body.apiInfo.storageApi;
  const buckets = (api.allowed?.buckets ?? []).filter((b: { id?: string; name?: string }) => b.id && b.name);
  if (buckets.length !== 1) {
    throw new Error("B2-Schlüssel muss auf genau einen Bucket beschränkt sein.");
  }
  return {
    apiUrl: api.apiUrl,
    downloadUrl: api.downloadUrl,
    token: body.authorizationToken,
    bucketId: buckets[0].id,
    bucketName: buckets[0].name,
    capabilities: api.allowed?.capabilities ?? [],
  };
}

async function call(b2: B2, operation: string, payload: unknown): Promise<Response> {
  return await fetch(`${b2.apiUrl}/b2api/v4/${operation}`, {
    method: "POST",
    headers: { Authorization: b2.token, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

async function sha1Hex(data: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function upload(b2: B2, name: string, data: Uint8Array): Promise<void> {
  const sha1 = await sha1Hex(data);
  // Laut Doku bei 401 (Token abgelaufen) oder 503 eine neue Upload-URL holen und erneut senden.
  for (let attempt = 0; attempt < 3; attempt++) {
    if (!b2.upload) {
      const response = await check(await call(b2, "b2_get_upload_url", { bucketId: b2.bucketId }), "Upload-URL");
      const body = await response.json();
      b2.upload = { url: body.uploadUrl, token: body.authorizationToken };
    }
    const response = await fetch(b2.upload.url, {
      method: "POST",
      headers: {
        Authorization: b2.upload.token,
        "X-Bz-File-Name": encodeName(name),
        "Content-Type": "application/octet-stream",
        "X-Bz-Content-Sha1": sha1,
      },
      body: data,
    });
    if (response.ok) return;
    if (response.status === 401 || response.status === 503 || response.status === 408) {
      b2.upload = undefined;
      continue;
    }
    await check(response, `Upload ${name}`);
  }
  throw new Error(`B2 Upload ${name}: nach drei Versuchen fehlgeschlagen`);
}

// Verbirgt die aktuelle Version; die Lebenszyklus-Regel löscht verborgene Versionen nach 30 Tagen.
export async function hide(b2: B2, name: string): Promise<void> {
  const response = await call(b2, "b2_hide_file", { bucketId: b2.bucketId, fileName: name });
  if (response.ok) return;
  if (response.status === 400 || response.status === 404) {
    const body = await response.clone().json().catch(() => ({}));
    if (body.code === "already_hidden" || body.code === "no_such_file" || body.code === "not_found") return;
  }
  await check(response, `Verbergen ${name}`);
}

export async function download(b2: B2, name: string): Promise<Uint8Array> {
  const response = await check(
    await fetch(`${b2.downloadUrl}/file/${encodeURIComponent(b2.bucketName)}/${encodeName(name)}`, {
      headers: { Authorization: b2.token },
    }),
    `Download ${name}`,
  );
  return new Uint8Array(await response.arrayBuffer());
}

// Aktuelle (nicht verborgene) Dateien unter prefix, ab startFileName (einschließlich).
export async function listNames(
  b2: B2,
  prefix: string,
  startFileName: string | null,
  max = 1000,
): Promise<{ names: string[]; next: string | null }> {
  const response = await check(
    await call(b2, "b2_list_file_names", {
      bucketId: b2.bucketId,
      prefix,
      startFileName: startFileName ?? undefined,
      maxFileCount: max,
    }),
    "Dateiliste",
  );
  const body = await response.json();
  return {
    names: (body.files ?? []).filter((f: { action: string }) => f.action === "upload").map((f: { fileName: string }) => f.fileName),
    next: body.nextFileName ?? null,
  };
}
