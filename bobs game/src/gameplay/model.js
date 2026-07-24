export const SAVE_VERSION = 1;

export const OBJECTIVES = [
  { id: "inspect-artwork", label: "Inspect the sealed artwork" },
  { id: "collect-document", label: "Collect the covenant document" },
  { id: "verify-document", label: "Verify the document in inventory" },
  { id: "activate-terminal", label: "Activate the sovereign terminal" },
  { id: "exit-chamber", label: "Exit through the unlocked door" },
];

export function createInitialState() {
  return {
    saveVersion: SAVE_VERSION,
    mode: "BOOT",
    player: {
      id: "player.local",
      spawnId: "chamber.entry",
      pose: { position: [0, 0.79, 3.35], yaw: 0, pitch: 0 },
      checkpoint: { position: [0, 0.79, 3.35], yaw: 0, pitch: 0 },
      stance: "STANDING",
      stability: 100,
      grounded: false,
      sitting: false,
    },
    inventory: { capacity: 8, order: [], byId: {} },
    world: {
      entities: {
        "lamp.floor": { on: true },
        "couch.main": { used: false },
        "artwork.seal": { inspected: false },
        "document.covenant": { present: true, collected: false, verified: false },
        "terminal.sovereign": { activated: false },
        "door.exit": { locked: true, open: false },
      },
    },
    quest: { id: "trust-chain", stage: 0, status: "ACTIVE" },
    settings: {
      sensitivity: 1,
      fov: 75,
      volume: 0.6,
      invertY: false,
      reducedMotion: false,
      highContrast: false,
      shadows: globalThis.matchMedia?.("(pointer:coarse)")?.matches ? "low" : "high",
    },
    session: { targetId: null, notice: null, returnMode: "PAUSED" },
  };
}

export function reducer(current, event) {
  const state = structuredClone(current);
  const entities = state.world.entities;
  switch (event.type) {
    case "MODE_CHANGED":
      state.mode = event.payload.mode;
      state.session.returnMode = event.payload.returnMode || state.session.returnMode;
      break;
    case "SETTINGS_CHANGED":
      Object.assign(state.settings, event.payload);
      break;
    case "LAMP_ACTIVATED":
      entities["lamp.floor"].on = true;
      break;
    case "LAMP_DEACTIVATED":
      entities["lamp.floor"].on = false;
      break;
    case "ARTWORK_INSPECTED":
      entities["artwork.seal"].inspected = true;
      break;
    case "COUCH_USED":
      entities["couch.main"].used = true;
      break;
    case "DOCUMENT_COLLECTED": {
      const item = event.payload.item;
      entities["document.covenant"].present = false;
      entities["document.covenant"].collected = true;
      if (!state.inventory.byId[item.id]) {
        state.inventory.order.push(item.id);
        state.inventory.byId[item.id] = item;
      }
      break;
    }
    case "DOCUMENT_VERIFIED":
      entities["document.covenant"].verified = true;
      if (state.inventory.byId[event.payload.itemId]) state.inventory.byId[event.payload.itemId].verified = true;
      break;
    case "TERMINAL_UNLOCKED":
      entities["terminal.sovereign"].activated = true;
      entities["door.exit"].locked = false;
      break;
    case "DOOR_OPENED":
      entities["door.exit"].open = true;
      break;
    case "OBJECTIVE_ADVANCED":
      state.quest.stage = event.payload.stage;
      state.quest.status = event.payload.status || "ACTIVE";
      break;
    case "MISSION_COMPLETED":
      state.quest.status = "COMPLETE";
      break;
    case "RESPAWNED":
      state.player.stability = 100;
      break;
    case "CHECKPOINT_RECORDED":
      state.player.pose = structuredClone(event.payload.pose);
      state.player.checkpoint = structuredClone(event.payload.pose);
      break;
    case "STABILITY_CHANGED":
      state.player.stability = Math.max(0, Math.min(100, event.payload.value));
      break;
  }
  return state;
}

export function durableProjection(state) {
  return {
    saveVersion: state.saveVersion,
    player: { id: state.player.id, spawnId: state.player.spawnId, checkpoint: state.player.checkpoint },
    inventory: state.inventory,
    world: state.world,
    quest: state.quest,
  };
}

export function currentObjective(state) {
  const stage = Math.min(state.quest.stage, OBJECTIVES.length - 1);
  return {
    ...OBJECTIVES[stage],
    progress: state.quest.status === "COMPLETE" ? OBJECTIVES.length : stage + 1,
    total: OBJECTIVES.length,
  };
}
