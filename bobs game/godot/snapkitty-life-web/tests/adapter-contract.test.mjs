import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");

test("autoload bridge exposes canon and continuity contracts", async () => {
  const source = await read("canon_bridge.gd");

  for (const contract of [
    "signal canon_loaded",
    "signal canon_load_failed",
    "signal continuity_ingested",
    "signal continuity_exported",
    "func get_character(",
    "func get_characters(",
    "func export_continuity(",
    "func append_continuity_event(",
    "func ingest_continuity(",
    "func ingest_continuity_json(",
    "func load_continuity(",
  ]) {
    assert.match(source, new RegExp(contract.replace(/[(/[\]]/g, "\\$&")));
  }

  assert.match(source, /OS\.has_feature\("web"\)/);
  assert.match(source, /JavaScriptBridge\.eval/);
  assert.match(source, /localStorage/);
  assert.match(source, /postMessage/);
  assert.match(source, /user:\/\/snapkitty-continuity\.v1\.json/);
  assert.match(source, /unsupported-canon-format/);
  assert.match(source, /unsupported-canon-version/);
  assert.match(source, /idempotency-conflict/);
  assert.match(source, /snapkitty\.universe\.continuity\.bridge\.v1/);
  assert.match(source, /BroadcastChannel/);
  assert.match(source, /func _canonical_stringify/);
  assert.match(source, /HashingContext\.HASH_SHA256/);
});

test("web preset is compatibility-oriented and single threaded", async () => {
  const preset = await read("export_presets.cfg");
  const overrides = await read("project.web-overrides.godot");

  assert.match(preset, /platform="Web"/);
  assert.match(preset, /variant\/thread_support=false/);
  assert.match(preset, /variant\/extensions_support=false/);
  assert.match(preset, /export_path="build\/web\/index\.html"/);
  assert.match(overrides, /renderer\/rendering_method="gl_compatibility"/);
  assert.match(overrides, /CanonBridge="\*res:\/\/integrations\/snapkitty-life-web\/canon_bridge\.gd"/);
});

test("binding file declares the frozen project's extension boundary", async () => {
  const binding = JSON.parse(await read("bindings/snapkitty-life.v1.json"));

  assert.equal(binding.format, "snapkitty-canon-binding");
  assert.equal(binding.version, 1);
  assert.equal(binding.project_id, "snapkitty-life");
  assert.equal(binding.canon.shared_source, "../../../canon/v1/canon.json");
  assert.equal(binding.native_extension.bridge_dependency, false);
  assert.equal(binding.continuity.schema, "snapkitty.universe.continuity");
  assert.deepEqual(binding.native_extension.required_classes, ["SnapKittyWorld", "SnapKittyPara"]);
  assert.ok(binding.legacy_save.preserve_fields.includes("worm_head"));
});

test("README keeps integration copy-in and does not claim an export", async () => {
  const readme = await read("README.md");

  assert.match(readme, /copy-in adapter/i);
  assert.match(readme, /does not contain a generated Godot Web export/i);
  assert.match(readme, /SnapKittyWorld/);
  assert.match(readme, /SnapKittyPara/);
});
