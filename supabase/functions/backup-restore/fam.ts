// Dateiformat der Datensicherung (ADR 0009). Identische Kopie in backup/fam.ts.
//
//   "FAM1" | Länge des verschlüsselten Schlüssels (uint16, big endian) | verschlüsselter Schlüssel
//   | IV (12 Byte) | Daten mit AES-256-GCM verschlüsselt (inkl. 16-Byte-Prüfzeichen)
//
// Je Datei ein zufälliger AES-Schlüssel; dieser ist mit RSA-OAEP (SHA-256) für den öffentlichen
// Sicherungsschlüssel verschlüsselt. Die Kopfzeile ist als Zusatzdaten (AAD) an das GCM-Prüfzeichen
// gebunden, jede Veränderung der Datei fällt beim Öffnen auf.

const MAGIC = new TextEncoder().encode("FAM1");
const RSA = { name: "RSA-OAEP", hash: "SHA-256" } as const;

// PEM aus einem Secret lesen; Zeilenumbrüche können beim Einfügen ins Dashboard verloren gehen
// oder als „\n“ ankommen.
function pemBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----(BEGIN|END)[^-]*-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export function importPublicKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", pemBytes(pem), RSA, false, ["encrypt"]);
}

export function importPrivateKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", pemBytes(pem), RSA, false, ["decrypt"]);
}

export async function seal(data: Uint8Array, publicKey: CryptoKey): Promise<Uint8Array> {
  const aesKey = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt"]);
  const wrapped = new Uint8Array(
    await crypto.subtle.encrypt(RSA, publicKey, await crypto.subtle.exportKey("raw", aesKey)),
  );
  const header = new Uint8Array(MAGIC.length + 2 + wrapped.length);
  header.set(MAGIC, 0);
  new DataView(header.buffer).setUint16(MAGIC.length, wrapped.length);
  header.set(wrapped, MAGIC.length + 2);

  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: header }, aesKey, data),
  );

  const out = new Uint8Array(header.length + iv.length + cipher.length);
  out.set(header, 0);
  out.set(iv, header.length);
  out.set(cipher, header.length + iv.length);
  return out;
}

export async function open(file: Uint8Array, privateKey: CryptoKey): Promise<Uint8Array> {
  if (file.length < MAGIC.length + 2 || MAGIC.some((b, i) => file[i] !== b)) {
    throw new Error("Keine Familiar-Sicherungsdatei (FAM1).");
  }
  const keyLength = new DataView(file.buffer, file.byteOffset).getUint16(MAGIC.length);
  const headerEnd = MAGIC.length + 2 + keyLength;
  const header = file.subarray(0, headerEnd);
  const raw = await crypto.subtle.decrypt(RSA, privateKey, file.subarray(MAGIC.length + 2, headerEnd));
  const aesKey = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["decrypt"]);
  const iv = file.subarray(headerEnd, headerEnd + 12);
  return new Uint8Array(
    await crypto.subtle.decrypt({ name: "AES-GCM", iv, additionalData: header }, aesKey, file.subarray(headerEnd + 12)),
  );
}

export async function gzip(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

export async function gunzip(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
