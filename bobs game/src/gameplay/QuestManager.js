export class QuestManager {
  constructor(store, bus) {
    this.store = store;
    this.processing = false;
    this.unsubscribe = bus.on("EVENT_COMMITTED", ({ event }) => {
      if (event.type !== "OBJECTIVE_ADVANCED") this.evaluate();
    });
  }

  evaluate() {
    if (this.processing) return;
    this.processing = true;
    const state = this.store.state;
    const entities = state.world.entities;
    const conditions = [
      () => entities["artwork.seal"].inspected,
      () => entities["document.covenant"].collected,
      () => entities["document.covenant"].verified,
      () => entities["terminal.sovereign"].activated,
    ];
    let stage = state.quest.stage;
    while (stage < conditions.length && conditions[stage]()) {
      stage++;
      this.store.dispatch(
        "OBJECTIVE_ADVANCED",
        { stage, status: stage === conditions.length ? "OBJECTIVE_COMPLETE" : "ACTIVE" },
        { entityId: "quest.trust-chain" },
      );
    }
    this.processing = false;
  }

  dispose() {
    this.unsubscribe?.();
  }
}
