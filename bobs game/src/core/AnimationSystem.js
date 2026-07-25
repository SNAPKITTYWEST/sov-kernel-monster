const easing = {
  linear: value => value,
  smooth: value => value * value * (3 - 2 * value),
  outCubic: value => 1 - (1 - value) ** 3,
};

export class AnimationSystem {
  constructor() {
    this.active = new Set();
  }

  to({ duration = 0.4, ease = "smooth", update, complete }) {
    const animation = { elapsed: 0, duration, ease: easing[ease] || easing.smooth, update, complete };
    this.active.add(animation);
    update(0);
    return () => this.active.delete(animation);
  }

  update(delta) {
    for (const animation of this.active) {
      animation.elapsed += delta;
      const progress = Math.min(1, animation.elapsed / animation.duration);
      animation.update(animation.ease(progress));
      if (progress === 1) {
        this.active.delete(animation);
        animation.complete?.();
      }
    }
  }
}
