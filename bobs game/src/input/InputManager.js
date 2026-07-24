const KEY_ACTIONS = {
  KeyW: "MOVE_FORWARD",
  ArrowUp: "MOVE_FORWARD",
  KeyS: "MOVE_BACKWARD",
  ArrowDown: "MOVE_BACKWARD",
  KeyA: "MOVE_LEFT",
  ArrowLeft: "MOVE_LEFT",
  KeyD: "MOVE_RIGHT",
  ArrowRight: "MOVE_RIGHT",
  Space: "JUMP",
  ShiftLeft: "SPRINT",
  ShiftRight: "SPRINT",
  ControlLeft: "CROUCH",
  KeyC: "CROUCH",
  KeyE: "INTERACT",
  KeyI: "INVENTORY",
  Tab: "INVENTORY",
  Escape: "PAUSE",
  KeyP: "PAUSE",
  KeyR: "RESPAWN",
};

const GAMEPAD_BUTTONS = {
  0: "JUMP",
  1: "CROUCH",
  2: "INTERACT",
  3: "INVENTORY",
  9: "PAUSE",
  10: "SPRINT",
};

export class InputManager {
  constructor(canvas) {
    this.canvas = canvas;
    this.keyboardHeld = new Set();
    this.touchHeld = new Set();
    this.gamepadHeld = new Set();
    this.pressed = new Set();
    this.released = new Set();
    this.look = { x: 0, y: 0 };
    this.touchMove = { x: 0, y: 0 };
    this.gamepadMove = { x: 0, y: 0 };
    this.gamepadLook = { x: 0, y: 0 };
    this.device = matchMedia("(pointer:coarse)").matches ? "touch" : "keyboard";
    this.isTouch = this.device === "touch";
    this.lookPointer = null;
    this.previousGamepad = new Map();
    this.bindEvents();
  }

  bindEvents() {
    addEventListener("keydown", event => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement || event.target instanceof HTMLButtonElement) return;
      const action = KEY_ACTIONS[event.code];
      if (!action) return;
      if (["Space", "Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.code)) event.preventDefault();
      this.device = "keyboard";
      if (!event.repeat && !this.keyboardHeld.has(action)) this.pressed.add(action);
      this.keyboardHeld.add(action);
    });
    addEventListener("keyup", event => {
      const action = KEY_ACTIONS[event.code];
      if (!action) return;
      this.keyboardHeld.delete(action);
      this.released.add(action);
    });
    addEventListener("mousemove", event => {
      if (document.pointerLockElement !== this.canvas) return;
      this.device = "keyboard";
      this.look.x += event.movementX;
      this.look.y += event.movementY;
    });
    this.canvas.addEventListener("pointerdown", event => {
      if (event.pointerType !== "touch" || event.clientX < innerWidth * 0.35) return;
      this.device = "touch";
      this.lookPointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
      this.canvas.setPointerCapture(event.pointerId);
    });
    this.canvas.addEventListener("pointermove", event => {
      if (this.lookPointer?.id !== event.pointerId) return;
      this.look.x += (event.clientX - this.lookPointer.x) * 0.75;
      this.look.y += (event.clientY - this.lookPointer.y) * 0.75;
      this.lookPointer.x = event.clientX;
      this.lookPointer.y = event.clientY;
    });
    const clearLookPointer = event => {
      if (this.lookPointer?.id === event.pointerId) this.lookPointer = null;
    };
    this.canvas.addEventListener("pointerup", clearLookPointer);
    this.canvas.addEventListener("pointercancel", clearLookPointer);
  }

  attachTouch(root = document) {
    const pad = root.querySelector("#move-pad");
    const knob = root.querySelector("#move-knob");
    let padPointer = null;
    const updatePad = event => {
      if (event.pointerId !== padPointer) return;
      const bounds = pad.getBoundingClientRect();
      let x = event.clientX - (bounds.left + bounds.width / 2);
      let y = event.clientY - (bounds.top + bounds.height / 2);
      const length = Math.hypot(x, y);
      const limit = 32;
      if (length > limit) {
        x *= limit / length;
        y *= limit / length;
      }
      this.touchMove.x = x / limit;
      this.touchMove.y = -y / limit;
      knob.style.transform = `translate(${x}px,${y}px)`;
      this.device = "touch";
    };
    pad?.addEventListener("pointerdown", event => {
      padPointer = event.pointerId;
      pad.setPointerCapture(event.pointerId);
      updatePad(event);
    });
    pad?.addEventListener("pointermove", updatePad);
    const releasePad = event => {
      if (event.pointerId !== padPointer) return;
      padPointer = null;
      this.touchMove.x = this.touchMove.y = 0;
      knob.style.transform = "translate(0,0)";
    };
    pad?.addEventListener("pointerup", releasePad);
    pad?.addEventListener("pointercancel", releasePad);

    for (const button of root.querySelectorAll("[data-touch-action]")) {
      const action = button.dataset.touchAction;
      button.addEventListener("pointerdown", event => {
        event.preventDefault();
        this.device = "touch";
        if (!this.touchHeld.has(action)) this.pressed.add(action);
        this.touchHeld.add(action);
        button.setPointerCapture(event.pointerId);
      });
      const release = () => {
        this.touchHeld.delete(action);
        this.released.add(action);
      };
      button.addEventListener("pointerup", release);
      button.addEventListener("pointercancel", release);
    }
  }

  pollGamepad() {
    const gamepad = [...(navigator.getGamepads?.() || [])].find(Boolean);
    if (!gamepad) {
      this.gamepadMove = { x: 0, y: 0 };
      this.gamepadLook = { x: 0, y: 0 };
      this.gamepadHeld.clear();
      return;
    }
    const deadzone = value => Math.abs(value) < 0.15 ? 0 : Math.sign(value) * ((Math.abs(value) - 0.15) / 0.85) ** 1.4;
    this.gamepadMove = { x: deadzone(gamepad.axes[0] || 0), y: -deadzone(gamepad.axes[1] || 0) };
    this.gamepadLook = { x: deadzone(gamepad.axes[2] || 0), y: deadzone(gamepad.axes[3] || 0) };
    if (Math.hypot(this.gamepadMove.x, this.gamepadMove.y, this.gamepadLook.x, this.gamepadLook.y) > 0.1) this.device = "gamepad";
    for (const [index, action] of Object.entries(GAMEPAD_BUTTONS)) {
      const down = Boolean(gamepad.buttons[index]?.pressed);
      const wasDown = this.previousGamepad.get(action) || false;
      if (down && !wasDown) this.pressed.add(action);
      if (!down && wasDown) this.released.add(action);
      if (down) this.gamepadHeld.add(action);
      else this.gamepadHeld.delete(action);
      this.previousGamepad.set(action, down);
      if (down) this.device = "gamepad";
    }
  }

  movement() {
    const x = (this.isHeld("MOVE_RIGHT") ? 1 : 0) - (this.isHeld("MOVE_LEFT") ? 1 : 0) + this.touchMove.x + this.gamepadMove.x;
    const y = (this.isHeld("MOVE_FORWARD") ? 1 : 0) - (this.isHeld("MOVE_BACKWARD") ? 1 : 0) + this.touchMove.y + this.gamepadMove.y;
    const length = Math.hypot(x, y);
    return length > 1 ? { x: x / length, y: y / length } : { x, y };
  }

  consumeLook(delta) {
    const result = {
      x: this.look.x + this.gamepadLook.x * 720 * delta,
      y: this.look.y + this.gamepadLook.y * 720 * delta,
    };
    this.look.x = this.look.y = 0;
    return result;
  }

  isHeld(action) {
    return this.keyboardHeld.has(action) || this.touchHeld.has(action) || this.gamepadHeld.has(action);
  }

  consume(action) {
    const value = this.pressed.has(action);
    this.pressed.delete(action);
    return value;
  }

  clearFrame() {
    this.released.clear();
  }

  clearPressed() {
    this.pressed.clear();
  }

  reset() {
    this.keyboardHeld.clear();
    this.touchHeld.clear();
    this.gamepadHeld.clear();
    this.pressed.clear();
    this.released.clear();
    this.touchMove = { x: 0, y: 0 };
    this.gamepadMove = { x: 0, y: 0 };
    this.look.x = this.look.y = 0;
  }
}
