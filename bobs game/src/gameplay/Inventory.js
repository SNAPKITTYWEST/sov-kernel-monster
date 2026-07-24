export class Inventory {
  constructor(store) {
    this.store = store;
  }

  collect(item, entityId) {
    if (this.store.state.inventory.order.length >= this.store.state.inventory.capacity) return false;
    if (this.store.state.inventory.byId[item.id]) return false;
    this.store.dispatch("DOCUMENT_COLLECTED", { item: structuredClone(item) }, { entityId });
    return true;
  }

  verify(itemId) {
    const item = this.store.state.inventory.byId[itemId];
    if (!item || item.verified) return false;
    this.store.dispatch("DOCUMENT_VERIFIED", { itemId }, { entityId: itemId });
    return true;
  }

  list() {
    const inventory = this.store.state.inventory;
    return inventory.order.map(id => inventory.byId[id]);
  }
}
