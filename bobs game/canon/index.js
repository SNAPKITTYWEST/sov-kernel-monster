export const CANON_VERSION = "1.0.0";
export const CANON_ROOT = new URL("./", import.meta.url);
export const MANIFEST_URL = new URL("manifest.json", CANON_ROOT);

export async function loadCanon(readJson = defaultReadJson) {
  const manifest = await readJson(MANIFEST_URL);
  if (manifest.version !== CANON_VERSION) {
    throw new Error(`Unsupported SnapKitty canon version: ${manifest.version}`);
  }
  const entries = await Promise.all(
    Object.entries(manifest.collections).map(async ([name, descriptor]) => [
      name,
      await readJson(new URL(descriptor.path, CANON_ROOT)),
    ]),
  );
  const canon = { manifest, ...Object.fromEntries(entries) };
  const errors = validateCanon(canon);
  if (errors.length) throw new Error(`Invalid SnapKitty canon:\n${errors.join("\n")}`);
  return canon;
}

async function defaultReadJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Canon fetch failed (${response.status}): ${url}`);
  return response.json();
}

export function validateCanon(canon) {
  const errors = [];
  const collectionKeys = ["species", "locations", "experiences", "equipment", "quests", "characters", "bindings"];
  if (canon.manifest?.version !== CANON_VERSION) errors.push("manifest version must match the reader");
  for (const key of collectionKeys) {
    const records = canon[key]?.[key];
    if (!Array.isArray(records)) errors.push(`${key} collection is missing`);
    else if (records.length !== canon.manifest?.collections?.[key]?.count) errors.push(`${key} count does not match manifest`);
  }
  if (!Array.isArray(canon.economy?.nodes)) errors.push("economy nodes are missing");
  else if (canon.economy.nodes.length !== canon.manifest?.collections?.economy?.count) errors.push("economy count does not match manifest");
  return errors;
}
