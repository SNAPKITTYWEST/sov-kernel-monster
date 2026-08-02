# SnapKitty Life Web Adapter

This is an isolated, pure-GDScript copy-in adapter for the frozen **SnapKitty Life** Godot project. It connects that game to the shared SnapKitty canon and continuity state without changing either frozen source tree.

This directory does not contain a generated Godot Web export. A working browser build still requires Godot 4.6 export templates and a browser-compatible implementation of the game's native simulation classes.

## Contracts

`canon_bridge.gd` is intended to run as the `CanonBridge` autoload. It:

- fetches `../../canon/v1/canon.json` first in Web exports;
- falls back to bundled `res://canon/v1/canon.json` on native builds or failed Web fetches;
- accepts canon format `snapkitty-canon` or `snapkitty-universe-canon`, major version `1`;
- validates the top-level `characters`, `species`, `locations`, and `economy` sections;
- indexes character IDs, names, and aliases for deterministic lookup;
- persists the shared append-only `{schema, version, revision, updatedAt, headHash, events}` continuity document at the origin-wide `snapkitty.universe.continuity.v1` localStorage key;
- verifies and rebuilds the same canonical SHA-256 event chain used by the browser `ContinuityStore`;
- uses `BroadcastChannel` plus same-origin `postMessage` for embedded, parent, opener, and sibling-tab coordination;
- persists to `user://snapkitty-continuity.v1.json` outside the browser;
- rejects malformed, unsupported, and stale continuity snapshots with stable error codes.

The browser canon and binding URLs are exported properties. Override `canon_url` and `binding_url` before export if the deployed directory layout changes. Empty URLs force the bundled-resource path.

## Safe Copy Integration

Do not edit the frozen project in place. Make a writable integration copy, then run these steps inside that copy:

1. Create `res://integrations/snapkitty-life-web/` and copy `canon_bridge.gd` into it.
2. Copy the shared `bobs game/canon/v1/canon.json` to `res://canon/v1/canon.json`.
3. Copy `bobs game/canon/v1/bindings/godot.json` to `res://canon/v1/bindings/godot.json` when it exists. Until then, use `bindings/snapkitty-life.v1.json` at that destination.
4. Merge the sections in `project.web-overrides.godot` into the copied project's `project.godot`. Do not replace unrelated project settings.
5. Copy `export_presets.cfg` to the copied project root, or reproduce its Web preset in the Godot editor.
6. Record individual actions through `CanonBridge.append_continuity_event(type, payload, local_event_id)`. Use a stable local event ID so repeated delivery is idempotent. `export_continuity(project_state)` is a convenience wrapper that records a `mission-signal` state snapshot.
7. Restore through `continuity_ready` or `continuity_ingested`. Keep the existing WORM token fields listed in the binding file inside the `snapkitty-life` snapshot payload.
8. Validate the integration copy natively before attempting a Web export.

The static adapter contract can be checked without Godot:

```powershell
node --test tests/adapter-contract.test.mjs
```

## GDExtension Boundary

The frozen project declares `res://gdextension/snapkitty_npc.gdextension` and directly references `SnapKittyWorld` and `SnapKittyPara`. Those classes are not implemented by this bridge. The default Web preset therefore keeps `variant/extensions_support=false`; it is the portable, single-threaded baseline and does not imply that extension-dependent scenes can launch.

Choose one gameplay path in the writable integration copy:

1. **WebAssembly extension:** compile the existing GDExtension and all transitive native libraries for the Godot Web target, use export templates built with dynamic linking, add a Web library entry to the `.gdextension` descriptor, set `variant/extensions_support=true`, and serve with the cross-origin isolation requirements imposed by that export configuration.
2. **Pure-GDScript gameplay fallback:** implement API-compatible replacements for `SnapKittyWorld` and `SnapKittyPara`, then replace native class construction in the integration copy with explicit preloads selected for Web. Validate memory-chain hashing, relationship updates, needs, world ticks, and save hydration against the native implementation before exporting.

Do not register GDScript `class_name` fallbacks alongside the native extension under the same names; Godot will see duplicate global classes. Select one implementation per integration build.

Godot Web exports require the Compatibility renderer. Thread support is disabled here so the build can run on ordinary HTTPS hosting without requiring `SharedArrayBuffer` isolation headers. Godot's official Web export documentation covers the renderer, threading, and extension requirements: <https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html>.

## Public API

- `get_canon()`, `get_canon_version()`, `get_characters()`, `get_character(id_or_alias)`
- `get_species()`, `get_locations()`, `get_economy()`, `get_bindings()`
- `append_continuity_event(type, payload, local_event_id, occurred_at, publish)`
- `export_continuity(project_state, publish)`, `export_continuity_json(...)`
- `ingest_continuity(snapshot, source, persist)`, `ingest_continuity_json(...)`
- `load_continuity()`, `get_continuity()`, `clear_continuity()`

Signals expose canon readiness/failure, binding readiness, continuity readiness/import/export/rejection, and successful character lookup.
