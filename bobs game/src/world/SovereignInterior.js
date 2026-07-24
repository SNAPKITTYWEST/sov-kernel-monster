import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { TextureFactory } from "../rendering/TextureFactory.js";

export class SovereignInterior {
  constructor({ scene, renderer, physics, store, bus, commands, animations, audio }) {
    this.scene = scene;
    this.renderer = renderer;
    this.physics = physics;
    this.store = store;
    this.bus = bus;
    this.commands = commands;
    this.animations = animations;
    this.audio = audio;
    this.interactables = [];
    this.textureFactory = new TextureFactory(renderer.renderer);
    this.materials = this.textureFactory.materials();
    this.clock = new THREE.Clock();
    this.doorOpen = false;
    this.lampState = null;
    this.buildArchitecture();
    this.buildLighting();
    this.buildArt();
    this.buildCouch();
    this.buildTables();
    this.buildDiningChairs();
    this.buildFloorLamp();
    this.buildDocument();
    this.buildTerminalAndDoor();
    this.physics.addTrigger({ id: "trigger.exit", position: [3.9, 1.1, 5.45], size: [1.35, 2.2, 0.7] });
    this.unsubscribe = [
      bus.on("STATE_CHANGED", ({ state, event }) => this.applyState(state, event)),
      bus.on("STATE_HYDRATED", ({ state }) => this.applyState(state, { type: "STATE_HYDRATED" })),
      bus.on("TRIGGER_ENTERED", ({ id }) => {
        if (id === "trigger.exit" && this.store.state.world.entities["door.exit"].open) {
          this.commands.execute("MISSION_COMPLETE");
        }
      }),
    ];
    this.applyState(store.state, { type: "BOOT" });
  }

  piece(parent, geometry, material, position, rotation = [0, 0, 0], shadows = true) {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(...position);
    mesh.rotation.set(...rotation);
    mesh.castShadow = shadows;
    mesh.receiveShadow = true;
    parent.add(mesh);
    return mesh;
  }

  box(parent, size, material, position, rotationY = 0, shadows = true) {
    return this.piece(parent, new THREE.BoxGeometry(...size), material, position, [0, rotationY, 0], shadows);
  }

  round(parent, size, radius, material, position, rotation = [0, 0, 0]) {
    return this.piece(parent, new RoundedBoxGeometry(...size, 5, radius), material, position, rotation);
  }

  cylinder(parent, top, bottom, height, material, position, segments = 32) {
    return this.piece(parent, new THREE.CylinderGeometry(top, bottom, height, segments), material, position);
  }

  register(object, metadata) {
    object.name = metadata.name;
    object.traverse(child => {
      if (child.isMesh) child.userData.entityId = metadata.id;
    });
    this.interactables.push({ object, ...metadata });
    return object;
  }

  buildArchitecture() {
    const M = this.materials;
    const floor = this.box(this.scene, [12, 0.18, 10], M.floor, [0, -0.09, 0]);
    floor.name = "Wood floor";
    this.physics.addFixedBox({ position: [0, -0.09, 0], size: [12, 0.18, 10], friction: 0.9 });
    const walls = [
      { position: [0, 2.5, -5], size: [12, 5, 0.18] },
      { position: [-6, 2.5, 0], size: [0.18, 5, 10] },
      { position: [6, 2.5, 0], size: [0.18, 5, 10] },
      { position: [-1.45, 2.5, 5], size: [9.1, 5, 0.18] },
      { position: [5.35, 2.5, 5], size: [1.3, 5, 0.18] },
      { position: [3.9, 3.85, 5], size: [1.6, 2.3, 0.18] },
    ];
    for (const wall of walls) {
      this.box(this.scene, wall.size, M.wall, wall.position, 0, false);
      this.physics.addFixedBox(wall);
    }
    const ceiling = this.box(this.scene, [12, 0.12, 10], M.wall, [0, 5.02, 0], 0, false);
    ceiling.name = "Ceiling";
    this.physics.addFixedBox({ position: [0, 5.02, 0], size: [12, 0.12, 10] });
    this.box(this.scene, [11.8, 0.18, 0.12], M.dark, [0, 0.16, -4.84]);
    this.box(this.scene, [0.12, 0.18, 9.7], M.dark, [-5.84, 0.16, 0]);
    this.box(this.scene, [0.12, 0.18, 9.7], M.dark, [5.84, 0.16, 0]);
    this.box(this.scene, [9, 0.18, 0.12], M.dark, [-1.5, 0.16, 4.84]);
    this.box(this.scene, [1.2, 0.18, 0.12], M.dark, [5.35, 0.16, 4.84]);
    this.box(this.scene, [5.2, 0.06, 3.25], M.rug, [-2.1, 0.08, -1.35]);
  }

  buildLighting() {
    this.scene.add(new THREE.AmbientLight(0xfff6e8, 1.25));
    this.mainLight = new THREE.PointLight(0xffd19a, 105, 16, 2);
    this.mainLight.position.set(0, 4.35, 0.65);
    this.mainLight.castShadow = true;
    const mapSize = this.store.state.settings.shadows === "high" ? 2048 : 1024;
    this.mainLight.shadow.mapSize.set(mapSize, mapSize);
    this.mainLight.shadow.camera.near = 0.2;
    this.mainLight.shadow.camera.far = 15;
    this.mainLight.shadow.bias = -0.0004;
    this.mainLight.shadow.normalBias = 0.025;
    this.scene.add(this.mainLight);
    const pendant = this.cylinder(this.scene, 0.045, 0.045, 0.5, this.materials.dark, [0, 4.76, 0.65], 16);
    pendant.castShadow = false;
    const bulbMaterial = new THREE.MeshStandardMaterial({ color: 0xffd7a0, emissive: 0xffa94c, emissiveIntensity: 2 });
    const bulb = this.piece(this.scene, new THREE.SphereGeometry(0.24, 24, 16), bulbMaterial, [0, 4.43, 0.65]);
    bulb.castShadow = false;
  }

  buildArt() {
    const group = new THREE.Group();
    group.position.set(-2.15, 3.42, -4.77);
    this.scene.add(group);
    this.box(group, [3.2, 1.78, 0.09], this.materials.dark, [0, 0, 0]);
    this.box(group, [2.94, 1.52, 0.06], this.materials.art, [0, 0, 0.09]);
    this.register(group, {
      id: "artwork.seal",
      name: "Sealed Artwork",
      interactionType: "inspect",
      interactionDistance: 2.8,
      prompt: state => state.world.entities["artwork.seal"].inspected ? "Review sealed artwork" : "Inspect sealed artwork",
      onInteract: () => this.commands.execute("INSPECT_ARTWORK"),
    });
  }

  buildCouch() {
    const M = this.materials;
    const couch = new THREE.Group();
    couch.position.set(-2.2, 0, -3.72);
    this.scene.add(couch);
    this.round(couch, [4.7, 0.52, 1.45], 0.14, M.sofa, [0, 0.48, 0]);
    this.round(couch, [4.68, 0.72, 0.4], 0.14, M.sofa, [0, 1.35, -0.58], [-0.09, 0, 0]);
    this.round(couch, [0.5, 1.05, 1.5], 0.16, M.sofa, [-2.18, 0.82, 0.02]);
    this.round(couch, [0.5, 1.05, 1.5], 0.16, M.sofa, [2.18, 0.82, 0.02]);
    for (const x of [-1.43, 0, 1.43]) {
      this.round(couch, [1.32, 0.28, 1.17], 0.11, M.sofa, [x, 0.82, 0.15]);
      this.round(couch, [1.3, 1.03, 0.27], 0.12, M.sofa, [x, 1.43, -0.47], [-0.08, 0, 0]);
    }
    for (const x of [-1.9, 1.9]) {
      for (const z of [-0.45, 0.45]) this.cylinder(couch, 0.08, 0.1, 0.28, M.dark, [x, 0.13, z], 12);
    }
    this.round(couch, [0.72, 0.72, 0.18], 0.1, M.chair, [-1.55, 1.46, -0.24], [0, 0, -0.15]);
    this.round(couch, [0.72, 0.72, 0.18], 0.1, M.chair, [1.5, 1.45, -0.22], [0, 0, 0.12]);
    this.physics.addFixedBox({ position: [-2.2, 0.62, -3.72], size: [4.7, 1.24, 1.45] });
    this.register(couch, {
      id: "couch.main",
      name: "Couch",
      interactionType: "sit",
      interactionDistance: 2.5,
      prompt: () => "Sit on couch",
      onInteract: () => this.commands.execute("USE_COUCH", {
        anchor: {
          position: [-2.2, 0.79, -3.12],
          standPosition: [0.65, 0.79, -2.7],
          yaw: Math.PI,
          pitch: 0,
        },
      }),
    });
  }

  buildTables() {
    const M = this.materials;
    const coffee = new THREE.Group();
    coffee.position.set(-2.1, 0, -1.28);
    this.scene.add(coffee);
    this.cylinder(coffee, 1.18, 1.18, 0.16, M.wood, [0, 0.72, 0], 48);
    for (const x of [-0.65, 0.65]) {
      for (const z of [-0.42, 0.42]) this.cylinder(coffee, 0.09, 0.12, 0.67, M.dark, [x, 0.35, z], 12);
    }
    this.physics.addFixedBox({ position: [-2.1, 0.72, -1.28], size: [2.35, 0.16, 2.35] });

    const dining = new THREE.Group();
    dining.position.set(3.45, 0, -1.62);
    this.scene.add(dining);
    this.box(dining, [2.55, 0.18, 1.45], M.wood, [0, 1.42, 0]);
    for (const x of [-1, 1]) {
      for (const z of [-0.51, 0.51]) this.box(dining, [0.12, 1.35, 0.12], M.dark, [x, 0.7, z]);
    }
    this.physics.addFixedBox({ position: [3.45, 1.42, -1.62], size: [2.55, 0.18, 1.45] });
  }

  buildDiningChairs() {
    this.createChair([2.75, 0.02, -0.12], Math.PI, "chair.dining.01");
    this.createChair([4.15, 0.02, -3.1], 0, "chair.dining.02");
  }

  createChair(position, rotationY, id) {
    const chair = new THREE.Group();
    this.round(chair, [1.02, 0.2, 0.96], 0.08, this.materials.chair, [0, 0.88, 0]);
    this.round(chair, [1.02, 0.95, 0.2], 0.08, this.materials.chair, [0, 1.45, 0.42], [-0.08, 0, 0]);
    for (const x of [-0.38, 0.38]) {
      for (const z of [-0.34, 0.34]) this.box(chair, [0.1, 0.82, 0.1], this.materials.dark, [x, 0.43, z]);
    }
    chair.rotation.y = rotationY;
    this.scene.add(chair);
    const body = this.physics.addDynamicChair(position, chair);
    body.setRotation({ x: 0, y: Math.sin(rotationY / 2), z: 0, w: Math.cos(rotationY / 2) }, true);
    this.register(chair, {
      id,
      name: "Dining Chair",
      interactionType: "push",
      interactionDistance: 2.2,
      prompt: () => "Move chair",
      onInteract: ({ direction }) => this.commands.execute("PUSH_CHAIR", {
        body,
        impulse: { x: direction.x * 2.8, y: 0.18, z: direction.z * 2.8 },
      }),
    });
  }

  buildFloorLamp() {
    const lamp = new THREE.Group();
    lamp.position.set(-5.03, 0, -3.75);
    this.scene.add(lamp);
    this.cylinder(lamp, 0.38, 0.46, 0.12, this.materials.brass, [0, 0.08, 0]);
    this.cylinder(lamp, 0.045, 0.045, 2.75, this.materials.brass, [0, 1.47, 0], 16);
    this.shadeMaterial = new THREE.MeshPhysicalMaterial({
      color: 0xe8c994,
      roughness: 0.6,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.88,
      emissive: 0xffb35c,
      emissiveIntensity: 0.13,
    });
    this.piece(lamp, new THREE.CylinderGeometry(0.35, 0.62, 0.72, 40, 1, true), this.shadeMaterial, [0, 2.76, 0]);
    const glow = new THREE.MeshStandardMaterial({ color: 0xffd49a, emissive: 0xffa43a, emissiveIntensity: 3 });
    this.piece(lamp, new THREE.SphereGeometry(0.1, 20, 12), glow, [0, 2.68, 0]);
    this.floorLight = new THREE.PointLight(0xffb66e, 38, 6, 2);
    this.floorLight.position.set(-5.03, 2.7, -3.75);
    this.scene.add(this.floorLight);
    this.physics.addFixedBox({ position: [-5.03, 1.4, -3.75], size: [0.75, 2.8, 0.75] });
    this.register(lamp, {
      id: "lamp.floor",
      name: "Floor Lamp",
      interactionType: "toggle",
      interactionDistance: 2.5,
      prompt: state => state.world.entities["lamp.floor"].on ? "Turn lamp off" : "Turn lamp on",
      onInteract: () => this.commands.execute("TOGGLE_LAMP"),
    });
  }

  buildDocument() {
    const document = new THREE.Group();
    document.position.set(-2.1, 0.84, -1.28);
    document.rotation.y = -0.2;
    this.scene.add(document);
    this.box(document, [0.72, 0.035, 0.92], this.materials.paper, [0, 0, 0]);
    this.cylinder(document, 0.09, 0.09, 0.018, this.materials.brass, [0.22, 0.03, 0.27], 24);
    this.documentObject = document;
    this.register(document, {
      id: "document.covenant",
      name: "Covenant Fragment",
      interactionType: "collect",
      interactionDistance: 2.25,
      prompt: () => "Collect covenant document",
      onInteract: () => this.commands.execute("COLLECT_DOCUMENT"),
    });
  }

  buildTerminalAndDoor() {
    const terminal = new THREE.Group();
    terminal.position.set(2.58, 1.42, 4.78);
    terminal.rotation.y = Math.PI;
    this.scene.add(terminal);
    this.box(terminal, [0.74, 0.92, 0.18], this.materials.dark, [0, 0, 0]);
    this.terminalScreen = this.box(terminal, [0.58, 0.46, 0.04], this.materials.screen, [0, 0.12, 0.11]);
    this.box(terminal, [0.48, 0.08, 0.07], this.materials.brass, [0, -0.32, 0.12]);
    this.register(terminal, {
      id: "terminal.sovereign",
      name: "Sovereign Terminal",
      interactionType: "activate",
      interactionDistance: 2.45,
      enabled: state => state.world.entities["document.covenant"].verified,
      prompt: state => state.world.entities["terminal.sovereign"].activated ? "Trust chain accepted" : "Activate sovereign terminal",
      disabledPrompt: () => "Terminal awaits verified evidence",
      onInteract: () => this.commands.execute("ACTIVATE_TERMINAL"),
    });

    this.doorPivot = new THREE.Group();
    this.doorPivot.position.set(3.1, 0, 4.84);
    this.scene.add(this.doorPivot);
    const panel = this.box(this.doorPivot, [1.55, 2.68, 0.12], this.materials.door, [0.775, 1.34, 0]);
    this.box(this.doorPivot, [0.09, 0.09, 0.16], this.materials.brass, [1.38, 1.35, -0.1]);
    this.register(this.doorPivot, {
      id: "door.exit",
      name: "Exit Door",
      interactionType: "door",
      interactionDistance: 2.2,
      enabled: state => !state.world.entities["door.exit"].locked && !state.world.entities["door.exit"].open,
      prompt: () => "Open exit door",
      disabledPrompt: state => state.world.entities["door.exit"].open ? "Exit is open" : "Door requires verified covenant",
      onInteract: () => {
        if (!this.store.state.world.entities["door.exit"].open) {
          this.store.dispatch("DOOR_OPENED", { automatic: false }, { entityId: "door.exit" });
        }
      },
    });
    this.doorCollider = this.physics.addFixedBox({ position: [3.875, 1.34, 4.84], size: [1.55, 2.68, 0.18] });
  }

  applyState(state, event) {
    const entities = state.world.entities;
    const lampOn = entities["lamp.floor"].on;
    if (this.floorLight && this.lampState !== lampOn) {
      this.lampState = lampOn;
      const start = this.floorLight.intensity;
      const target = lampOn ? 38 : 0;
      this.animations.to({
        duration: 0.28,
        update: progress => {
          this.floorLight.intensity = THREE.MathUtils.lerp(start, target, progress);
          this.shadeMaterial.emissiveIntensity = THREE.MathUtils.lerp(lampOn ? 0.02 : 0.13, lampOn ? 0.13 : 0.02, progress);
        },
      });
      this.audio.setLamp(lampOn);
    }
    if (this.documentObject) this.documentObject.visible = entities["document.covenant"].present;
    if (this.terminalScreen) {
      this.terminalScreen.material.emissive.setHex(entities["terminal.sovereign"].activated ? 0x5ee6ba : 0x214f45);
      this.terminalScreen.material.emissiveIntensity = entities["terminal.sovereign"].activated ? 2.2 : 1.2;
    }
    if (entities["door.exit"].open && !this.doorOpen) this.openDoor(event.type === "STATE_HYDRATED");
    if (!entities["door.exit"].open && this.doorOpen) this.closeDoor();
  }

  openDoor(instant = false) {
    this.doorOpen = true;
    this.physics.removeCollider(this.doorCollider);
    if (instant) {
      this.doorPivot.rotation.y = Math.PI / 2;
      return;
    }
    const start = this.doorPivot.rotation.y;
    this.cancelDoorAnimation?.();
    this.cancelDoorAnimation = this.animations.to({
      duration: this.store.state.settings.reducedMotion ? 0.01 : 1.05,
      ease: "outCubic",
      update: progress => {
        this.doorPivot.rotation.y = THREE.MathUtils.lerp(start, Math.PI / 2, progress);
      },
      complete: () => this.audio.playTone(520, 0.12, 0.035),
    });
  }

  closeDoor() {
    this.cancelDoorAnimation?.();
    this.cancelDoorAnimation = null;
    this.doorOpen = false;
    this.doorPivot.rotation.y = 0;
    this.doorCollider = this.physics.addFixedBox({ position: [3.875, 1.34, 4.84], size: [1.55, 2.68, 0.18] });
  }

  setShadowQuality(quality) {
    this.mainLight.castShadow = quality !== "off";
    const size = quality === "high" ? 2048 : 1024;
    this.mainLight.shadow.mapSize.set(size, size);
    this.mainLight.shadow.map?.dispose();
    this.mainLight.shadow.map = null;
  }

  update() {
    const time = this.clock.getElapsedTime();
    if (this.store.state.world.entities["lamp.floor"].on) this.floorLight.intensity = 38 + Math.sin(time * 5.2) * 0.35;
    this.mainLight.intensity = 105 + Math.sin(time * 0.9) * 1.2;
  }

  dispose() {
    this.unsubscribe.forEach(dispose => dispose());
    this.textureFactory.dispose();
  }
}
