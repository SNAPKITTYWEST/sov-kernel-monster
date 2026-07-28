/**
 * ISS Telemetry Integration
 * Fetches live ISS position from BOB VOYAGER and renders on Bloch sphere
 * NORAD 25544 · ISS ZARYA
 */

export class ISSTelemetry {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.voyagerUrl = options.voyagerUrl || 'http://localhost:4299';
    this.issMesh = null;
    this.trailPoints = [];
    this.trailGeometry = null;
    this.trailMesh = null;
    this.hudElement = options.hudElement || null;
    this.isLive = false;
    this.lastUpdate = null;
  }

  /**
   * Map lat/lon/alt to Bloch sphere coordinates
   * Normalize satellite position to unit sphere surface
   */
  latLonToBloch(lat, lon, alt) {
    // Convert to radians
    const latRad = (lat * Math.PI) / 180;
    const lonRad = (lon * Math.PI) / 180;

    // Normalize altitude (0-500km) to 0-0.3 sphere offset
    const altNorm = Math.min(alt / 500, 1.0) * 0.3;

    // Map to sphere surface with altitude offset
    const radius = 1.0 + altNorm;
    const x = radius * Math.cos(latRad) * Math.cos(lonRad);
    const y = radius * Math.sin(latRad);
    const z = radius * Math.cos(latRad) * Math.sin(lonRad);

    return { x, y, z };
  }

  /**
   * Create ISS position marker (glowing dot)
   */
  createISSTelemetryMarker() {
    if (this.issMesh) {
      this.scene.remove(this.issMesh);
    }

    // Glowing sphere
    const geo = new THREE.SphereGeometry(0.08, 16, 16);
    const mat = new THREE.MeshPhongMaterial({
      color: 0xff00ff,
      emissive: 0xff00ff,
      emissiveIntensity: 0.8,
      transparent: true,
      opacity: 0.9,
    });
    this.issMesh = new THREE.Mesh(geo, mat);
    this.scene.add(this.issMesh);

    // Glow effect (outer halo)
    const glowGeo = new THREE.SphereGeometry(0.12, 16, 16);
    const glowMat = new THREE.MeshBasicMaterial({
      color: 0xff00ff,
      transparent: true,
      opacity: 0.3,
    });
    const glowMesh = new THREE.Mesh(glowGeo, glowMat);
    this.issMesh.add(glowMesh);
  }

  /**
   * Initialize trail line (orbit path)
   */
  initializeTrail() {
    if (this.trailMesh) {
      this.scene.remove(this.trailMesh);
    }

    this.trailPoints = [];
    this.trailGeometry = new THREE.BufferGeometry();
    const trailMat = new THREE.LineBasicMaterial({
      color: 0xff00ff,
      transparent: true,
      opacity: 0.4,
      linewidth: 1,
    });
    this.trailMesh = new THREE.Line(this.trailGeometry, trailMat);
    this.scene.add(this.trailMesh);
  }

  /**
   * Add position to trail
   */
  addToTrail(pos) {
    this.trailPoints.push(new THREE.Vector3(pos.x, pos.y, pos.z));

    // Keep max 200 trail points
    if (this.trailPoints.length > 200) {
      this.trailPoints.shift();
    }

    if (this.trailGeometry) {
      this.trailGeometry.setFromPoints(this.trailPoints);
    }
  }

  /**
   * Fetch live ISS telemetry from BOB VOYAGER
   */
  async fetchISSTelemetry() {
    try {
      const res = await fetch(`${this.voyagerUrl}/api/telemetry`);
      const data = await res.json();

      if (!data.ok || !data.telemetry) {
        console.error('[ISS] Invalid telemetry response');
        return null;
      }

      return {
        lat: data.telemetry.latitude,
        lon: data.telemetry.longitude,
        alt: data.telemetry.altitude,
        vel: data.telemetry.velocity,
        timestamp: data.telemetry.fetched_at,
        worm: data.worm_head,
      };
    } catch (e) {
      console.error('[ISS] Fetch failed:', e.message);
      return null;
    }
  }

  /**
   * Update ISS position on sphere
   */
  async update() {
    const telemetry = await this.fetchISSTelemetry();
    if (!telemetry) return;

    if (!this.issMesh) {
      this.createISSTelemetryMarker();
      this.initializeTrail();
    }

    // Convert to Bloch sphere coordinates
    const pos = this.latLonToBloch(telemetry.lat, telemetry.lon, telemetry.alt);
    this.issMesh.position.set(pos.x, pos.y, pos.z);

    // Animate glow
    if (this.issMesh.children[0]) {
      this.issMesh.children[0].material.opacity = 0.3 + 0.2 * Math.sin(Date.now() * 0.005);
    }

    // Add to trail
    this.addToTrail(pos);

    // Update HUD
    if (this.hudElement) {
      this.hudElement.innerHTML = `
        <div><span class="label">ISS:</span> <span class="value">${telemetry.lat.toFixed(2)}° ${telemetry.lon.toFixed(2)}°</span></div>
        <div><span class="label">ALT:</span> <span class="value">${telemetry.alt.toFixed(0)}km VEL ${telemetry.vel.toFixed(2)}km/s</span></div>
        <div><span class="label">WORM:</span> <span class="value">${telemetry.worm}</span></div>
      `;
    }

    this.lastUpdate = telemetry;
    this.isLive = true;
  }

  /**
   * Start continuous updates
   */
  startPolling(intervalMs = 4500) {
    console.log('[ISS] Starting telemetry polling at', intervalMs, 'ms interval');
    this.pollingInterval = setInterval(() => this.update(), intervalMs);
    // Do first update immediately
    this.update();
  }

  /**
   * Stop polling
   */
  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
  }

  /**
   * Get last telemetry
   */
  getLastTelemetry() {
    return this.lastUpdate;
  }
}
