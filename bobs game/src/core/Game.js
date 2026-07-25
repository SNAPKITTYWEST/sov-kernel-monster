import { EventBus } from "./EventBus.js";
import { StateStore } from "./StateStore.js";
import { SaveManager } from "./SaveManager.js";
import { AnimationSystem } from "./AnimationSystem.js";
import { GameLoop } from "./GameLoop.js";
import { Ledger } from "./Ledger.js";
import { Renderer } from "../rendering/Renderer.js";
import { PhysicsWorld } from "../physics/PhysicsWorld.js";
import { SovereignInterior } from "../world/SovereignInterior.js";
import { InputManager } from "../input/InputManager.js";
import { PlayerController } from "../player/PlayerController.js";
import { InteractionSystem } from "../interaction/InteractionSystem.js";
import { AudioManager } from "../audio/AudioManager.js";
import { Inventory } from "../gameplay/Inventory.js";
import { QuestManager } from "../gameplay/QuestManager.js";
import { CommandRouter } from "../gameplay/CommandRouter.js";
import { HUD } from "../ui/HUD.js";
import { durableProjection } from "../gameplay/model.js";

export class Game {
  constructor(RAPIER) {
    this.bus = new EventBus();
    this.store = new StateStore({ bus: this.bus });
    this.rendering = new Renderer(document.getElementById("viewport"), this.store.state.settings);
    this.audio = new AudioManager(this.store);
    this.animations = new AnimationSystem();
    this.physics = new PhysicsWorld(RAPIER, this.bus);
    this.inventory = new Inventory(this.store);
    this.quests = new QuestManager(this.store, this.bus);
    this.commands = new CommandRouter({ store: this.store, bus: this.bus, inventory: this.inventory });
    this.world = new SovereignInterior({
      scene: this.rendering.scene,
      renderer: this.rendering,
      physics: this.physics,
      store: this.store,
      bus: this.bus,
      commands: this.commands,
      animations: this.animations,
      audio: this.audio,
    });
    this.input = new InputManager(this.rendering.renderer.domElement);
    this.input.attachTouch();
    this.player = new PlayerController({
      scene: this.rendering.scene,
      camera: this.rendering.camera,
      physics: this.physics,
      input: this.input,
      store: this.store,
      bus: this.bus,
      audio: this.audio,
    });
    this.interaction = new InteractionSystem({
      scene: this.rendering.scene,
      camera: this.rendering.camera,
      input: this.input,
      store: this.store,
      bus: this.bus,
      player: this.player,
      interactables: this.world.interactables,
    });
    this.saves = new SaveManager({ store: this.store, bus: this.bus });
    this.hud = new HUD({
      store: this.store,
      bus: this.bus,
      inventory: this.inventory,
      actions: {
        start: load => this.start(load),
        resume: () => this.resume(),
        save: () => this.save(),
        load: () => this.load(),
        respawn: () => this.player.respawn(),
        setMode: mode => this.setMode(mode),
        settings: patch => this.updateSettings(patch),
        verify: itemId => this.commands.execute("VERIFY_DOCUMENT", { itemId }),
      },
    });
    this.autosaveTimer = null;
    this.intentionalUnlock = false;
    this.bindEvents();
    this.loop = new GameLoop({
      fixedUpdate: delta => this.fixedUpdate(delta),
      update: delta => this.update(delta),
      render: () => this.render(),
    });
  }

  bindEvents() {
    document.addEventListener("pointerlockchange", () => {
      const locked = document.pointerLockElement === this.rendering.renderer.domElement;
      if (locked) {
        this.store.setMode("PLAYING");
        this.intentionalUnlock = false;
      } else if (this.store.state.mode === "PLAYING" && !this.input.isTouch && !this.intentionalUnlock) {
        this.pause();
      }
    });
    this.bus.on("EVENT_COMMITTED", ({ event }) => {
      if (["MISSION_COMPLETED", "DOCUMENT_VERIFIED", "TERMINAL_UNLOCKED", "DOCUMENT_COLLECTED"].includes(event.type)) {
        this.scheduleAutosave(event.type === "MISSION_COMPLETED" ? 0 : 700);
      }
      if (event.type === "MISSION_COMPLETED") {
        this.intentionalUnlock = true;
        document.exitPointerLock?.();
        this.store.setMode("COMPLETE");
      }
    });
  }

  ready() {
    this.rendering.render();
    this.hud.ready(this.saves.hasSave());
    this.store.setMode("BOOT");
    this.loop.start();
  }

  async start(loadSave = false) {
    await this.audio.resume();
    if (loadSave) await this.load(false);
    if (this.input.isTouch) {
      this.store.setMode("PLAYING");
      return;
    }
    this.intentionalUnlock = false;
    try {
      await this.rendering.renderer.domElement.requestPointerLock();
    } catch {
      this.store.setMode("PAUSED");
      this.bus.emit("NOTICE", { message: "Select Resume to capture the pointer.", tone: "info" });
    }
  }

  async resume() {
    await this.audio.resume();
    if (this.input.isTouch) {
      this.store.setMode("PLAYING");
      return;
    }
    this.intentionalUnlock = false;
    try {
      await this.rendering.renderer.domElement.requestPointerLock();
    } catch {
      this.store.setMode("PAUSED");
    }
  }

  pause() {
    this.intentionalUnlock = true;
    this.input.reset();
    this.store.setMode("PAUSED");
    if (document.pointerLockElement) document.exitPointerLock();
  }

  setMode(mode) {
    if (mode === "PAUSED") return this.pause();
    if (["INVENTORY", "SETTINGS", "DOCUMENT"].includes(mode)) {
      this.intentionalUnlock = true;
      this.input.reset();
      if (document.pointerLockElement) document.exitPointerLock();
    }
    this.store.setMode(mode, this.store.state.mode);
  }

  updateSettings(patch) {
    this.store.updateSettings(patch);
    if (patch.fov) {
      this.player.baseFov = patch.fov;
      this.rendering.setFov(patch.fov);
    }
    if (patch.volume !== undefined) this.audio.setVolume(patch.volume);
    if (patch.shadows) {
      this.rendering.setQuality(patch.shadows);
      this.world.setShadowQuality(patch.shadows);
    }
    localStorage.setItem("snapkitty.sovereign-interior.settings.v1", JSON.stringify(this.store.state.settings));
  }

  fixedUpdate(delta) {
    if (this.store.state.mode !== "PLAYING") return;
    this.player.fixedUpdate(delta);
    this.physics.step();
    this.physics.sync();
    this.player.afterPhysics(delta);
  }

  update(delta) {
    this.input.pollGamepad();
    if (this.store.state.mode === "PLAYING") {
      this.player.applyLook(delta);
      if (this.input.consume("PAUSE")) this.pause();
      else if (this.input.consume("INVENTORY")) this.setMode("INVENTORY");
      else if (this.input.consume("RESPAWN")) this.player.respawn();
      this.interaction.update();
      this.animations.update(delta);
      this.world.update(delta);
      this.audio.updateListener(this.rendering.camera);
    }
    if (this.store.state.mode !== "PLAYING") this.input.clearPressed();
    this.rendering.monitor(delta);
    this.input.clearFrame();
  }

  render() {
    this.rendering.render();
  }

  async save() {
    return this.saves.save(this.player.getSavePose());
  }

  async load(showPause = true) {
    const record = await this.saves.load();
    if (!record) return null;
    this.player.restore(record.player);
    if (showPause) this.store.setMode("PAUSED");
    return record;
  }

  scheduleAutosave(delay) {
    clearTimeout(this.autosaveTimer);
    this.autosaveTimer = setTimeout(() => this.save(), delay);
  }

  testAPI() {
    return Object.freeze({
      ready: true,
      getState: () => this.store.snapshot(),
      getPose: () => this.player.getPose(),
      interact: id => this.interaction.interactById(id),
      command: (command, context) => this.commands.execute(command, context),
      setPose: pose => this.player.teleport(pose),
      stepFixed: count => {
        for (let index = 0; index < count; index++) this.fixedUpdate(1 / 60);
        this.render();
        return this.player.getPose();
      },
      save: () => this.save(),
      load: () => this.load(false),
      verifyLedger: async () => Ledger.verify(await this.store.whenSealed(), durableProjection(this.store.state)),
      sceneStats: () => ({
        objects: this.rendering.scene.children.length,
        interactables: this.world.interactables.length,
        colliders: this.physics.world.colliders.len(),
        bodies: this.physics.world.bodies.len(),
      }),
    });
  }
}
