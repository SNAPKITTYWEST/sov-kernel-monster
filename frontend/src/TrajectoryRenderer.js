import * as THREE from 'three';

/**
 * Loads batched trajectory data and sets up indexed LineSegments for parallel animation.
 * Binary file layout: Float32Array of [x,y,z] grouped contiguously per trajectory.
 * [traj₀_step₀(x,y,z), traj₀_step₁(x,y,z), ..., traj₁_step₀(x,y,z), ...]
 *
 * @param {THREE.Scene} scene - Three.js scene to add the mesh to
 * @param {ArrayBuffer} buffer - Raw binary trajectory data
 * @param {number} numTrajectories - Number of simultaneous trajectories
 * @param {number} numSteps - Time steps per trajectory
 * @returns {{lineSegments: THREE.LineSegments, maxIndices: number}}
 */
export function setupBatchedTrajectories(scene, buffer, numTrajectories, numSteps) {
    const positions = new Float32Array(buffer);

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    // Build Index Buffer for LineSegments
    // Each trajectory has (numSteps - 1) segments, each segment = 2 indices
    const totalSegments = numTrajectories * (numSteps - 1);
    const indices = new Uint32Array(totalSegments * 2);

    let indexPtr = 0;
    for (let b = 0; b < numTrajectories; b++) {
        const baseOffset = b * numSteps;
        for (let t = 0; t < numSteps - 1; t++) {
            indices[indexPtr++] = baseOffset + t;
            indices[indexPtr++] = baseOffset + t + 1;
        }
    }

    geometry.setIndex(new THREE.BufferAttribute(indices, 1));

    // Start with zero draw range — nothing visible
    // NOTE: With index buffer, setDrawRange counts INDICES not vertices
    geometry.setDrawRange(0, 0);

    const material = new THREE.LineBasicMaterial({
        color: 0x00ffcc,
        transparent: true,
        opacity: 0.15,
        blending: THREE.AdditiveBlending,
    });

    const lineSegments = new THREE.LineSegments(geometry, material);
    scene.add(lineSegments);

    return { lineSegments, maxIndices: indices.length, material };
}

/**
 * Loads trajectory data from a URL and sets up the renderer.
 */
export async function loadAndSetupBatchedTrajectories(scene, url, numTrajectories, numSteps) {
    const response = await fetch(url);
    const buffer = await response.arrayBuffer();
    return setupBatchedTrajectories(scene, buffer, numTrajectories, numSteps);
}

/**
 * Animation controller for parallel trajectory growth.
 */
export class TrajectoryAnimator {
    constructor(lineSegments, maxIndices, growthRatePerFrame = 6) {
        if (growthRatePerFrame % 2 !== 0) {
            throw new Error('growthRatePerFrame must be even (each line segment = 2 indices)');
        }
        this.lineSegments = lineSegments;
        this.maxIndices = maxIndices;
        this.growthRate = growthRatePerFrame;
        this.currentIndex = 0;
        this.playing = true;
    }

    get progress() {
        return this.maxIndices > 0 ? this.currentIndex / this.maxIndices : 0;
    }

    get complete() {
        return this.currentIndex >= this.maxIndices;
    }

    play() { this.playing = true; }
    pause() { this.playing = false; }

    reset() {
        this.currentIndex = 0;
        this.lineSegments.geometry.setDrawRange(0, 0);
    }

    setSpeed(rate) {
        this.growthRate = rate % 2 === 0 ? rate : rate + 1;
    }

    tick() {
        if (!this.playing || this.complete) return;

        this.currentIndex = Math.min(
            this.currentIndex + this.growthRate,
            this.maxIndices
        );
        this.lineSegments.geometry.setDrawRange(0, this.currentIndex);
    }
}
