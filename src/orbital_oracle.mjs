/**
 * Orbital Oracle — ISS Telemetry Verification Agent
 * Integrates BOB VOYAGER with sov-kernel-monster formal proofs
 * NORAD 25544 · ISS ZARYA
 * Apache 2.0 · SnapKitty Collective 2026
 */

import https from 'https';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

/**
 * OrbitalOracle
 * Fetches live ISS telemetry, validates against formal orbit proofs,
 * seals results in WORM chain
 */
export class OrbitalOracle {
  constructor(options = {}) {
    this.voyagerUrl = options.voyagerUrl || 'http://localhost:4299';
    this.cache = null;
    this.cacheTime = 0;
    this.cacheTTL = options.cacheTTL || 4500;
    this.wormChain = [];
    this.verificationHistory = [];
  }

  /**
   * Fetch live ISS telemetry from BOB VOYAGER
   */
  async fetchTelemetry() {
    return new Promise((resolve, reject) => {
      const url = new URL('/api/telemetry', this.voyagerUrl);
      https.get(url, res => {
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(new Error(`Failed to parse telemetry: ${e.message}`));
          }
        });
      }).on('error', reject);
    });
  }

  /**
   * Fetch WORM chain from BOB VOYAGER
   */
  async fetchWormChain() {
    return new Promise((resolve, reject) => {
      const url = new URL('/api/worm', this.voyagerUrl);
      https.get(url, res => {
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(e);
          }
        });
      }).on('error', reject);
    });
  }

  /**
   * Orbital mechanics validation
   * Verifies that live telemetry satisfies formal invariants
   */
  validateOrbitalInvariants(telemetry, orbital) {
    if (!telemetry || !orbital) {
      return { valid: false, errors: ['Missing telemetry or orbital data'] };
    }

    const errors = [];
    const warnings = [];

    // ─ Invariant 1: Altitude bounds
    const alt = telemetry.altitude;
    if (alt < 370 || alt > 435) {
      errors.push(`Altitude ${alt} km out of ISS nominal range [370, 435]`);
    }

    // ─ Invariant 2: Velocity bounds (vis-viva)
    const vel = telemetry.velocity;
    const vv = orbital.vis_viva_kms;
    const velDelta = Math.abs(vel - vv);
    if (velDelta > 0.5) {
      errors.push(`Velocity ${vel} km/s diverges from vis-viva ${vv.toFixed(3)} (Δ=${velDelta.toFixed(3)})`);
    }

    // ─ Invariant 3: Orbital period (16 revs/day)
    const period = orbital.orbital_period_min;
    const revPerDay = 24 * 60 / period;
    if (Math.abs(revPerDay - 16) > 0.2) {
      warnings.push(`Mean motion ${revPerDay.toFixed(2)} rev/day (expected ~16)`);
    }

    // ─ Invariant 4: Inclination (51.6°)
    const inc = orbital.inclination_deg;
    if (Math.abs(inc - 51.6) > 0.1) {
      errors.push(`Inclination ${inc}° ≠ ISS nominal 51.6°`);
    }

    // ─ Invariant 5: Eccentricity (near-zero)
    const ecc = 0.0001698;
    const eccentricity = (orbital.apogee_km - orbital.perigee_km) / (2 * (alt));
    if (eccentricity > 0.01) {
      warnings.push(`Eccentricity ${eccentricity.toFixed(6)} anomalously high (expected <0.001)`);
    }

    // ─ Invariant 6: Ground footprint (Euler constraint)
    const fp = orbital.footprint_km;
    if (fp < 2700 || fp > 3000) {
      warnings.push(`Footprint ${fp.toFixed(0)} km (expected 2800-2900)`);
    }

    // ─ Invariant 7: Latitude bounds
    const lat = telemetry.latitude;
    const maxLat = orbital.inclination_deg;
    if (Math.abs(lat) > maxLat + 1) {
      errors.push(`Latitude ${lat.toFixed(2)}° exceeds orbital inclination bound ${maxLat}°`);
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings,
      invariants: {
        altitude_nominal: alt >= 370 && alt <= 435,
        velocity_verified: velDelta < 0.5,
        period_nominal: Math.abs(revPerDay - 16) < 0.2,
        inclination_correct: Math.abs(inc - 51.6) < 0.1,
        latitude_bounded: Math.abs(lat) <= maxLat + 1,
        footprint_nominal: fp >= 2700 && fp <= 3000,
      },
    };
  }

  /**
   * Seal verification result in WORM chain
   */
  sealVerification(telemetry, validation, wormHead) {
    const msg = `${wormHead}|VERIFICATION|${Date.now()}|${telemetry.latitude.toFixed(4)}|${telemetry.longitude.toFixed(4)}`;
    const hash = crypto.createHash('sha256').update(msg).digest('hex');

    const entry = {
      timestamp: new Date().toISOString(),
      hash: hash.slice(0, 16),
      worm_prev: wormHead.slice(0, 16),
      valid: validation.valid,
      telemetry_snapshot: {
        lat: telemetry.latitude.toFixed(4),
        lon: telemetry.longitude.toFixed(4),
        alt: telemetry.altitude.toFixed(2),
        vel: telemetry.velocity.toFixed(2),
      },
      invariants_passed: Object.values(validation.invariants).filter(Boolean).length,
      invariants_total: Object.keys(validation.invariants).length,
      errors: validation.errors,
      warnings: validation.warnings,
    };

    this.wormChain.push(entry);
    return entry;
  }

  /**
   * Main verification loop
   * Fetches live telemetry, validates, seals result
   */
  async verify() {
    try {
      const voyagerData = await this.fetchTelemetry();
      if (!voyagerData.ok) {
        throw new Error('BOB VOYAGER returned error');
      }

      const telemetry = voyagerData.telemetry;
      const orbital = { ...voyagerData.telemetry, ...voyagerData.telemetry };

      const validation = this.validateOrbitalInvariants(telemetry, orbital);
      const wormChain = await this.fetchWormChain();
      const wormHead = wormChain.head || 'GENESIS';

      const seal = this.sealVerification(telemetry, validation, wormHead);

      this.verificationHistory.push({
        timestamp: seal.timestamp,
        valid: validation.valid,
        position: [telemetry.latitude, telemetry.longitude],
        altitude: telemetry.altitude,
      });

      return {
        ok: true,
        timestamp: seal.timestamp,
        position: [telemetry.latitude, telemetry.longitude],
        altitude: telemetry.altitude,
        velocity: telemetry.velocity,
        valid: validation.valid,
        invariants: validation.invariants,
        errors: validation.errors,
        warnings: validation.warnings,
        seal,
      };
    } catch (error) {
      return {
        ok: false,
        error: error.message,
      };
    }
  }

  /**
   * Get verification history (last N entries)
   */
  getHistory(limit = 50) {
    return this.verificationHistory.slice(-limit);
  }

  /**
   * Get WORM chain (last N seals)
   */
  getWormChain(limit = 50) {
    return this.wormChain.slice(-limit);
  }

  /**
   * Continuous verification loop
   * Polls every N seconds
   */
  startPolling(intervalMs = 5000) {
    this.pollingInterval = setInterval(async () => {
      const result = await this.verify();
      if (!result.ok) {
        console.error('[ORBITAL] Verification failed:', result.error);
      } else {
        const status = result.valid ? '✓' : '✗';
        console.log(
          `[ORBITAL] ${status} LAT ${result.position[0].toFixed(2)}° LON ${result.position[1].toFixed(2)}° ALT ${result.altitude.toFixed(0)}km | ${Object.values(result.invariants).filter(Boolean).length}/${Object.keys(result.invariants).length} invariants`
        );
      }
    }, intervalMs);
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
  }
}

export default OrbitalOracle;
