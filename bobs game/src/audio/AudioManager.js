import * as THREE from "three";

export class AudioManager {
  constructor(store) {
    this.store = store;
    this.context = null;
    this.master = null;
    this.hum = null;
    this.humGain = null;
    this.humPanner = null;
    this.lampOn = store.state.world.entities["lamp.floor"].on;
    this.listenerPosition = new THREE.Vector3();
    this.listenerDirection = new THREE.Vector3();
  }

  async resume() {
    if (!this.context) {
      const AudioContext = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!AudioContext) return;
      this.context = new AudioContext();
      this.master = this.context.createGain();
      this.master.gain.value = this.store.state.settings.volume;
      this.master.connect(this.context.destination);
      this.createLampHum();
    }
    await this.context.resume();
  }

  createLampHum() {
    this.hum = this.context.createOscillator();
    this.humGain = this.context.createGain();
    this.humPanner = this.context.createPanner();
    const filter = this.context.createBiquadFilter();
    this.hum.type = "sine";
    this.hum.frequency.value = 58;
    filter.type = "lowpass";
    filter.frequency.value = 180;
    this.humGain.gain.value = this.lampOn ? 0.008 : 0;
    this.humPanner.panningModel = "HRTF";
    this.humPanner.distanceModel = "inverse";
    this.humPanner.refDistance = 1;
    this.humPanner.maxDistance = 12;
    this.humPanner.rolloffFactor = 1.2;
    this.humPanner.positionX.value = -5.03;
    this.humPanner.positionY.value = 2.7;
    this.humPanner.positionZ.value = -3.75;
    this.hum.connect(filter).connect(this.humGain).connect(this.humPanner).connect(this.master);
    this.hum.start();
  }

  setVolume(value) {
    if (this.master) this.master.gain.setTargetAtTime(value, this.context.currentTime, 0.03);
  }

  setLamp(on) {
    this.lampOn = on;
    if (this.humGain) this.humGain.gain.setTargetAtTime(on ? 0.008 : 0, this.context.currentTime, 0.08);
    if (this.context?.state === "running") this.playTone(on ? 310 : 190, 0.08, 0.025);
  }

  playTone(frequency = 440, duration = 0.08, volume = 0.02) {
    if (!this.context || this.context.state !== "running") return;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    oscillator.type = "triangle";
    oscillator.frequency.value = frequency;
    gain.gain.setValueAtTime(volume, this.context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.0001, this.context.currentTime + duration);
    oscillator.connect(gain).connect(this.master);
    oscillator.start();
    oscillator.stop(this.context.currentTime + duration);
  }

  footstep(material = "wood", strength = 0.5) {
    if (!this.context || this.context.state !== "running") return;
    const length = Math.floor(this.context.sampleRate * 0.075);
    const buffer = this.context.createBuffer(1, length, this.context.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < length; index++) {
      const envelope = 1 - index / length;
      data[index] = (Math.random() * 2 - 1) * envelope * envelope;
    }
    const source = this.context.createBufferSource();
    const filter = this.context.createBiquadFilter();
    const gain = this.context.createGain();
    filter.type = "bandpass";
    filter.frequency.value = material === "wood" ? 185 : 120;
    filter.Q.value = 0.8;
    gain.gain.value = 0.045 * strength;
    source.buffer = buffer;
    source.connect(filter).connect(gain).connect(this.master);
    source.start();
  }

  updateListener(camera) {
    if (!this.context) return;
    camera.getWorldPosition(this.listenerPosition);
    camera.getWorldDirection(this.listenerDirection);
    const listener = this.context.listener;
    const time = this.context.currentTime;
    listener.positionX?.setValueAtTime(this.listenerPosition.x, time);
    listener.positionY?.setValueAtTime(this.listenerPosition.y, time);
    listener.positionZ?.setValueAtTime(this.listenerPosition.z, time);
    listener.forwardX?.setValueAtTime(this.listenerDirection.x, time);
    listener.forwardY?.setValueAtTime(this.listenerDirection.y, time);
    listener.forwardZ?.setValueAtTime(this.listenerDirection.z, time);
  }
}
