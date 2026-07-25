export class GameLoop {
  constructor({ fixedUpdate, update, render, fixedStep = 1 / 60 }) {
    this.fixedUpdate = fixedUpdate;
    this.update = update;
    this.render = render;
    this.fixedStep = fixedStep;
    this.accumulator = 0;
    this.lastTime = 0;
    this.running = false;
    this.frame = time => this.tick(time);
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.lastTime = performance.now();
    requestAnimationFrame(this.frame);
  }

  stop() {
    this.running = false;
  }

  tick(time) {
    if (!this.running) return;
    const delta = Math.min(0.05, Math.max(0, (time - this.lastTime) / 1000));
    this.lastTime = time;
    this.accumulator = Math.min(this.accumulator + delta, this.fixedStep * 5);
    while (this.accumulator >= this.fixedStep) {
      this.fixedUpdate(this.fixedStep);
      this.accumulator -= this.fixedStep;
    }
    this.update(delta);
    this.render(this.accumulator / this.fixedStep);
    requestAnimationFrame(this.frame);
  }
}
