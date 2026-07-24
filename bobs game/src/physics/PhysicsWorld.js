export class PhysicsWorld {
  constructor(RAPIER, bus) {
    this.RAPIER = RAPIER;
    this.bus = bus;
    this.world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
    this.world.timestep = 1 / 60;
    this.eventQueue = new RAPIER.EventQueue(true);
    this.syncTargets = [];
    this.triggerHandles = new Map();
  }

  addFixedBox({ position, size, rotationY = 0, friction = 0.82, restitution = 0.02, sensor = false }) {
    const [x, y, z] = position;
    const [width, height, depth] = size;
    const descriptor = this.RAPIER.ColliderDesc.cuboid(width / 2, height / 2, depth / 2)
      .setTranslation(x, y, z)
      .setFriction(friction)
      .setRestitution(restitution)
      .setSensor(sensor);
    if (rotationY) descriptor.setRotation({ x: 0, y: Math.sin(rotationY / 2), z: 0, w: Math.cos(rotationY / 2) });
    return this.world.createCollider(descriptor);
  }

  addDynamicChair(position, object) {
    const [x, y, z] = position;
    const body = this.world.createRigidBody(
      this.RAPIER.RigidBodyDesc.dynamic()
        .setTranslation(x, y, z)
        .setLinearDamping(0.55)
        .setAngularDamping(0.85)
        .setCcdEnabled(true),
    );
    const add = (size, offset, density = 120) => {
      const descriptor = this.RAPIER.ColliderDesc.cuboid(size[0] / 2, size[1] / 2, size[2] / 2)
        .setTranslation(...offset)
        .setDensity(density)
        .setFriction(0.78)
        .setRestitution(0.04);
      return this.world.createCollider(descriptor, body);
    };
    add([1.02, 0.2, 0.96], [0, 0.88, 0], 75);
    add([1.02, 0.95, 0.2], [0, 1.45, 0.42], 55);
    for (const xOffset of [-0.38, 0.38]) {
      for (const zOffset of [-0.34, 0.34]) add([0.1, 0.82, 0.1], [xOffset, 0.43, zOffset], 180);
    }
    this.syncTargets.push({ body, object });
    return body;
  }

  createPlayer(spawn) {
    const body = this.world.createRigidBody(
      this.RAPIER.RigidBodyDesc.kinematicPositionBased().setTranslation(...spawn),
    );
    const collider = this.world.createCollider(
      this.RAPIER.ColliderDesc.capsule(0.45, 0.32).setFriction(0).setRestitution(0),
      body,
    );
    const controller = this.world.createCharacterController(0.02);
    controller.enableAutostep(0.28, 0.15, false);
    controller.enableSnapToGround(0.18);
    controller.setMaxSlopeClimbAngle(Math.PI / 4);
    controller.setMinSlopeSlideAngle(Math.PI / 3);
    controller.setApplyImpulsesToDynamicBodies(true);
    controller.setCharacterMass(80);
    return { body, collider, controller };
  }

  replacePlayerCollider(body, collider, crouched) {
    this.world.removeCollider(collider, true);
    const next = this.RAPIER.ColliderDesc.capsule(crouched ? 0.18 : 0.45, 0.32).setFriction(0).setRestitution(0);
    return this.world.createCollider(next, body);
  }

  canStand(body, collider) {
    const position = body.translation();
    const hit = this.world.intersectionWithShape(
      { x: position.x, y: position.y + 0.27, z: position.z },
      { x: 0, y: 0, z: 0, w: 1 },
      new this.RAPIER.Capsule(0.45, 0.32),
      undefined,
      undefined,
      collider,
      body,
      candidate => !candidate.isSensor(),
    );
    return !hit;
  }

  addTrigger({ id, position, size }) {
    const collider = this.addFixedBox({ position, size, sensor: true });
    collider.setActiveEvents(this.RAPIER.ActiveEvents.COLLISION_EVENTS);
    collider.setActiveCollisionTypes(
      this.RAPIER.ActiveCollisionTypes.DEFAULT | this.RAPIER.ActiveCollisionTypes.KINEMATIC_FIXED,
    );
    this.triggerHandles.set(collider.handle, id);
    return collider;
  }

  removeCollider(collider) {
    if (collider && this.world.getCollider(collider.handle)) this.world.removeCollider(collider, true);
  }

  step() {
    this.world.step(this.eventQueue);
    this.eventQueue.drainCollisionEvents((first, second, started) => {
      if (!started) return;
      const id = this.triggerHandles.get(first) || this.triggerHandles.get(second);
      if (id) this.bus.emit("TRIGGER_ENTERED", { id, first, second });
    });
  }

  sync() {
    for (const { body, object } of this.syncTargets) {
      const position = body.translation();
      const rotation = body.rotation();
      object.position.set(position.x, position.y, position.z);
      object.quaternion.set(rotation.x, rotation.y, rotation.z, rotation.w);
    }
  }
}
