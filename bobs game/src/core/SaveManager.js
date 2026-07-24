import { Ledger, canonical } from "./Ledger.js";
import { SAVE_VERSION, createInitialState, durableProjection } from "../gameplay/model.js";

const PRIMARY_KEY = "snapkitty.sovereign-interior.save.v1";
const BACKUP_KEY = `${PRIMARY_KEY}.backup`;

export class SaveManager {
  constructor({ store, bus, storage = globalThis.localStorage } = {}) {
    this.store = store;
    this.bus = bus;
    this.storage = storage;
  }

  hasSave() {
    return Boolean(this.storage?.getItem(PRIMARY_KEY));
  }

  async buildRecord(playerPose) {
    if (playerPose) {
      this.store.setPlayerRuntime({ pose: structuredClone(playerPose) });
      if (canonical(playerPose) !== canonical(this.store.state.player.checkpoint)) {
        this.store.dispatch("CHECKPOINT_RECORDED", { pose: structuredClone(playerPose) }, { entityId: "player.local" });
      }
    }
    const { state, receipts: events } = await this.store.captureSealedState();
    const player = structuredClone(state.player);
    if (playerPose) {
      player.pose = structuredClone(playerPose);
      player.checkpoint = structuredClone(playerPose);
      player.stance = "STANDING";
      player.sitting = false;
      player.grounded = false;
      delete player.movement;
    }
    return {
      saveVersion: SAVE_VERSION,
      player,
      inventory: state.inventory,
      world: state.world,
      quests: state.quest,
      events,
      timestamp: new Date().toISOString(),
      previousSeal: events.at(-2)?.currentHash || "GENESIS",
      currentSeal: events.at(-1)?.currentHash || "GENESIS",
    };
  }

  async save(playerPose) {
    this.bus?.emit("SAVE_STATUS", { status: "saving", message: "Saving" });
    try {
      const record = await this.buildRecord(playerPose);
      const previous = this.storage.getItem(PRIMARY_KEY);
      if (previous) this.storage.setItem(BACKUP_KEY, previous);
      this.storage.setItem(PRIMARY_KEY, JSON.stringify(record));
      this.bus?.emit("SAVE_STATUS", { status: "saved", message: "Saved", seal: record.currentSeal });
      return record;
    } catch (error) {
      this.bus?.emit("SAVE_STATUS", { status: "error", message: "Save failed" });
      throw error;
    }
  }

  async validate(record) {
    if (!record || record.saveVersion !== SAVE_VERSION || !Array.isArray(record.events)) return false;
    const state = createInitialState();
    state.player = record.player;
    state.inventory = record.inventory;
    state.world = record.world;
    state.quest = record.quests;
    if (record.currentSeal !== (record.events.at(-1)?.currentHash || "GENESIS")) return false;
    if (record.previousSeal !== (record.events.at(-2)?.currentHash || "GENESIS")) return false;
    if (canonical(record.player.pose) !== canonical(record.player.checkpoint)) return false;
    if (!record.events.length) {
      const genesis = durableProjection(createInitialState());
      if (canonical(durableProjection(state)) !== canonical(genesis)) return false;
    }
    return Ledger.verify(record.events, durableProjection(state));
  }

  async load() {
    for (const key of [PRIMARY_KEY, BACKUP_KEY]) {
      const raw = this.storage?.getItem(key);
      if (!raw) continue;
      try {
        const record = JSON.parse(raw);
        if (!(await this.validate(record))) continue;
        const state = createInitialState();
        state.mode = "PAUSED";
        state.settings = structuredClone(this.store.state.settings);
        state.player = record.player;
        state.inventory = record.inventory;
        state.world = record.world;
        state.quest = record.quests;
        this.store.hydrate(state, record.events);
        this.bus?.emit("SAVE_STATUS", { status: "loaded", message: "Loaded", seal: record.currentSeal });
        return record;
      } catch {
        // Try the verified backup slot.
      }
    }
    this.bus?.emit("SAVE_STATUS", { status: "error", message: "No valid save" });
    return null;
  }

  async export(playerPose) {
    const record = await this.save(playerPose);
    const blob = new Blob([JSON.stringify(record, null, 2)], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `sovereign-interior-${record.currentSeal.slice(0, 12)}.json`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 0);
  }
}
