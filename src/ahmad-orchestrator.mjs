/**
 * Ahmad Orchestrator — Sovereign Event Bus Orchestrator
 * Integrates BOB VOYAGER telemetry + verification + WORM sealing
 * NORAD 25544 · ISS ZARYA
 * Apache 2.0 · SnapKitty Collective 2026
 */

import http from 'http';
import { OrbitalOracle } from './orbital_oracle.mjs';

const PORT = process.env.AHMAD_PORT || 5555;
const VOYAGER_URL = process.env.VOYAGER_URL || 'http://localhost:4299';

const oracle = new OrbitalOracle({ voyagerUrl: VOYAGER_URL });
let orchestrationLog = [];
let eventCount = 0;

/**
 * Ahmad State Machine
 * Tracks verification state and decisions
 */
class AhmadOrchestrator {
  constructor() {
    this.state = 'INIT';
    this.lastVerification = null;
    this.lastDecision = null;
    this.anomalies = [];
    this.startTime = Date.now();
  }

  async verify() {
    const result = await oracle.verify();

    if (!result.ok) {
      this.state = 'ERROR';
      this.lastDecision = { type: 'ERROR', message: result.error };
      return result;
    }

    this.state = 'VERIFIED';
    this.lastVerification = result;

    // Decision logic: if all invariants pass, seal as valid
    if (result.valid && Object.values(result.invariants).every(Boolean)) {
      this.lastDecision = {
        type: 'ACCEPT',
        timestamp: new Date().toISOString(),
        position: result.position,
        altitude: result.altitude,
        invariants_passed: result.invariants_passed,
      };
    } else {
      // Flag anomaly
      this.lastDecision = {
        type: 'ANOMALY',
        timestamp: new Date().toISOString(),
        errors: result.errors,
        warnings: result.warnings,
      };
      this.anomalies.push(this.lastDecision);
    }

    orchestrationLog.push({
      seq: eventCount++,
      timestamp: new Date().toISOString(),
      decision: this.lastDecision,
      verification: result,
    });

    return {
      ok: true,
      verification: result,
      decision: this.lastDecision,
      state: this.state,
    };
  }

  getStatus() {
    return {
      state: this.state,
      uptime_s: Math.floor((Date.now() - this.startTime) / 1000),
      events_processed: eventCount,
      anomalies_detected: this.anomalies.length,
      last_verification: this.lastVerification,
      last_decision: this.lastDecision,
    };
  }

  getLog(limit = 50) {
    return orchestrationLog.slice(-limit);
  }

  getAnomalies(limit = 50) {
    return this.anomalies.slice(-limit);
  }
}

const ahmad = new AhmadOrchestrator();

/**
 * HTTP Server — Ahmad Orchestrator API
 */
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

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204);
    res.end();
    return;
  }

  const url = req.url.split('?')[0];

  // ─ GET /status — Current orchestrator state
  if (url === '/status') {
    json(res, ahmad.getStatus());
    return;
  }

  // ─ POST /verify — Run verification cycle
  if (url === '/verify' && req.method === 'POST') {
    const result = await ahmad.verify();
    json(res, result, result.ok ? 200 : 400);
    return;
  }

  // ─ GET /log — Orchestration log
  if (url === '/log') {
    const limit = parseInt(new URL(`http://localhost${req.url}`).searchParams.get('limit') || 50);
    json(res, {
      ok: true,
      count: orchestrationLog.length,
      entries: ahmad.getLog(limit),
    });
    return;
  }

  // ─ GET /anomalies — Detected anomalies
  if (url === '/anomalies') {
    json(res, {
      ok: true,
      count: ahmad.anomalies.length,
      anomalies: ahmad.getAnomalies(),
    });
    return;
  }

  // ─ GET /health — Service health
  if (url === '/health') {
    json(res, {
      ok: true,
      service: 'ahmad-orchestrator',
      version: '1.0.0',
      state: ahmad.state,
      uptime_s: Math.floor((Date.now() - ahmad.startTime) / 1000),
      events_total: eventCount,
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
║  Ahmad Orchestrator v1.0                   ║
║  Sovereign Event Bus Orchestrator           ║
║  NORAD 25544 · ISS ZARYA                   ║
║  http://localhost:${PORT}                      ║
║  Apache 2.0 · SnapKitty Collective 2026    ║
╚════════════════════════════════════════════╝

  API endpoints:
    GET  /status               orchestrator state + last decision
    POST /verify               run verification cycle
    GET  /log?limit=50         orchestration log
    GET  /anomalies            detected anomalies
    GET  /health               service health
`);

server.listen(PORT, () => {
  console.log(`Ahmad Orchestrator listening on port ${PORT}`);
});

// ─ Polling loop: verify every 5 seconds
console.log('Starting orbital verification loop (5s interval)...\n');
setInterval(async () => {
  const result = await ahmad.verify();
  if (result.ok) {
    const status = result.decision.type === 'ACCEPT' ? '✓' : '✗';
    console.log(
      `[AHMAD] ${status} LAT ${result.verification.position[0].toFixed(2)}° ALT ${result.verification.altitude.toFixed(0)}km | ${result.decision.type}`
    );
  } else {
    console.error(`[AHMAD] ERROR: ${result.error}`);
  }
}, 5000);
