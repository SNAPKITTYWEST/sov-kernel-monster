import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { setupBatchedTrajectories, TrajectoryAnimator } from './TrajectoryRenderer.js';
import { generateDemoTrajectories } from './DemoGenerator.js';

// ═══════════════════════════════════════════════════════════════════
// SCENE SETUP
// ═══════════════════════════════════════════════════════════════════
const container = document.getElementById('canvas-container');
const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x0a0a0f, 0.15);

const camera = new THREE.PerspectiveCamera(
    75,
    window.innerWidth / window.innerHeight,
    0.01,
    100
);
camera.position.set(2.2, 1.8, 2.2);

const renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: true,
    powerPreference: 'high-performance',
});
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
container.appendChild(renderer.domElement);

// Orbit controls — cockpit rotation feel
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.05;
controls.autoRotate = true;
controls.autoRotateSpeed = 0.3;
controls.minDistance = 0.5;
controls.maxDistance = 10;

// ═══════════════════════════════════════════════════════════════════
// REFERENCE FRAME — BLOCH SPHERE
// ═══════════════════════════════════════════════════════════════════
const sphereGeo = new THREE.SphereGeometry(1, 48, 48);
const wireframe = new THREE.WireframeGeometry(sphereGeo);
const sphereMat = new THREE.LineBasicMaterial({
    color: 0x222244,
    transparent: true,
    opacity: 0.12,
});
const sphere = new THREE.LineSegments(wireframe, sphereMat);
scene.add(sphere);

// Axes
const axesGroup = new THREE.Group();
const axisLen = 1.3;
const axisMat = (color) => new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.4 });

function addAxis(dir, color, label) {
    const points = [new THREE.Vector3(0, 0, 0), dir.clone().multiplyScalar(axisLen)];
    const geo = new THREE.BufferGeometry().setFromPoints(points);
    axesGroup.add(new THREE.Line(geo, axisMat(color)));
}
addAxis(new THREE.Vector3(1, 0, 0), 0xff4444, 'X');
addAxis(new THREE.Vector3(0, 1, 0), 0x44ff44, 'Y');
addAxis(new THREE.Vector3(0, 0, 1), 0x4444ff, 'Z');
scene.add(axesGroup);

// Grid ring at equator
const ringGeo = new THREE.RingGeometry(0.99, 1.01, 64);
const ringMat = new THREE.MeshBasicMaterial({
    color: 0x00ffcc,
    transparent: true,
    opacity: 0.08,
    side: THREE.DoubleSide,
});
const ring = new THREE.Mesh(ringGeo, ringMat);
ring.rotation.x = Math.PI / 2;
scene.add(ring);

// Origin marker
const originGeo = new THREE.SphereGeometry(0.02, 16, 16);
const originMat = new THREE.MeshBasicMaterial({ color: 0xffd700 });
const origin = new THREE.Mesh(originGeo, originMat);
scene.add(origin);

// ═══════════════════════════════════════════════════════════════════
// TRAJECTORY STATE
// ═══════════════════════════════════════════════════════════════════
let animator = null;
let trajectoryMaterial = null;

const NUM_TRAJECTORIES = 1000;
const NUM_STEPS = 500;

// ═══════════════════════════════════════════════════════════════════
// HUD UPDATE
// ═══════════════════════════════════════════════════════════════════
const hudTrajectories = document.querySelector('#hud-trajectories .value');
const hudSteps = document.querySelector('#hud-steps .value');
const hudProgress = document.querySelector('#hud-progress .value');
const hudFps = document.querySelector('#hud-fps .value');

let frameCount = 0;
let lastFpsTime = performance.now();
let currentFps = 0;

function updateHUD() {
    if (animator) {
        hudProgress.textContent = `${(animator.progress * 100).toFixed(1)}%`;
    }
    hudFps.textContent = `${currentFps}`;
}

// ═══════════════════════════════════════════════════════════════════
// CONTROLS
// ═══════════════════════════════════════════════════════════════════
document.getElementById('btn-play').addEventListener('click', () => {
    if (animator) animator.play();
});

document.getElementById('btn-pause').addEventListener('click', () => {
    if (animator) animator.pause();
});

document.getElementById('btn-reset').addEventListener('click', () => {
    if (animator) animator.reset();
});

document.getElementById('btn-demo').addEventListener('click', () => {
    loadDemo();
});

document.getElementById('speed-slider').addEventListener('input', (e) => {
    if (animator) {
        let rate = parseInt(e.target.value, 10);
        if (rate % 2 !== 0) rate++;
        animator.setSpeed(rate);
    }
});

document.getElementById('opacity-slider').addEventListener('input', (e) => {
    if (trajectoryMaterial) {
        trajectoryMaterial.opacity = parseInt(e.target.value, 10) / 100;
    }
});

// ═══════════════════════════════════════════════════════════════════
// DEMO LOADER
// ═══════════════════════════════════════════════════════════════════
function loadDemo() {
    // Remove existing trajectory if any
    if (animator) {
        scene.remove(animator.lineSegments);
        animator = null;
    }

    const buffer = generateDemoTrajectories(NUM_TRAJECTORIES, NUM_STEPS, 0.01, 0.3);
    const { lineSegments, maxIndices, material } = setupBatchedTrajectories(
        scene, buffer, NUM_TRAJECTORIES, NUM_STEPS
    );

    trajectoryMaterial = material;
    animator = new TrajectoryAnimator(lineSegments, maxIndices, 6);

    hudTrajectories.textContent = NUM_TRAJECTORIES.toLocaleString();
    hudSteps.textContent = NUM_STEPS.toLocaleString();
}

/**
 * Load trajectory from a binary file URL.
 * Call this when serving real data from the Rust backend.
 */
export async function loadFromBinary(url, numTrajectories, numSteps) {
    if (animator) {
        scene.remove(animator.lineSegments);
        animator = null;
    }

    const response = await fetch(url);
    const buffer = await response.arrayBuffer();
    const { lineSegments, maxIndices, material } = setupBatchedTrajectories(
        scene, buffer, numTrajectories, numSteps
    );

    trajectoryMaterial = material;
    animator = new TrajectoryAnimator(lineSegments, maxIndices, 6);

    hudTrajectories.textContent = numTrajectories.toLocaleString();
    hudSteps.textContent = numSteps.toLocaleString();
}

// Expose for console usage
window.loadFromBinary = loadFromBinary;

// ═══════════════════════════════════════════════════════════════════
// ANIMATION LOOP
// ═══════════════════════════════════════════════════════════════════
function animate() {
    requestAnimationFrame(animate);

    // FPS counter
    frameCount++;
    const now = performance.now();
    if (now - lastFpsTime >= 1000) {
        currentFps = frameCount;
        frameCount = 0;
        lastFpsTime = now;
    }

    // Advance trajectory animation
    if (animator) {
        animator.tick();
    }

    // Slow sphere rotation for ambient feel
    sphere.rotation.y += 0.0005;

    controls.update();
    renderer.render(scene, camera);
    updateHUD();
}

// ═══════════════════════════════════════════════════════════════════
// RESPONSIVE
// ═══════════════════════════════════════════════════════════════════
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// ═══════════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════════
loadDemo();
animate();
