import * as THREE from "three";

export class PlayerController {
  constructor({ scene, camera, physics, input, store, bus, audio }) {
    this.scene = scene;
    this.camera = camera;
    this.physics = physics;
    this.input = input;
    this.store = store;
    this.bus = bus;
    this.audio = audio;
    this.rig = new THREE.Group();
    this.pitchRig = new THREE.Group();
    this.rig.add(this.pitchRig);
    this.pitchRig.add(camera);
    this.scene.add(this.rig);
    const pose = store.state.player.pose;
    const player = physics.createPlayer(pose.position);
    this.body = player.body;
    this.collider = player.collider;
    this.controller = player.controller;
    this.yaw = pose.yaw;
    this.pitch = pose.pitch;
    this.verticalVelocity = 0;
    this.horizontalVelocity = new THREE.Vector3();
    this.forward = new THREE.Vector3();
    this.right = new THREE.Vector3();
    this.grounded = false;
    this.crouched = false;
    this.sitting = false;
    this.seatAnchor = null;
    this.sprinting = false;
    this.moving = false;
    this.bobPhase = 0;
    this.lastStep = 0;
    this.baseFov = store.state.settings.fov;
    this.bus.on("PLAYER_SIT_REQUESTED", ({ anchor }) => this.sit(anchor));
    this.afterPhysics(0);
  }

  applyLook(delta) {
    if (this.sitting) return;
    const look = this.input.consumeLook(delta);
    const sensitivity = 0.0021 * this.store.state.settings.sensitivity;
    this.yaw -= look.x * sensitivity;
    const direction = this.store.state.settings.invertY ? 1 : -1;
    this.pitch += look.y * sensitivity * direction;
    this.pitch = THREE.MathUtils.clamp(this.pitch, -Math.PI * 0.47, Math.PI * 0.47);
  }

  fixedUpdate(delta) {
    if (this.sitting) return;
    if (this.input.consume("CROUCH")) this.setCrouched(!this.crouched);
    if (this.input.consume("JUMP") && this.grounded) {
      this.verticalVelocity = 4.65;
      this.grounded = false;
      this.audio.playTone(115, 0.07, 0.018);
    }
    const move = this.input.movement();
    this.moving = Math.hypot(move.x, move.y) > 0.05;
    this.sprinting = this.input.isHeld("SPRINT") && move.y > 0.1 && !this.crouched;
    const speed = this.crouched ? 1.45 : this.sprinting ? 4.8 : 2.75;
    this.forward.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    this.right.set(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    const target = this.forward.multiplyScalar(move.y).add(this.right.multiplyScalar(move.x)).multiplyScalar(speed);
    const response = 1 - Math.exp(-(this.grounded ? 15 : 5) * delta);
    this.horizontalVelocity.x = THREE.MathUtils.lerp(this.horizontalVelocity.x, target.x, response);
    this.horizontalVelocity.z = THREE.MathUtils.lerp(this.horizontalVelocity.z, target.z, response);
    this.verticalVelocity += -9.81 * delta;

    this.controller.computeColliderMovement(this.collider, {
      x: this.horizontalVelocity.x * delta,
      y: this.verticalVelocity * delta,
      z: this.horizontalVelocity.z * delta,
    });
    const movement = this.controller.computedMovement();
    const position = this.body.translation();
    this.body.setNextKinematicTranslation({
      x: position.x + movement.x,
      y: position.y + movement.y,
      z: position.z + movement.z,
    });
    this.grounded = this.controller.computedGrounded();
    if (this.grounded && this.verticalVelocity < 0) this.verticalVelocity = -0.25;
    if (position.y < -2.5) this.respawn();
  }

  afterPhysics(delta) {
    const position = this.body.translation();
    this.rig.position.set(position.x, position.y, position.z);
    this.rig.rotation.y = this.yaw;
    this.pitchRig.rotation.x = this.pitch;
    const reduced = this.store.state.settings.reducedMotion;
    const eyeHeight = this.crouched ? 0.43 : 0.63;
    let bob = 0;
    if (!reduced && this.grounded && this.moving && !this.sitting) {
      this.bobPhase += delta * (this.sprinting ? 13 : 9);
      bob = Math.sin(this.bobPhase) * (this.sprinting ? 0.035 : 0.022);
      const step = Math.floor(this.bobPhase / Math.PI);
      if (step !== this.lastStep) {
        this.lastStep = step;
        this.audio.footstep("wood", this.sprinting ? 0.75 : 0.5);
      }
    }
    this.camera.position.set(0, eyeHeight + bob, 0);
    const desiredFov = this.sprinting && !reduced ? this.baseFov + 4 : this.baseFov;
    this.camera.fov = THREE.MathUtils.lerp(this.camera.fov, desiredFov, 1 - Math.exp(-8 * delta));
    this.camera.updateProjectionMatrix();
    this.store.setPlayerRuntime({
      pose: this.getPose(),
      stance: this.crouched ? "CROUCHED" : "STANDING",
      grounded: this.grounded,
      sitting: this.sitting,
      movement: this.sprinting ? "SPRINTING" : this.moving ? "MOVING" : "",
    });
  }

  setCrouched(value) {
    if (this.crouched === value || this.sitting) return;
    if (!value && !this.physics.canStand(this.body, this.collider)) {
      this.bus.emit("NOTICE", { message: "Not enough room to stand.", tone: "info" });
      return;
    }
    const position = this.body.translation();
    const offset = value ? -0.27 : 0.27;
    this.body.setTranslation({ x: position.x, y: position.y + offset, z: position.z }, true);
    this.collider = this.physics.replacePlayerCollider(this.body, this.collider, value);
    this.crouched = value;
  }

  sit(anchor) {
    if (!anchor || this.sitting) return;
    if (this.crouched) {
      this.collider = this.physics.replacePlayerCollider(this.body, this.collider, false);
      this.crouched = false;
    }
    this.sitting = true;
    this.seatAnchor = anchor;
    this.horizontalVelocity.set(0, 0, 0);
    this.verticalVelocity = 0;
    this.collider.setEnabled(false);
    const position = { x: anchor.position[0], y: anchor.position[1], z: anchor.position[2] };
    this.body.setTranslation(position, true);
    this.body.setNextKinematicTranslation(position);
    this.yaw = anchor.yaw;
    this.pitch = anchor.pitch;
    this.bus.emit("NOTICE", { message: "Seated. Interact again to stand.", tone: "info" });
  }

  stand() {
    if (!this.sitting) return;
    const standPosition = this.seatAnchor?.standPosition || this.store.state.player.checkpoint.position;
    this.sitting = false;
    this.collider.setEnabled(true);
    const position = { x: standPosition[0], y: standPosition[1], z: standPosition[2] };
    this.body.setTranslation(position, true);
    this.body.setNextKinematicTranslation(position);
    this.seatAnchor = null;
    this.verticalVelocity = 0;
  }

  respawn() {
    if (this.sitting) this.collider.setEnabled(true);
    if (this.crouched) this.collider = this.physics.replacePlayerCollider(this.body, this.collider, false);
    const checkpoint = this.store.state.player.checkpoint;
    this.body.setTranslation({
      x: checkpoint.position[0],
      y: checkpoint.position[1],
      z: checkpoint.position[2],
    }, true);
    this.body.setNextKinematicTranslation({
      x: checkpoint.position[0],
      y: checkpoint.position[1],
      z: checkpoint.position[2],
    });
    this.yaw = checkpoint.yaw;
    this.pitch = checkpoint.pitch;
    this.sitting = false;
    this.crouched = false;
    this.seatAnchor = null;
    this.sprinting = false;
    this.moving = false;
    this.verticalVelocity = 0;
    this.horizontalVelocity.set(0, 0, 0);
    this.store.dispatch("RESPAWNED", { spawnId: this.store.state.player.spawnId }, { entityId: "player.local" });
  }

  restore(playerState) {
    if (this.crouched) this.collider = this.physics.replacePlayerCollider(this.body, this.collider, false);
    this.collider.setEnabled(true);
    this.crouched = false;
    this.sitting = false;
    this.seatAnchor = null;
    this.sprinting = false;
    this.moving = false;
    this.grounded = false;
    this.verticalVelocity = 0;
    this.horizontalVelocity.set(0, 0, 0);
    this.teleport(playerState.pose || playerState.checkpoint);
  }

  teleport(pose) {
    this.body.setTranslation({ x: pose.position[0], y: pose.position[1], z: pose.position[2] }, true);
    this.body.setNextKinematicTranslation({ x: pose.position[0], y: pose.position[1], z: pose.position[2] });
    this.yaw = pose.yaw;
    this.pitch = pose.pitch;
    this.verticalVelocity = 0;
    this.afterPhysics(0);
  }

  getPose() {
    const position = this.body.translation();
    return { position: [position.x, position.y, position.z], yaw: this.yaw, pitch: this.pitch };
  }

  getSavePose() {
    if (!this.sitting) return this.getPose();
    const position = this.seatAnchor?.standPosition || this.store.state.player.checkpoint.position;
    return { position: [...position], yaw: this.yaw, pitch: 0 };
  }
}
