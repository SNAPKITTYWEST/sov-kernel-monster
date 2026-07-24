import * as THREE from "three";

export class Renderer {
  constructor(container, settings) {
    this.container = container;
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0xd8d2c8);
    this.scene.fog = new THREE.Fog(0xd8d2c8, 15, 25);
    this.camera = new THREE.PerspectiveCamera(settings.fov, innerWidth / innerHeight, 0.05, 45);
    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.12;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.container.append(this.renderer.domElement);
    this.frameAverage = 1 / 60;
    this.quality = settings.shadows;
    this.setQuality(settings.shadows);
    this.resize();
    this.onResize = () => this.resize();
    addEventListener("resize", this.onResize);
  }

  setQuality(quality) {
    this.quality = quality;
    this.renderer.shadowMap.enabled = quality !== "off";
    const cap = quality === "high" ? 2 : 1.35;
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, cap));
    this.resize();
  }

  setFov(value) {
    this.camera.fov = value;
    this.camera.updateProjectionMatrix();
  }

  resize() {
    const width = this.container.clientWidth || innerWidth;
    const height = this.container.clientHeight || innerHeight;
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height, false);
  }

  monitor(delta) {
    this.frameAverage += (delta - this.frameAverage) * 0.025;
    if (this.frameAverage > 1 / 34 && this.renderer.getPixelRatio() > 1.05) {
      this.renderer.setPixelRatio(Math.max(1, this.renderer.getPixelRatio() - 0.15));
      this.resize();
      this.frameAverage = 1 / 60;
    }
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    removeEventListener("resize", this.onResize);
    this.renderer.dispose();
  }
}
