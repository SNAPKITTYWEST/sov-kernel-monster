/**
 * Verification Server — Orbital Invariant Oracle
 * Integrates BOB VOYAGER, sov-kernel-monster proofs, Ahmad Bot orchestration
 * NORAD 25544 · ISS ZARYA
 * Apache 2.0 · SnapKitty Collective 2026
 */

import http from 'http';
import crypto from 'crypto';
import { OrbitalOracle } from './orbital_oracle.mjs';

const PORT = process.env.PORT || 3333;
const VOYAGER_URL = process.env.VOYAGER_URL || 'http://localhost:4299';

/**
 * Verification Server
 * Accepts telemetry from BOB VOYAGER, validates against formal proofs
 */
const oracle = new OrbitalOracle({ voyagerUrl: VOYAGER_URL });
let wormChain = [];
let verificationCount = 0;

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function json(res, data, status = 200) {
  cors(res);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data, null, 2));
}

/**
 * Verify orbital telemetry against formal invariants
 */
function verifyTelemetry(telemetry) {
  if (!telemetry || typeof telemetry !== 'object') {
    return { ok: false, error: 'Invalid telemetry payload' };
  }

  const validation = oracle.validateOrbitalInvariants(telemetry, telemetry);

  // Create WORM seal
  const msg = `${wormChain.length}|VERIFICATION|${Date.now()}|${telemetry.latitude.toFixed(4)}|${telemetry.longitude.toFixed(4)}`;
  const hash = crypto.createHash('sha256').update(msg).digest('hex');
  const seal = {
    seq: wormChain.length,
    hash: hash.slice(0, 16),
    full_hash: hash,
    timestamp: new Date().toISOString(),
    valid: validation.valid,
    position: {
      lat: telemetry.latitude,
      lon: telemetry.longitude,
      alt: telemetry.altitude,
    },
  };

  wormChain.push(seal);
  verificationCount++;

  return {
    ok: true,
    timestamp: new Date().toISOString(),
    position: [telemetry.latitude, telemetry.longitude],
    altitude: telemetry.altitude,
    velocity: telemetry.velocity,
    valid: validation.valid,
    invariants: validation.invariants,
    invariants_passed: Object.values(validation.invariants).filter(Boolean).length,
    invariants_total: Object.keys(validation.invariants).length,
    errors: validation.errors,
    warnings: validation.warnings,
    seal: {
      hash: seal.hash,
      full_hash: seal.full_hash,
    },
  };
}

/**
 * HTTP Server
 */
const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204);
    res.end();
    return;
  }

  const url = req.url.split('?')[0];

  // ─ POST /verify — Verify telemetry payload
  if (url === '/verify' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        const result = verifyTelemetry(payload.telemetry);
        json(res, result, result.ok ? 200 : 400);
      } catch (e) {
        json(res, { ok: false, error: e.message }, 400);
      }
    });
    return;
  }

  // ─ GET /worm — Last N WORM seals
  if (url === '/worm') {
    json(res, {
      ok: true,
      count: wormChain.length,
      entries: wormChain.slice(-50),
    });
    return;
  }

  // ─ GET /history — Verification history
  if (url === '/history') {
    const limit = parseInt(new URL(`http://localhost${req.url}`).searchParams.get('limit') || 100);
    json(res, {
      ok: true,
      count: oracle.verificationHistory.length,
      history: oracle.verificationHistory.slice(-limit),
    });
    return;
  }

  // ─ GET /health — Service status
  if (url === '/health') {
    json(res, {
      ok: true,
      service: 'verification-server',
      version: '1.0.0',
      norad: 25544,
      verifications_total: verificationCount,
      worm_count: wormChain.length,
      uptime_s: process.uptime().toFixed(0),
    });
    return;
  }

  // ─ GET /live — Live verification status
  if (url === '/live') {
    const latest = oracle.verificationHistory[oracle.verificationHistory.length - 1];
    json(res, {
      ok: true,
      latest_verification: latest || null,
      worm_count: wormChain.length,
      verification_count: verificationCount,
    });
    return;
  }

  cors(res);
  res.writeHead(404);
  res.end('Not found');
});

// ─ Boot
console.log(`
╔════════════════════════════════════════════╗
║  Verification Server v1.0                  ║
║  Orbital Invariant Oracle                  ║
║  NORAD 25544 · ISS ZARYA                   ║
║  http://localhost:${PORT}                      ║
║  Apache 2.0 · SnapKitty Collective 2026    ║
╚════════════════════════════════════════════╝

  API endpoints:
    POST /verify               verify telemetry payload
    GET  /worm                 last 50 WORM seals
    GET  /history?limit=100    verification history
    GET  /live                 latest verification
    GET  /health               service status
`);

server.listen(PORT, () => {
  console.log(`Verification server listening on port ${PORT}`);
});
