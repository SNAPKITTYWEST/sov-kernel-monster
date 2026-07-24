const encoder = new TextEncoder();

export function canonical(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("Ledger values must be finite");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (typeof value === "object") {
    const entries = Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`);
    return `{${entries.join(",")}}`;
  }
  throw new TypeError(`Unsupported ledger value: ${typeof value}`);
}

export async function sha256(value) {
  const bytes = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

export class Ledger {
  constructor({ receipts = [], hash = sha256 } = {}) {
    this.receipts = structuredClone(receipts);
    this.hash = hash;
  }

  async append(event, durableState) {
    const previousHash = this.receipts.at(-1)?.currentHash || "GENESIS";
    const sequence = this.receipts.length + 1;
    const payloadHash = await this.hash(canonical(event.payload || {}));
    const stateHash = await this.hash(canonical(durableState));
    const core = {
      version: 1,
      sequence,
      eventType: event.type,
      entityId: event.entityId || null,
      playerId: event.playerId || "player.local",
      previousHash,
      payloadHash,
      stateHash,
      timestamp: event.timestamp,
    };
    const receipt = { ...core, payload: structuredClone(event.payload || {}), currentHash: await this.hash(canonical(core)) };
    this.receipts.push(receipt);
    return structuredClone(receipt);
  }

  clone() {
    return structuredClone(this.receipts);
  }

  static async verify(receipts, durableState, hash = sha256) {
    let previousHash = "GENESIS";
    for (let index = 0; index < receipts.length; index++) {
      const receipt = receipts[index];
      if (receipt.sequence !== index + 1 || receipt.previousHash !== previousHash) return false;
      if (await hash(canonical(receipt.payload || {})) !== receipt.payloadHash) return false;
      const core = {
        version: 1,
        sequence: receipt.sequence,
        eventType: receipt.eventType,
        entityId: receipt.entityId ?? null,
        playerId: receipt.playerId || "player.local",
        previousHash: receipt.previousHash,
        payloadHash: receipt.payloadHash,
        stateHash: receipt.stateHash,
        timestamp: receipt.timestamp,
      };
      if (await hash(canonical(core)) !== receipt.currentHash) return false;
      previousHash = receipt.currentHash;
    }
    if (receipts.length && durableState) {
      const expected = await hash(canonical(durableState));
      if (expected !== receipts.at(-1).stateHash) return false;
    }
    return true;
  }
}
