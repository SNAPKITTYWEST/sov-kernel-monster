import RAPIER from "@dimforge/rapier3d-compat";
import { Game } from "./core/Game.js";

const loadingText = document.getElementById("loading-text");

try {
  loadingText.textContent = "Loading Rapier collision world";
  await RAPIER.init();
  loadingText.textContent = "Building sealed chamber";
  const game = new Game(RAPIER);
  const savedSettings = localStorage.getItem("snapkitty.sovereign-interior.settings.v1");
  if (savedSettings) {
    try {
      game.updateSettings(JSON.parse(savedSettings));
    } catch {
      localStorage.removeItem("snapkitty.sovereign-interior.settings.v1");
    }
  }
  game.ready();
  if (new URLSearchParams(location.search).has("test")) {
    globalThis.__SOVEREIGN_TEST__ = game.testAPI();
  }
} catch (error) {
  console.error(error);
  loadingText.textContent = "Initialization failed. Reload to retry.";
  document.querySelector(".loading-line").hidden = true;
}
