import * as THREE from "three";

export class TextureFactory {
  constructor(renderer, seed = 8437) {
    this.renderer = renderer;
    this.seed = seed;
    this.textures = [];
  }

  random() {
    this.seed = this.seed * 16807 % 2147483647;
    return (this.seed - 1) / 2147483646;
  }

  create(kind, repeatX = 1, repeatY = 1) {
    const canvas = Object.assign(document.createElement("canvas"), { width: 512, height: 512 });
    const context = canvas.getContext("2d");
    const base = {
      wood: "#855637",
      plaster: "#e7e2d9",
      fabric: "#d2d1ca",
      rug: "#cdbb97",
      art: "#eee6d7",
      paper: "#e9dfc9",
      screen: "#142c28",
    }[kind];
    context.fillStyle = base;
    context.fillRect(0, 0, 512, 512);

    if (kind === "wood") this.drawWood(context);
    if (kind === "plaster") this.drawPlaster(context);
    if (kind === "fabric") this.drawFabric(context);
    if (kind === "rug") this.drawRug(context);
    if (kind === "art") this.drawArt(context);
    if (kind === "paper") this.drawPaper(context);
    if (kind === "screen") this.drawScreen(context);

    const texture = new THREE.CanvasTexture(canvas);
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    texture.repeat.set(repeatX, repeatY);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = Math.min(8, this.renderer.capabilities.getMaxAnisotropy());
    this.textures.push(texture);
    return texture;
  }

  drawWood(context) {
    for (let y = 0; y < 512; y += 64) {
      context.fillStyle = `rgba(55,24,10,${0.035 + (y / 64 % 2) * 0.025})`;
      context.fillRect(0, y, 512, 64);
      context.strokeStyle = "rgba(38,17,8,.25)";
      context.lineWidth = 2;
      context.beginPath();
      context.moveTo(0, y);
      context.lineTo(512, y);
      context.stroke();
      for (let line = 0; line < 9; line++) {
        context.strokeStyle = `rgba(255,220,170,${0.025 + this.random() * 0.04})`;
        context.beginPath();
        context.moveTo(0, y + 5 + line * 6);
        for (let x = 0; x <= 512; x += 16) {
          context.lineTo(x, y + 5 + line * 6 + Math.sin((x + line * 31) * 0.035) * 2);
        }
        context.stroke();
      }
    }
  }

  drawPlaster(context) {
    for (let index = 0; index < 7000; index++) {
      const value = this.random() > 0.5 ? 255 : 60;
      context.fillStyle = `rgba(${value},${value},${value},${this.random() * 0.035})`;
      context.fillRect(this.random() * 512, this.random() * 512, 1 + this.random() * 2, 1 + this.random() * 2);
    }
  }

  drawFabric(context) {
    context.strokeStyle = "rgba(35,35,30,.12)";
    for (let index = 0; index < 512; index += 5) {
      context.beginPath();
      context.moveTo(index, 0);
      context.lineTo(index, 512);
      context.stroke();
      context.beginPath();
      context.moveTo(0, index);
      context.lineTo(512, index);
      context.stroke();
    }
  }

  drawRug(context) {
    context.strokeStyle = "#315d58";
    context.lineWidth = 20;
    context.strokeRect(28, 28, 456, 456);
    context.strokeStyle = "#a7573f";
    context.lineWidth = 7;
    context.strokeRect(55, 55, 402, 402);
    for (let index = 0; index < 5; index++) {
      context.save();
      context.translate(106 + index * 75, 256);
      context.rotate(Math.PI / 4);
      context.fillStyle = index % 2 ? "#315d58" : "#a7573f";
      context.fillRect(-31, -31, 62, 62);
      context.restore();
    }
  }

  drawArt(context) {
    context.fillStyle = "#315d58";
    context.fillRect(42, 52, 146, 365);
    context.fillStyle = "#b85f42";
    context.beginPath();
    context.arc(327, 172, 105, 0, Math.PI * 2);
    context.fill();
    context.fillStyle = "#d5aa58";
    context.fillRect(255, 276, 200, 92);
    context.fillStyle = "#292925";
    context.fillRect(205, 85, 32, 330);
  }

  drawPaper(context) {
    context.strokeStyle = "rgba(97,65,33,.18)";
    context.lineWidth = 2;
    for (let y = 90; y < 450; y += 46) {
      context.beginPath();
      context.moveTo(55, y);
      context.lineTo(457, y);
      context.stroke();
    }
    context.strokeStyle = "#a75d3b";
    context.lineWidth = 18;
    context.strokeRect(28, 28, 456, 456);
    context.fillStyle = "#315d58";
    context.fillRect(380, 365, 74, 74);
  }

  drawScreen(context) {
    context.strokeStyle = "rgba(111,217,188,.22)";
    context.lineWidth = 2;
    for (let y = 18; y < 512; y += 18) {
      context.beginPath();
      context.moveTo(0, y);
      context.lineTo(512, y);
      context.stroke();
    }
    context.fillStyle = "#78c9b4";
    context.font = "700 92px system-ui";
    context.textAlign = "center";
    context.fillText("SOV", 256, 290);
    context.font = "600 24px monospace";
    context.fillText("CHAIN AWAITS", 256, 340);
  }

  materials() {
    const plaster = this.create("plaster", 4, 2);
    const floor = this.create("wood", 5, 4);
    const wood = this.create("wood", 2, 2);
    const weave = this.create("fabric", 4, 4);
    const rugBump = this.create("fabric", 8, 8);
    return {
      wall: new THREE.MeshStandardMaterial({ color: 0xf3eee6, map: plaster, bumpMap: plaster, bumpScale: 0.018, roughness: 0.94 }),
      floor: new THREE.MeshStandardMaterial({ map: floor, bumpMap: floor, bumpScale: 0.035, roughness: 0.58 }),
      wood: new THREE.MeshStandardMaterial({ map: wood, bumpMap: wood, bumpScale: 0.025, roughness: 0.48 }),
      sofa: new THREE.MeshStandardMaterial({ color: 0x3d6962, map: weave, bumpMap: weave, bumpScale: 0.018, roughness: 0.9 }),
      chair: new THREE.MeshStandardMaterial({ color: 0xac674a, map: weave, bumpMap: weave, bumpScale: 0.015, roughness: 0.85 }),
      dark: new THREE.MeshStandardMaterial({ color: 0x292824, roughness: 0.52 }),
      brass: new THREE.MeshStandardMaterial({ color: 0xb38a52, metalness: 0.78, roughness: 0.24 }),
      rug: new THREE.MeshStandardMaterial({ map: this.create("rug"), bumpMap: rugBump, bumpScale: 0.025, roughness: 0.96 }),
      art: new THREE.MeshStandardMaterial({ map: this.create("art"), roughness: 0.72 }),
      paper: new THREE.MeshStandardMaterial({ map: this.create("paper"), roughness: 0.8 }),
      screen: new THREE.MeshStandardMaterial({ map: this.create("screen"), color: 0x7be0c3, emissive: 0x214f45, emissiveIntensity: 1.2, roughness: 0.5 }),
      door: new THREE.MeshStandardMaterial({ map: this.create("wood", 1, 2), color: 0x7c4d31, roughness: 0.46 }),
    };
  }

  dispose() {
    this.textures.forEach(texture => texture.dispose());
  }
}
