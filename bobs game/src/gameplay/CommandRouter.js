import { ITEMS } from "./items.js";

export class CommandRouter {
  constructor({ store, bus, inventory }) {
    this.store = store;
    this.bus = bus;
    this.inventory = inventory;
  }

  execute(command, context = {}) {
    const worldCommands = new Set([
      "TOGGLE_LAMP", "INSPECT_ARTWORK", "COLLECT_DOCUMENT", "ACTIVATE_TERMINAL",
      "USE_COUCH", "PUSH_CHAIR", "MISSION_COMPLETE",
    ]);
    if (worldCommands.has(command) && this.store.state.mode !== "PLAYING") return false;
    if (command === "VERIFY_DOCUMENT" && !["INVENTORY", "DOCUMENT"].includes(this.store.state.mode)) return false;
    const entities = this.store.state.world.entities;
    switch (command) {
      case "TOGGLE_LAMP": {
        const on = entities["lamp.floor"].on;
        this.store.dispatch(on ? "LAMP_DEACTIVATED" : "LAMP_ACTIVATED", { on: !on }, { entityId: "lamp.floor" });
        return true;
      }
      case "INSPECT_ARTWORK":
        if (!entities["artwork.seal"].inspected) {
          this.store.dispatch("ARTWORK_INSPECTED", { inscription: "Witness I acknowledged" }, { entityId: "artwork.seal" });
          this.notice("Witness I sealed into the chain.");
        } else {
          this.notice("The artwork receipt remains valid.");
        }
        return true;
      case "COLLECT_DOCUMENT":
        if (!entities["document.covenant"].present) return false;
        if (this.inventory.collect(ITEMS.covenant, "document.covenant")) {
          this.notice("Covenant Fragment added to evidence.");
          return true;
        }
        this.notice("Evidence capacity reached.", "error");
        return false;
      case "VERIFY_DOCUMENT":
        if (this.inventory.verify(context.itemId || ITEMS.covenant.id)) {
          this.notice("Covenant predecessor verified.");
          return true;
        }
        return false;
      case "ACTIVATE_TERMINAL":
        if (!entities["document.covenant"].verified) {
          this.notice("The terminal rejects unverified evidence.", "error");
          return false;
        }
        if (!entities["terminal.sovereign"].activated) {
          this.store.dispatch("TERMINAL_UNLOCKED", { covenant: ITEMS.covenant.id }, { entityId: "terminal.sovereign" });
          this.store.dispatch("DOOR_OPENED", { automatic: true }, { entityId: "door.exit" });
          this.notice("Trust chain accepted. Exit released.");
        }
        return true;
      case "USE_COUCH":
        if (!entities["couch.main"].used) this.store.dispatch("COUCH_USED", { anchor: "couch.main.seat" }, { entityId: "couch.main" });
        this.bus.emit("PLAYER_SIT_REQUESTED", { anchor: context.anchor });
        return true;
      case "PUSH_CHAIR":
        context.body?.applyImpulse(context.impulse, true);
        return true;
      case "MISSION_COMPLETE":
        if (this.store.state.quest.status !== "COMPLETE") {
          this.store.dispatch("MISSION_COMPLETED", { exit: "door.exit" }, { entityId: "trigger.exit" });
        }
        return true;
      default:
        return false;
    }
  }

  notice(message, tone = "info") {
    this.bus.emit("NOTICE", { message, tone });
  }
}
