import test from "node:test";
import assert from "node:assert/strict";
import { Ledger, canonical, sha256 } from "../src/core/Ledger.js";

test("canonical JSON sorts nested object keys", () => {
  assert.equal(
    canonical({ z: 1, a: { y: 2, b: [3, { q: true, a: false }] } }),
    '{"a":{"b":[3,{"a":false,"q":true}],"y":2},"z":1}',
  );
});

test("ledger seals payload, durable state, and predecessor", async () => {
  const ledger = new Ledger();
  const firstState = { world: { lamp: false } };
  const secondState = { world: { lamp: false, document: "collected" } };
  await ledger.append(
    { type: "LAMP_DEACTIVATED", payload: { on: false }, entityId: "lamp.floor", timestamp: "2026-07-23T00:00:00.000Z" },
    firstState,
  );
  await ledger.append(
    { type: "DOCUMENT_COLLECTED", payload: { id: "fragment" }, entityId: "document.covenant", timestamp: "2026-07-23T00:00:01.000Z" },
    secondState,
  );

  const receipts = ledger.clone();
  assert.equal(receipts[1].previousHash, receipts[0].currentHash);
  assert.equal(await Ledger.verify(receipts, secondState), true);

  const tamperedPayload = structuredClone(receipts);
  tamperedPayload[0].payload.on = true;
  assert.equal(await Ledger.verify(tamperedPayload, secondState), false);

  const tamperedState = { world: { lamp: true, document: "collected" } };
  assert.equal(await Ledger.verify(receipts, tamperedState), false);
});

test("identical events and states create identical seals", async () => {
  const event = { type: "ARTWORK_INSPECTED", payload: { witness: 1 }, entityId: "artwork.seal", timestamp: "2026-07-23T00:00:00.000Z" };
  const state = { artwork: { inspected: true } };
  const first = new Ledger();
  const second = new Ledger();
  await first.append(event, state);
  await second.append(event, state);
  assert.equal(first.receipts[0].currentHash, second.receipts[0].currentHash);
  assert.equal(first.receipts[0].payloadHash, await sha256(canonical(event.payload)));
});
