#!/usr/bin/env node
// seb_convergence.mjs — Wire universeSum into SEB WORM chain
//
// Every convergence event (problem solved, attack detected) becomes
// a 64-byte payload appended to the SEB lattice chain.
// Negative universeSumDelta = attack event = triggers chain verify + halt.
//
// Payload layout (64 bytes):
//   [0:8]   event_type  (uint64 LE): 0x0400=PROBLEM_SOLVED, 0x0401=ATTACK_DETECTED
//   [8:16]  timestamp   (uint64 LE): Unix nanoseconds
//   [16:48] problem_id  (32 bytes):  SHA256 of problemId string
//   [48:56] delta_bits  (float64 LE): universeSumDelta as IEEE 754
//   [56:64] reserved    (8 bytes):   zeros
//
// The SEB lattice circuit computes:
//   commitment[n] = circuit(commitment[n-1] || payload[n])
// A broken chain (verify returns 0) means tampered history.
// A negative delta payload is a first-class event, not an error.

import { readFileSync, writeFileSync, existsSync, appendFileSync } from 'fs';
import { join, resolve } from 'path';
import { createHash } from 'crypto';

const ROOT      = resolve(import.meta.dirname, '..', '..');
const CONV_LOG  = join(ROOT, '.agentos', 'pnp', 'convergence_log.jsonl');
const CHAIN_LOG = join(ROOT, '.agentos', 'pnp', 'seb_chain.jsonl');  // WORM-sealed records

// Event type codes (match seb_types.ads EventTypeRegistry)
const EVENT_PROBLEM_SOLVED   = 0x0400n;
const EVENT_ATTACK_DETECTED  = 0x0401n;
const EVENT_CHAIN_VERIFY     = 0x0402n;

// Genesis tip (all zeros — matches seb_lattice.c genesis)
let tip = Buffer.alloc(32, 0);

// Load existing chain tip from chain log
if (existsSync(CHAIN_LOG)) {
  const lines = readFileSync(CHAIN_LOG, 'utf8').split('\n').filter(l => l.trim());
  if (lines.length > 0) {
    const last = JSON.parse(lines[lines.length - 1]);
    tip = Buffer.from(last.commitment, 'hex');
  }
}

// GF(256) multiply with AES poly 0x11B — matches seb_lattice.c exactly
function gf256_mul(x, y) {
  let z = 0;
  for (let i = 0; i < 8; i++) {
    if (y & 1) z ^= x;
    const hi = x & 0x80;
    x = (x << 1) & 0xFF;
    if (hi) x ^= 0x1B;
    y >>>= 1;
  }
  return z;
}

// Cyclic convolution in GF(256)[x]/(x^32+1)
function cyclic_convolve(a, b) {
  const c = Buffer.alloc(32);
  for (let k = 0; k < 32; k++) {
    let s = 0;
    for (let i = 0; i < 32; i++) s ^= gf256_mul(a[i], b[(k - i + 32) & 31]);
    c[k] = s;
  }
  return c;
}

// K0=1, K1=x, K2=x^2
const K0 = Buffer.alloc(32); K0[0] = 1;
const K1 = Buffer.alloc(32); K1[1] = 1;
const K2 = Buffer.alloc(32); K2[2] = 1;

// Lattice circuit: next = K0⊗prev XOR K1⊗b XOR K2⊗c
// Since K0=1 (identity): next[k] = prev[k] ^ b[(k-1)&31] ^ c[(k-2)&31]
function circuit(prev32, payload64) {
  const b = payload64.slice(0, 32);
  const c = payload64.slice(32, 64);
  const t0 = cyclic_convolve(K0, prev32);
  const t1 = cyclic_convolve(K1, b);
  const t2 = cyclic_convolve(K2, c);
  const next = Buffer.alloc(32);
  for (let i = 0; i < 32; i++) next[i] = t0[i] ^ t1[i] ^ t2[i];
  return next;
}

// Build 64-byte payload from a convergence event
function buildPayload(entry) {
  const buf = Buffer.alloc(64, 0);

  const delta = entry.universeSumDelta || 0;
  const eventType = delta < 0 ? EVENT_ATTACK_DETECTED : EVENT_PROBLEM_SOLVED;

  // [0:8] event type
  buf.writeBigUInt64LE(eventType, 0);

  // [8:16] timestamp ns
  const ts = BigInt(new Date(entry.timestamp || new Date()).getTime()) * 1_000_000n;
  buf.writeBigUInt64LE(ts, 8);

  // [16:48] SHA256 of problemId (32 bytes)
  const pidHash = createHash('sha256').update(entry.problemId || '').digest();
  pidHash.copy(buf, 16);

  // [48:56] delta as float64 LE
  buf.writeDoubleLE(delta, 48);

  // [56:64] reserved zeros
  return buf;
}

// Append a convergence entry to the SEB WORM chain
function appendToChain(entry) {
  const payload = buildPayload(entry);
  const commitment = circuit(tip, payload);

  const record = {
    n:          existsSync(CHAIN_LOG)
                  ? readFileSync(CHAIN_LOG,'utf8').split('\n').filter(l=>l.trim()).length
                  : 0,
    event:      entry.event,
    problemId:  entry.problemId,
    solver:     entry.solver || null,
    delta:      entry.universeSumDelta || 0,
    timestamp:  entry.timestamp || new Date().toISOString(),
    payload:    payload.toString('hex'),
    commitment: commitment.toString('hex'),
    prev_tip:   tip.toString('hex')
  };

  appendFileSync(CHAIN_LOG, JSON.stringify(record) + '\n');
  tip = commitment;
  return record;
}

// Verify the full chain (re-evaluate circuit from genesis)
function verifyChain() {
  if (!existsSync(CHAIN_LOG)) return { ok: true, count: 0 };
  const lines = readFileSync(CHAIN_LOG, 'utf8').split('\n').filter(l => l.trim());
  let expectedTip = Buffer.alloc(32, 0);
  for (let i = 0; i < lines.length; i++) {
    const rec = JSON.parse(lines[i]);
    const payload = Buffer.from(rec.payload, 'hex');
    const computed = circuit(expectedTip, payload);
    const stored   = Buffer.from(rec.commitment, 'hex');
    if (!computed.equals(stored)) {
      return { ok: false, broken_at: i, expected: computed.toString('hex'), got: stored.toString('hex') };
    }
    expectedTip = computed;
  }
  return { ok: true, count: lines.length, tip: expectedTip.toString('hex') };
}

// Main: read convergence_log, find unsealed entries, seal them
function run() {
  if (!existsSync(CONV_LOG)) {
    console.log('No convergence log. Nothing to seal.');
    return;
  }

  // Load already-sealed record indices
  const sealed = new Set();
  if (existsSync(CHAIN_LOG)) {
    readFileSync(CHAIN_LOG, 'utf8').split('\n').filter(l => l.trim())
      .forEach(l => {
        const r = JSON.parse(l);
        sealed.add(`${r.problemId}:${r.timestamp}`);
      });
  }

  const entries = readFileSync(CONV_LOG, 'utf8').split('\n')
    .filter(l => l.trim()).map(l => JSON.parse(l));

  let appended = 0;
  let attacks  = 0;

  for (const entry of entries) {
    const key = `${entry.problemId}:${entry.timestamp}`;
    if (sealed.has(key)) continue;

    const record = appendToChain(entry);
    appended++;

    const delta = entry.universeSumDelta || 0;
    if (delta < 0) {
      attacks++;
      console.log(`⚠  ATTACK EVENT sealed: ${entry.problemId} delta=${delta}`);
      console.log(`   commitment: ${record.commitment}`);
    } else {
      console.log(`✓  Sealed: ${entry.problemId} delta=+${delta}`);
    }
  }

  if (appended === 0) {
    console.log('Chain up to date. Nothing new to seal.');
  }

  // Always verify chain integrity after sealing
  const result = verifyChain();
  if (!result.ok) {
    console.error(`\n⛔ CHAIN INTEGRITY FAILURE at record ${result.broken_at}`);
    console.error(`   Expected: ${result.expected}`);
    console.error(`   Got:      ${result.got}`);
    console.error('   Chain is tampered. Halting.');
    process.exit(1);
  }

  const universeSum = entries.reduce((s, e) => s + (e.universeSumDelta || 0), 0);
  console.log(`\n🌌 Universe sum:  ${universeSum.toFixed(6)}`);
  console.log(`🔗 Chain records: ${result.count || 0}`);
  console.log(`⚠  Attack events: ${attacks}`);
  console.log(`🔒 Tip:           ${tip.toString('hex').slice(0, 16)}...`);
  console.log(`\n✅ SEB chain: VERIFIED`);

  if (attacks > 0 && universeSum < 0) {
    console.error('\n⛔ NEGATIVE UNIVERSE SUM — active attack condition. Investigate.');
    process.exit(2);
  }
}

run();
