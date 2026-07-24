import { Ledger } from "./Ledger.js";
import { createInitialState, reducer, durableProjection } from "../gameplay/model.js";

export class StateStore {
  constructor({ bus, initialState = createInitialState(), clock = () => new Date().toISOString(), ledger } = {}) {
    this.bus = bus;
    this.state = structuredClone(initialState);
    this.clock = clock;
    this.ledger = ledger || new Ledger();
    this.sealQueue = Promise.resolve();
  }

  dispatch(type, payload = {}, { durable = true, entityId = null } = {}) {
    const event = {
      type,
      payload: structuredClone(payload),
      entityId,
      playerId: this.state.player.id,
      timestamp: this.clock(),
    };
    this.state = reducer(this.state, event);
    const projection = durableProjection(this.state);
    if (durable) {
      this.sealQueue = this.sealQueue
        .then(() => this.ledger.append(event, projection))
        .then(receipt => {
          this.bus?.emit("SEALED_EVENT", receipt);
          return receipt;
        });
    }
    this.bus?.emit("STATE_CHANGED", { state: this.state, event });
    this.bus?.emit("EVENT_COMMITTED", { state: this.state, event });
    return event;
  }

  setMode(mode, returnMode) {
    this.dispatch("MODE_CHANGED", { mode, returnMode }, { durable: false });
  }

  updateSettings(settings) {
    this.dispatch("SETTINGS_CHANGED", settings, { durable: false });
  }

  setPlayerRuntime(patch) {
    Object.assign(this.state.player, structuredClone(patch));
  }

  snapshot() {
    return structuredClone(this.state);
  }

  async whenSealed() {
    return (await this.captureSealedState()).receipts;
  }

  async captureSealedState() {
    while (true) {
      const pending = this.sealQueue;
      await pending;
      if (pending !== this.sealQueue) continue;
      return { state: this.snapshot(), receipts: this.ledger.clone() };
    }
  }

  hydrate(state, receipts) {
    this.state = structuredClone(state);
    this.ledger = new Ledger({ receipts });
    this.sealQueue = Promise.resolve();
    this.bus?.emit("STATE_HYDRATED", { state: this.state });
    this.bus?.emit("STATE_CHANGED", { state: this.state, event: { type: "STATE_HYDRATED", payload: {} } });
  }
}
