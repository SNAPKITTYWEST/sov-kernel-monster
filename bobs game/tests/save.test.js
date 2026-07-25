import test from "node:test";
import assert from "node:assert/strict";
import { EventBus } from "../src/core/EventBus.js";
import { Ledger } from "../src/core/Ledger.js";
import { StateStore } from "../src/core/StateStore.js";
import { SaveManager } from "../src/core/SaveManager.js";
import { Inventory } from "../src/gameplay/Inventory.js";
import { QuestManager } from "../src/gameplay/QuestManager.js";
import { CommandRouter } from "../src/gameplay/CommandRouter.js";

class MemoryStorage {
  constructor() {
    this.values = new Map();
  }
  getItem(key) {
    return this.values.get(key) ?? null;
  }
  setItem(key, value) {
    this.values.set(key, String(value));
  }
}

function gameState(storage) {
  const bus = new EventBus();
  const store = new StateStore({ bus, clock: () => "2026-07-23T00:00:00.000Z" });
  const inventory = new Inventory(store);
  new QuestManager(store, bus);
  const commands = new CommandRouter({ store, bus, inventory });
  const saves = new SaveManager({ store, bus, storage });
  store.setMode("PLAYING");
  return { bus, store, commands, saves };
}

test("verified save round-trips player, inventory, world, quest, and seals", async () => {
  const storage = new MemoryStorage();
  const first = gameState(storage);
  first.commands.execute("INSPECT_ARTWORK");
  first.commands.execute("COLLECT_DOCUMENT");
  first.store.setMode("DOCUMENT");
  first.commands.execute("VERIFY_DOCUMENT", { itemId: "covenant-fragment-01" });
  const pose = { position: [1.2, 0.79, -0.4], yaw: 1.1, pitch: -0.2 };
  const record = await first.saves.save(pose);

  assert.equal(record.saveVersion, 1);
  assert.equal(record.currentSeal, record.events.at(-1).currentHash);
  assert.deepEqual(record.player.pose, pose);

  const second = gameState(storage);
  const loaded = await second.saves.load();
  assert.ok(loaded);
  assert.deepEqual(second.store.state.player.pose, pose);
  assert.equal(second.store.state.world.entities["document.covenant"].verified, true);
  assert.equal(second.store.state.quest.stage, 3);
});

test("tampered primary save falls back to the prior verified slot", async () => {
  const storage = new MemoryStorage();
  const game = gameState(storage);
  game.commands.execute("INSPECT_ARTWORK");
  const first = await game.saves.save();
  game.commands.execute("COLLECT_DOCUMENT");
  await game.saves.save();

  const primaryKey = "snapkitty.sovereign-interior.save.v1";
  const primary = JSON.parse(storage.getItem(primaryKey));
  primary.world.entities["door.exit"].locked = false;
  storage.setItem(primaryKey, JSON.stringify(primary));

  const restored = gameState(storage);
  const record = await restored.saves.load();
  assert.ok(record);
  assert.equal(record.currentSeal, first.currentSeal);
  assert.equal(restored.store.state.quest.stage, 1);
  assert.equal(restored.store.state.world.entities["door.exit"].locked, true);
});

test("unsupported save versions are rejected", async () => {
  const storage = new MemoryStorage();
  storage.setItem("snapkitty.sovereign-interior.save.v1", JSON.stringify({ saveVersion: 99, events: [] }));
  const game = gameState(storage);
  assert.equal(await game.saves.load(), null);
});

test("genesis-only saves cannot introduce unsealed world state", async () => {
  const storage = new MemoryStorage();
  const game = gameState(storage);
  const record = await game.saves.buildRecord();
  record.world.entities["door.exit"].locked = false;
  storage.setItem("snapkitty.sovereign-interior.save.v1", JSON.stringify(record));
  assert.equal(await game.saves.load(), null);
});

test("saved player position must match its sealed checkpoint", async () => {
  const storage = new MemoryStorage();
  const game = gameState(storage);
  const pose = { position: [2, 0.79, 1], yaw: 0.5, pitch: 0 };
  const record = await game.saves.save(pose);
  record.player.pose.position[0] = 99;
  storage.setItem("snapkitty.sovereign-interior.save.v1", JSON.stringify(record));
  assert.equal(await game.saves.load(), null);
});

test("saving normalizes transient seated state to a standing checkpoint", async () => {
  const storage = new MemoryStorage();
  const game = gameState(storage);
  game.store.setPlayerRuntime({ sitting: true, stance: "CROUCHED" });
  const pose = { position: [0.65, 0.79, -2.7], yaw: Math.PI, pitch: 0 };
  const record = await game.saves.save(pose);

  assert.deepEqual(record.player.pose, pose);
  assert.deepEqual(record.player.checkpoint, pose);
  assert.equal(record.player.sitting, false);
  assert.equal(record.player.stance, "STANDING");
});

test("save capture retries when a durable event enters during sealing", async () => {
  let releaseFirst;
  let signalStarted;
  const started = new Promise(resolve => {
    signalStarted = resolve;
  });
  const gate = new Promise(resolve => {
    releaseFirst = resolve;
  });
  class GatedLedger extends Ledger {
    async append(event, state) {
      if (!this.started) {
        this.started = true;
        signalStarted();
        await gate;
      }
      return super.append(event, state);
    }
  }

  const storage = new MemoryStorage();
  const bus = new EventBus();
  const store = new StateStore({
    bus,
    ledger: new GatedLedger(),
    clock: () => "2026-07-23T00:00:00.000Z",
  });
  const saves = new SaveManager({ store, bus, storage });
  const first = { position: [1, 0.79, 1], yaw: 0, pitch: 0 };
  const second = { position: [2, 0.79, 2], yaw: 0.4, pitch: 0 };
  store.dispatch("CHECKPOINT_RECORDED", { pose: first }, { entityId: "player.local" });
  const saving = saves.save();

  await started;
  store.dispatch("CHECKPOINT_RECORDED", { pose: second }, { entityId: "player.local" });
  releaseFirst();
  const record = await saving;

  assert.deepEqual(record.player.checkpoint, second);
  assert.equal(record.events.length, 2);
  assert.equal(await saves.validate(record), true);
});
