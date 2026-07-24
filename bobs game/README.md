# Sovereign Interior

A procedural first-person Three.js and Rapier game set inside a WORM-sealed chamber. The playable loop is:

```text
walk -> inspect artwork -> collect document -> verify evidence
     -> activate terminal -> unlock door -> exit -> seal receipt
```

## Run

```bash
npm run dev
```

Open `http://127.0.0.1:4173`, or play the published build at [snapkittywest.github.io/sov-kernel-monster/bobs-game](https://snapkittywest.github.io/sov-kernel-monster/bobs-game/). Three.js and Rapier are pinned CDN modules; there is no dependency installation or build step.

## Test

```bash
npm test
```

The tests cover quest ordering, authoritative state transitions, SHA-256 receipt chaining, tamper detection, save recovery, and version rejection.

## Controls

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` or arrows | Left stick |
| Look | Mouse | Right stick |
| Interact | `E` | X / Square |
| Jump | `Space` | A / Cross |
| Sprint | `Shift` | Left-stick press |
| Crouch | `C` or `Ctrl` | B / Circle |
| Inventory | `I` or `Tab` | Y / Triangle |
| Pause | `Esc` or `P` | Menu |
| Respawn | `R` | Pause menu |

Touch devices receive a movement stick, drag-to-look, and dedicated action controls.

## Architecture

- `src/core`: fixed game loop, event bus, authoritative store, animation, ledger, save/load.
- `src/physics`: Rapier world, architectural colliders, kinematic player, triggers, dynamic chairs.
- `src/player` and `src/input`: camera rig, movement states, gravity, stance, abstract device actions.
- `src/interaction`: centered camera ray and metadata-driven object actions.
- `src/gameplay`: inventory, commands, quest conditions, item definitions.
- `src/world` and `src/rendering`: procedural level, PBR materials, lighting, quality controls.
- `src/audio`: generated footsteps, UI tones, and positional lamp hum.
- `src/ui`: HUD, pause, settings, inventory, document reader, and completion state.

Durable gameplay events are chained as:

```text
previousHash -> payloadHash -> stateHash -> currentHash
```

Camera motion is deliberately excluded. Saves use verified primary and backup `localStorage` slots and include versioned player, inventory, world, quest, event, and seal data.

The receipt chain is a local, tamper-evident checksum. It detects accidental edits and unsophisticated save manipulation, but it is not an authenticated signature or MAC and cannot establish player identity against a hostile client.
