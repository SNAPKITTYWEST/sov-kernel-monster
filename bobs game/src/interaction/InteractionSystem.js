import * as THREE from "three";

export class InteractionSystem {
  constructor({ scene, camera, input, store, bus, player, interactables }) {
    this.scene = scene;
    this.camera = camera;
    this.input = input;
    this.store = store;
    this.bus = bus;
    this.player = player;
    this.interactables = interactables;
    this.byId = new Map(interactables.map(item => [item.id, item]));
    this.raycaster = new THREE.Raycaster();
    this.raycaster.far = 3;
    this.lastPrompt = "";
  }

  update() {
    if (this.store.state.mode !== "PLAYING") return this.publish(null);
    if (this.player.sitting) {
      const prompt = `${this.binding()} Stand up`;
      this.publish({ id: "player.stand", enabled: true, prompt });
      if (this.input.consume("INTERACT")) this.player.stand();
      return;
    }
    this.raycaster.setFromCamera({ x: 0, y: 0 }, this.camera);
    const intersections = this.raycaster.intersectObject(this.scene, true);
    let target = null;
    for (const hit of intersections) {
      let visible = true;
      for (let node = hit.object; node; node = node.parent) visible &&= node.visible;
      if (!visible) continue;
      const metadata = this.byId.get(hit.object.userData.entityId);
      if (!metadata || hit.distance > metadata.interactionDistance) break;
      const enabled = metadata.enabled ? metadata.enabled(this.store.state) : true;
      const label = enabled ? metadata.prompt(this.store.state) : metadata.disabledPrompt?.(this.store.state);
      target = { id: metadata.id, enabled, prompt: `${enabled ? this.binding() : ""} ${label || ""}`.trim(), metadata };
      this.raycaster.ray.direction.normalize();
      if (enabled && this.input.consume("INTERACT")) {
        metadata.onInteract({
          direction: this.raycaster.ray.direction.clone(),
          point: hit.point,
          distance: hit.distance,
        });
      }
      break;
    }
    this.publish(target);
  }

  binding() {
    if (this.input.device === "gamepad") return "[X]";
    if (this.input.device === "touch") return "[USE]";
    return "[E]";
  }

  publish(target) {
    const signature = target ? `${target.id}:${target.prompt}:${target.enabled}` : "";
    if (signature === this.lastPrompt) return;
    this.lastPrompt = signature;
    this.store.state.session.targetId = target?.id || null;
    this.bus.emit("INTERACTION_TARGET", target);
  }

  interactById(id) {
    const metadata = this.byId.get(id);
    if (!metadata) return false;
    const enabled = metadata.enabled ? metadata.enabled(this.store.state) : true;
    if (!enabled) return false;
    metadata.onInteract({ direction: new THREE.Vector3(0, 0, -1), point: new THREE.Vector3(), distance: 0 });
    return true;
  }
}
