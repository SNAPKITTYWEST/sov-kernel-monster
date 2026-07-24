import { currentObjective } from "../gameplay/model.js";

const MODES = {
  BOOT: "start-screen",
  PAUSED: "pause-screen",
  SETTINGS: "settings-screen",
  INVENTORY: "inventory-screen",
  DOCUMENT: "document-screen",
  COMPLETE: "complete-screen",
};

export class HUD {
  constructor({ store, bus, inventory, actions }) {
    this.store = store;
    this.bus = bus;
    this.inventory = inventory;
    this.actions = actions;
    this.selectedItemId = null;
    this.category = "all";
    this.toastTimer = null;
    this.saveTimer = null;
    this.nodes = Object.fromEntries(
      [
        "hud", "loading-screen", "start-screen", "pause-screen", "settings-screen", "inventory-screen",
        "document-screen", "complete-screen", "objective-text", "objective-progress", "save-status",
        "reticle", "interaction-prompt", "stability-value", "stability-fill", "stance", "movement-state",
        "inventory-count", "inventory-list", "inventory-detail", "toast", "continue-game", "pause-receipt",
        "document-title", "document-body", "document-seal", "verify-document", "completion-seal",
      ].map(id => [id, document.getElementById(id)]),
    );
    this.overlays = [...document.querySelectorAll(".overlay")];
    this.bind();
    this.bus.on("STATE_CHANGED", ({ state }) => this.renderState(state));
    this.bus.on("INTERACTION_TARGET", target => this.renderInteraction(target));
    this.bus.on("NOTICE", notice => this.toast(notice));
    this.bus.on("SAVE_STATUS", status => this.renderSaveStatus(status));
    this.bus.on("SEALED_EVENT", receipt => {
      this.nodes["pause-receipt"].textContent = `Current seal ${receipt.currentHash}`;
      if (receipt.eventType === "MISSION_COMPLETED") this.nodes["completion-seal"].textContent = receipt.currentHash;
    });
    this.renderState(store.state);
  }

  bind() {
    document.getElementById("enter-game").addEventListener("click", () => this.actions.start(false));
    this.nodes["continue-game"].addEventListener("click", () => this.actions.start(true));
    document.getElementById("resume-game").addEventListener("click", () => this.actions.resume());
    document.getElementById("save-game").addEventListener("click", () => this.actions.save());
    document.getElementById("load-game").addEventListener("click", () => this.actions.load());
    document.getElementById("respawn-player").addEventListener("click", () => this.actions.respawn());
    document.getElementById("open-settings").addEventListener("click", () => this.actions.setMode("SETTINGS"));
    document.getElementById("close-settings").addEventListener("click", () => this.actions.setMode("PAUSED"));
    document.getElementById("close-inventory").addEventListener("click", () => this.actions.setMode("PAUSED"));
    document.getElementById("back-document").addEventListener("click", () => this.actions.setMode("INVENTORY"));
    document.getElementById("continue-exploring").addEventListener("click", () => this.actions.resume());
    for (const button of document.querySelectorAll('[data-command="inventory"]')) {
      button.addEventListener("click", () => this.actions.setMode("INVENTORY"));
    }
    for (const button of document.querySelectorAll('[data-command="pause"]')) {
      button.addEventListener("click", () => this.actions.setMode("PAUSED"));
    }
    for (const button of document.querySelectorAll("[data-category]")) {
      button.addEventListener("click", () => {
        this.category = button.dataset.category;
        document.querySelectorAll("[data-category]").forEach(item => item.classList.toggle("active", item === button));
        this.renderInventory();
      });
    }
    const settingMap = {
      "setting-sensitivity": ["sensitivity", "number"],
      "setting-fov": ["fov", "number"],
      "setting-volume": ["volume", "number"],
      "setting-invert": ["invertY", "checked"],
      "setting-reduced-motion": ["reducedMotion", "checked"],
      "setting-contrast": ["highContrast", "checked"],
      "setting-shadows": ["shadows", "value"],
    };
    for (const [id, [key, kind]] of Object.entries(settingMap)) {
      document.getElementById(id).addEventListener("input", event => {
        const value = kind === "number" ? Number(event.target.value) : kind === "checked" ? event.target.checked : event.target.value;
        this.actions.settings({ [key]: value });
      });
    }
    this.nodes["verify-document"].addEventListener("click", () => {
      if (this.selectedItemId) this.actions.verify(this.selectedItemId);
      this.renderDocument(this.store.state.inventory.byId[this.selectedItemId]);
    });
  }

  ready(hasSave) {
    this.nodes["loading-screen"].hidden = true;
    this.nodes["start-screen"].hidden = false;
    this.nodes["continue-game"].hidden = !hasSave;
    this.nodes["start-screen"].querySelector("button:not([hidden])")?.focus();
  }

  setMode(mode) {
    for (const overlay of this.overlays) {
      overlay.hidden = true;
      overlay.inert = true;
    }
    this.nodes.hud.hidden = mode === "BOOT" || mode === "LOADING";
    const overlayId = MODES[mode];
    if (overlayId) {
      const overlay = this.nodes[overlayId];
      overlay.hidden = false;
      overlay.inert = false;
      overlay.querySelector("button:not([disabled]),input,select")?.focus();
    }
    if (mode === "INVENTORY") this.renderInventory();
  }

  renderState(state) {
    const objective = currentObjective(state);
    this.nodes["objective-text"].textContent = objective.label;
    this.nodes["objective-progress"].textContent = state.quest.status === "COMPLETE"
      ? "Mission complete"
      : `Step ${objective.progress} of ${objective.total}`;
    this.nodes["stability-value"].textContent = Math.round(state.player.stability);
    this.nodes["stability-fill"].style.width = `${state.player.stability}%`;
    this.nodes.stance.textContent = state.player.sitting ? "Seated" : state.player.stance === "CROUCHED" ? "Crouched" : "Standing";
    this.nodes["movement-state"].textContent = state.player.movement || "";
    this.nodes["inventory-count"].textContent = state.inventory.order.length;
    this.applySettings(state.settings);
    this.setMode(state.mode);
    if (state.mode === "INVENTORY") this.renderInventory();
  }

  applySettings(settings) {
    document.body.classList.toggle("reduced-motion", settings.reducedMotion);
    document.body.classList.toggle("high-contrast", settings.highContrast);
    document.getElementById("setting-sensitivity").value = settings.sensitivity;
    document.getElementById("setting-fov").value = settings.fov;
    document.getElementById("setting-volume").value = settings.volume;
    document.getElementById("setting-invert").checked = settings.invertY;
    document.getElementById("setting-reduced-motion").checked = settings.reducedMotion;
    document.getElementById("setting-contrast").checked = settings.highContrast;
    document.getElementById("setting-shadows").value = settings.shadows;
  }

  renderInteraction(target) {
    this.nodes.reticle.classList.toggle("active", Boolean(target?.enabled));
    this.nodes["interaction-prompt"].textContent = target?.prompt || "";
    this.nodes["interaction-prompt"].classList.toggle("visible", Boolean(target?.prompt));
  }

  renderInventory() {
    const items = this.inventory.list().filter(item => this.category === "all" || item.category === this.category || item.kind === this.category);
    const list = this.nodes["inventory-list"];
    list.replaceChildren();
    if (!items.length) {
      list.innerHTML = '<p class="empty-state">No matching evidence.</p>';
      this.nodes["inventory-detail"].innerHTML = '<p class="empty-state">Inspect the chamber to build the evidence register.</p>';
      return;
    }
    if (!items.some(item => item.id === this.selectedItemId)) this.selectedItemId = items[0].id;
    for (const item of items) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `inventory-item${item.id === this.selectedItemId ? " selected" : ""}`;
      button.setAttribute("role", "option");
      button.ariaSelected = String(item.id === this.selectedItemId);
      button.innerHTML = `<strong>${item.name}</strong><small>${item.verified ? "Verified" : "Unverified"} · ${item.kind}</small>`;
      button.addEventListener("click", () => {
        this.selectedItemId = item.id;
        this.renderInventory();
      });
      list.append(button);
    }
    const item = this.store.state.inventory.byId[this.selectedItemId];
    this.nodes["inventory-detail"].innerHTML = `
      <p class="eyebrow">${item.kind}</p>
      <h3>${item.name}</h3>
      <p>${item.description}</p>
      <p><strong>${item.verified ? "Receipt verified" : "Verification required"}</strong></p>
      <div class="item-actions"><button id="read-selected" class="primary" type="button">Read</button></div>
    `;
    document.getElementById("read-selected").addEventListener("click", () => {
      this.renderDocument(item);
      this.actions.setMode("DOCUMENT");
    });
  }

  renderDocument(item) {
    if (!item) return;
    this.selectedItemId = item.id;
    this.nodes["document-title"].textContent = item.name;
    this.nodes["document-body"].replaceChildren(...item.body.map(paragraph => {
      const node = document.createElement("p");
      node.textContent = paragraph;
      return node;
    }));
    this.nodes["document-seal"].textContent = item.seal;
    this.nodes["verify-document"].disabled = item.verified;
    this.nodes["verify-document"].textContent = item.verified ? "Covenant Verified" : "Verify Covenant";
  }

  toast({ message, tone = "info" }) {
    clearTimeout(this.toastTimer);
    this.nodes.toast.textContent = message;
    this.nodes.toast.style.borderColor = tone === "error" ? "var(--danger)" : "var(--amber)";
    this.nodes.toast.classList.add("visible");
    this.toastTimer = setTimeout(() => this.nodes.toast.classList.remove("visible"), 2600);
  }

  renderSaveStatus({ status, message }) {
    clearTimeout(this.saveTimer);
    this.nodes["save-status"].textContent = message;
    this.nodes["save-status"].classList.add("visible");
    if (status !== "error") this.saveTimer = setTimeout(() => this.nodes["save-status"].classList.remove("visible"), 1800);
  }
}
