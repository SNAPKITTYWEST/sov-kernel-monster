import test from "node:test";
import assert from "node:assert/strict";
import { EventBus } from "../src/core/EventBus.js";
import { StateStore } from "../src/core/StateStore.js";
import { Inventory } from "../src/gameplay/Inventory.js";
import { QuestManager } from "../src/gameplay/QuestManager.js";
import { CommandRouter } from "../src/gameplay/CommandRouter.js";

function createHarness() {
  const bus = new EventBus();
  let tick = 0;
  const store = new StateStore({
    bus,
    clock: () => `2026-07-23T00:00:${String(tick++).padStart(2, "0")}.000Z`,
  });
  const inventory = new Inventory(store);
  const quests = new QuestManager(store, bus);
  const commands = new CommandRouter({ store, bus, inventory });
  store.setMode("PLAYING");
  return { bus, store, inventory, quests, commands };
}

test("vertical slice advances only from authoritative state conditions", async () => {
  const { store, commands } = createHarness();

  assert.equal(commands.execute("ACTIVATE_TERMINAL"), false);
  assert.equal(store.state.quest.stage, 0);

  commands.execute("INSPECT_ARTWORK");
  assert.equal(store.state.quest.stage, 1);

  commands.execute("COLLECT_DOCUMENT");
  assert.equal(store.state.quest.stage, 2);
  assert.deepEqual(store.state.inventory.order, ["covenant-fragment-01"]);

  store.setMode("DOCUMENT");
  commands.execute("VERIFY_DOCUMENT", { itemId: "covenant-fragment-01" });
  assert.equal(store.state.quest.stage, 3);

  store.setMode("PLAYING");
  commands.execute("ACTIVATE_TERMINAL");
  assert.equal(store.state.quest.stage, 4);
  assert.equal(store.state.world.entities["door.exit"].locked, false);
  assert.equal(store.state.world.entities["door.exit"].open, true);

  const receipts = await store.whenSealed();
  assert.deepEqual(receipts.map(receipt => receipt.eventType), [
    "ARTWORK_INSPECTED",
    "OBJECTIVE_ADVANCED",
    "DOCUMENT_COLLECTED",
    "OBJECTIVE_ADVANCED",
    "DOCUMENT_VERIFIED",
    "OBJECTIVE_ADVANCED",
    "TERMINAL_UNLOCKED",
    "OBJECTIVE_ADVANCED",
    "DOOR_OPENED",
  ]);
  receipts.forEach((receipt, index) => {
    assert.equal(receipt.sequence, index + 1);
    assert.equal(receipt.previousHash, index ? receipts[index - 1].currentHash : "GENESIS");
  });
});

test("lamp and couch actions are modeled independently from meshes", async () => {
  const { store, commands, bus } = createHarness();
  let sitRequest = null;
  bus.on("PLAYER_SIT_REQUESTED", request => { sitRequest = request; });

  commands.execute("TOGGLE_LAMP");
  assert.equal(store.state.world.entities["lamp.floor"].on, false);
  commands.execute("TOGGLE_LAMP");
  assert.equal(store.state.world.entities["lamp.floor"].on, true);

  const anchor = { position: [-2.2, 0.79, -3.12], yaw: Math.PI, pitch: 0 };
  commands.execute("USE_COUCH", { anchor });
  assert.equal(store.state.world.entities["couch.main"].used, true);
  assert.deepEqual(sitRequest.anchor, anchor);

  const receipts = await store.whenSealed();
  assert.deepEqual(receipts.map(receipt => receipt.eventType), [
    "LAMP_DEACTIVATED",
    "LAMP_ACTIVATED",
    "COUCH_USED",
  ]);
});

test("world commands are rejected outside PLAYING mode", () => {
  const { store, commands } = createHarness();
  store.setMode("PAUSED");
  assert.equal(commands.execute("TOGGLE_LAMP"), false);
  assert.equal(commands.execute("COLLECT_DOCUMENT"), false);
  assert.equal(store.state.world.entities["lamp.floor"].on, true);
  assert.equal(store.state.world.entities["document.covenant"].present, true);
});
