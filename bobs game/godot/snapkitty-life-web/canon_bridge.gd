## SnapKitty canon and continuity bridge for Godot 4.x.
##
## Install as the CanonBridge autoload. The bridge deliberately has no
## dependency on the SnapKitty native GDExtension, so it can run in native and
## single-threaded Web exports.

extends Node

signal canon_loaded(version: String, character_count: int)
signal canon_load_failed(code: String, detail: String)
signal bindings_loaded(project_id: String)
signal continuity_ready(snapshot: Dictionary)
signal continuity_ingested(snapshot: Dictionary, source: String)
signal continuity_exported(snapshot: Dictionary)
signal continuity_rejected(code: String, detail: String)
signal character_found(character_id: String, character: Dictionary)

const CANON_MAJOR_VERSION := 1
const CANON_FORMATS := [
	"snapkitty-canon",
	"snapkitty-universe-canon",
]
const CONTINUITY_SCHEMA := "snapkitty.universe.continuity"
const CONTINUITY_VERSION := 1
const CONTINUITY_PROTOCOL := "snapkitty.universe.continuity.bridge.v1"
const CONTINUITY_CHANNEL := "snapkitty.universe.continuity.v1"
const GENESIS_HASH := "0000000000000000000000000000000000000000000000000000000000000000"
const EVENT_TYPES := [
	"promise-made", "promise-kept", "promise-broken", "theft", "combat",
	"rescue", "gift", "betrayal", "negotiation", "contract-created",
	"contract-completed", "contract-breached", "lie", "debt-incurred",
	"debt-paid", "realm-entered", "realm-completed", "character-met",
	"dialogue", "discovery", "economy-signal", "mission-signal",
]
const DEFAULT_PROJECT_ID := "snapkitty-life"
const REQUIRED_CANON_COLLECTIONS := [
	"characters",
	"species",
	"locations",
	"experiences",
	"economy",
	"bindings",
]

@export var canon_resource_path := "res://canon/canon.json"
@export var binding_resource_path := "res://canon/v1/bindings.json"
@export var canon_url := "../../canon/canon.json"
@export var binding_url := "../../canon/v1/bindings.json"
@export var continuity_storage_key := "snapkitty.universe.continuity.v1"
@export var continuity_file_path := "user://snapkitty-continuity.v1.json"
@export var load_continuity_on_start := true
@export var poll_interval_seconds := 0.5

var _canon: Dictionary = {}
var _bindings: Dictionary = {}
var _continuity: Dictionary = {}
var _character_index: Dictionary = {}
var _canon_request: HTTPRequest = null
var _canon_descriptor: Dictionary = {}
var _canon_collection_documents: Dictionary = {}
var _canon_collection_queue: Array[String] = []
var _active_canon_collection := ""
var _resolved_canon_url := ""
var _poll_elapsed := 0.0
var _web_bridge_ready := false
var _instance_id := ""


func _ready() -> void:
	_instance_id = "%s-%s" % [Time.get_ticks_usec(), randi()]
	_bindings = _default_bindings()
	if OS.has_feature("web"):
		_install_web_bridge()
		_request_web_canon()
	else:
		_load_canon_from_resource()
	if load_continuity_on_start:
		call_deferred("load_continuity")


func _process(delta: float) -> void:
	if not OS.has_feature("web") or not _web_bridge_ready:
		return
	_poll_elapsed += delta
	if _poll_elapsed < poll_interval_seconds:
		return
	_poll_elapsed = 0.0
	var inbound := _web_read(_inbox_storage_key())
	if inbound.is_empty():
		return
	_web_remove(_inbox_storage_key())
	ingest_continuity_json(inbound, "browser-message", false)


func is_canon_ready() -> bool:
	return not _canon.is_empty()


func get_canon() -> Dictionary:
	return _canon.duplicate(true)


func get_canon_version() -> String:
	return str(_canon.get("version", ""))


func get_bindings() -> Dictionary:
	return _bindings.duplicate(true)


func get_characters() -> Array:
	var source: Variant = _canon.get("characters", [])
	return _collection_as_array(source, "characters")


func get_species() -> Array:
	return _collection_as_array(_canon.get("species", []), "species")


func get_locations() -> Array:
	return _collection_as_array(_canon.get("locations", []), "locations")


func get_experiences() -> Array:
	return _collection_as_array(_canon.get("experiences", []), "experiences")


func get_economy() -> Dictionary:
	var economy: Variant = _canon.get("economy", {})
	return economy.duplicate(true) if economy is Dictionary else {}


func has_character(id_or_alias: String) -> bool:
	return _character_index.has(_lookup_key(id_or_alias))


func get_character(id_or_alias: String) -> Dictionary:
	var character: Variant = _character_index.get(_lookup_key(id_or_alias), {})
	if not character is Dictionary or character.is_empty():
		return {}
	var result: Dictionary = character.duplicate(true)
	character_found.emit(str(result.get("id", result.get("character_id", ""))), result)
	return result


func get_continuity() -> Dictionary:
	return _continuity.duplicate(true)


## Record a project snapshot as a mission-signal event in the shared chain.
## Prefer append_continuity_event for individual player actions.
func export_continuity(project_state: Dictionary, publish := true) -> Dictionary:
	var local_event_id := "snapshot-%s-%s" % [Time.get_ticks_usec(), int(_continuity.get("revision", 0)) + 1]
	return append_continuity_event(
		"mission-signal",
		{"kind": "state-snapshot", "projectState": project_state.duplicate(true)},
		local_event_id,
		"",
		publish
	)


func export_continuity_json(project_state: Dictionary, publish := true) -> String:
	var snapshot := export_continuity(project_state, publish)
	return "" if snapshot.is_empty() else JSON.stringify(snapshot)


func append_continuity_event(
	type: String,
	payload: Dictionary,
	local_event_id: String,
	occurred_at := "",
	publish := true
) -> Dictionary:
	var normalized := _normalize_event_body(type, payload, local_event_id, occurred_at)
	if not normalized.ok:
		continuity_rejected.emit(normalized.code, normalized.detail)
		return {}
	var bodies := _event_bodies(_continuity)
	for body in bodies:
		if body.eventId != normalized.value.eventId:
			continue
		if body.type == normalized.value.type and _canonical_stringify(body.payload) == _canonical_stringify(normalized.value.payload):
			return _continuity.duplicate(true)
		continuity_rejected.emit("idempotency-conflict", "The local event id is already bound to different event data")
		return {}
	bodies.append(normalized.value)
	var rebuilt := _rebuild_continuity(bodies, _now_iso())
	if rebuilt.is_empty() or not _store_and_publish(rebuilt, publish):
		return {}
	return _continuity.duplicate(true)


func ingest_continuity(snapshot: Dictionary, source := "external", persist := true) -> bool:
	var validation := _validate_continuity(snapshot)
	if not validation.ok:
		continuity_rejected.emit(validation.code, validation.detail)
		return false
	var merged := _merge_continuity(_continuity, snapshot)
	if merged.is_empty():
		return false
	_continuity = merged
	if persist and not _persist_continuity(_continuity):
		continuity_rejected.emit("storage-write-failed", "Continuity could not be persisted")
		return false
	continuity_ingested.emit(_continuity.duplicate(true), source)
	continuity_ready.emit(_continuity.duplicate(true))
	return true


func ingest_continuity_json(text: String, source := "external", persist := true) -> bool:
	var parsed := _parse_json(text, "continuity")
	if not parsed.ok:
		continuity_rejected.emit(parsed.code, parsed.detail)
		return false
	if not parsed.value is Dictionary:
		continuity_rejected.emit("invalid-continuity-type", "Continuity root must be an object")
		return false
	return ingest_continuity(parsed.value, source, persist)


func load_continuity() -> bool:
	var source := "browser-storage" if OS.has_feature("web") else "user-file"
	var primary := _web_read(continuity_storage_key) if OS.has_feature("web") else _read_text_file(continuity_file_path)
	if not primary.is_empty() and ingest_continuity_json(primary, source, false):
		return true
	var backup := _web_read(continuity_storage_key + ".backup") if OS.has_feature("web") else _read_text_file(continuity_file_path + ".backup")
	if backup.is_empty() or not ingest_continuity_json(backup, source + "-backup", false):
		return false
	_persist_continuity(_continuity)
	return true


func clear_continuity() -> void:
	_continuity.clear()
	if OS.has_feature("web"):
		_web_remove(continuity_storage_key)
		_web_remove(continuity_storage_key + ".backup")
		_web_remove(_inbox_storage_key())
	else:
		if FileAccess.file_exists(continuity_file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(continuity_file_path))
		if FileAccess.file_exists(continuity_file_path + ".backup"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(continuity_file_path + ".backup"))


func load_canon_text(text: String, source := "manual") -> bool:
	var parsed := _parse_json(text, "canon")
	if not parsed.ok:
		canon_load_failed.emit(parsed.code, "%s: %s" % [source, parsed.detail])
		return false
	if not parsed.value is Dictionary:
		canon_load_failed.emit("invalid-canon-type", "%s: Canon root must be an object" % source)
		return false
	var validation := _validate_canon(parsed.value)
	if not validation.ok:
		canon_load_failed.emit(validation.code, "%s: %s" % [source, validation.detail])
		return false
	_canon = parsed.value.duplicate(true)
	_rebuild_character_index()
	canon_loaded.emit(str(_canon.version), get_characters().size())
	return true


func _request_web_canon() -> void:
	if canon_url.strip_edges().is_empty():
		_load_canon_from_resource()
		return
	_canon_descriptor.clear()
	_canon_collection_documents.clear()
	_canon_collection_queue.clear()
	_resolved_canon_url = _web_resolve_url(canon_url)
	_active_canon_collection = "__descriptor__"
	_start_web_canon_request(_resolved_canon_url)


func _start_web_canon_request(url: String) -> void:
	_canon_request = HTTPRequest.new()
	_canon_request.name = "CanonRequest_%s" % _active_canon_collection
	add_child(_canon_request)
	_canon_request.request_completed.connect(_on_canon_request_completed)
	var error := _canon_request.request(url)
	if error != OK:
		_canon_request.queue_free()
		_canon_request = null
		_load_canon_from_resource("web-request-start-failed:%s:%s" % [_active_canon_collection, error])


func _on_canon_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed_collection := _active_canon_collection
	if is_instance_valid(_canon_request):
		_canon_request.queue_free()
	_canon_request = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_load_canon_from_resource("web-fetch-failed:%s:%s:%s" % [completed_collection, result, response_code])
		return
	var parsed := _parse_json(body.get_string_from_utf8(), "canon-%s" % completed_collection)
	if not parsed.ok or not parsed.value is Dictionary:
		_load_canon_from_resource("web-json-invalid:%s" % completed_collection)
		return
	if completed_collection == "__descriptor__":
		if _is_monolithic_canon(parsed.value):
			if load_canon_text(body.get_string_from_utf8(), _resolved_canon_url):
				return
			_load_canon_from_resource("web-monolith-invalid")
			return
		var descriptor_validation := _validate_canon_descriptor(parsed.value)
		if not descriptor_validation.ok:
			_load_canon_from_resource(descriptor_validation.code)
			return
		_canon_descriptor = parsed.value.duplicate(true)
		_canon_collection_queue.assign(REQUIRED_CANON_COLLECTIONS)
		_request_next_web_collection()
		return
	var collection_validation := _validate_collection_document(completed_collection, parsed.value)
	if not collection_validation.ok:
		_load_canon_from_resource(collection_validation.code)
		return
	_canon_collection_documents[completed_collection] = parsed.value.duplicate(true)
	_request_next_web_collection()


func _request_next_web_collection() -> void:
	if _canon_collection_queue.is_empty():
		_assemble_and_load_canon(_canon_descriptor, _canon_collection_documents, "web-split")
		return
	_active_canon_collection = _canon_collection_queue.pop_front()
	var url := _collection_web_url(_active_canon_collection)
	if url.is_empty():
		_load_canon_from_resource("collection-url-missing:%s" % _active_canon_collection)
		return
	_start_web_canon_request(url)


func _collection_web_url(collection_name: String) -> String:
	if collection_name == "bindings" and not binding_url.strip_edges().is_empty():
		return _web_resolve_url(binding_url)
	var descriptor: Variant = _canon_descriptor.get("collections", {}).get(collection_name, null)
	var path := str(descriptor.get("path", "")) if descriptor is Dictionary else str(descriptor)
	return "" if path.is_empty() else _web_resolve_against(path, _resolved_canon_url)


func _load_canon_from_resource(prior_error := "") -> void:
	var text := _read_text_file(canon_resource_path)
	if text.is_empty():
		var detail := "Bundled canon is missing or empty at %s" % canon_resource_path
		if not prior_error.is_empty():
			detail = "%s; %s" % [prior_error, detail]
		canon_load_failed.emit("canon-unavailable", detail)
		return
	var parsed := _parse_json(text, "canon-descriptor")
	if not parsed.ok or not parsed.value is Dictionary:
		canon_load_failed.emit("invalid-canon-descriptor", canon_resource_path)
		return
	if _is_monolithic_canon(parsed.value):
		load_canon_text(text, canon_resource_path)
		return
	var descriptor_validation := _validate_canon_descriptor(parsed.value)
	if not descriptor_validation.ok:
		canon_load_failed.emit(descriptor_validation.code, descriptor_validation.detail)
		return
	var documents: Dictionary = {}
	for collection_name in REQUIRED_CANON_COLLECTIONS:
		var path := binding_resource_path if collection_name == "bindings" else _collection_resource_path(parsed.value, collection_name)
		var collection_text := _read_text_file(path)
		var collection := _parse_json(collection_text, "canon-%s" % collection_name)
		if not collection.ok or not collection.value is Dictionary:
			canon_load_failed.emit("bundled-collection-unavailable", "%s at %s" % [collection_name, path])
			return
		var collection_validation := _validate_collection_document(collection_name, collection.value)
		if not collection_validation.ok:
			canon_load_failed.emit(collection_validation.code, collection_validation.detail)
			return
		documents[collection_name] = collection.value.duplicate(true)
	_assemble_and_load_canon(parsed.value, documents, "bundled-split")


func _collection_resource_path(descriptor: Dictionary, collection_name: String) -> String:
	var entry: Variant = descriptor.get("collections", {}).get(collection_name, null)
	var relative_path := str(entry.get("path", "")) if entry is Dictionary else str(entry)
	return canon_resource_path.get_base_dir().path_join(relative_path) if not relative_path.is_empty() else ""


func _load_bindings_text(text: String) -> bool:
	var parsed := _parse_json(text, "bindings")
	if not parsed.ok or not parsed.value is Dictionary:
		return false
	if _major_version(parsed.value.get("version", 0)) != CANON_MAJOR_VERSION:
		return false
	_install_bindings_document(parsed.value)
	return true


func _install_bindings_document(document: Dictionary) -> void:
	_bindings = _default_bindings()
	_bindings["canon"] = document.duplicate(true)
	_bindings["bindings"] = document.get("bindings", []).duplicate(true) if document.get("bindings", null) is Array else []
	bindings_loaded.emit(_project_id())


func _validate_canon(value: Dictionary) -> Dictionary:
	var format := str(value.get("format", value.get("canonId", "")))
	if format not in CANON_FORMATS and format != "snapkitty-universe":
		return _failure("unsupported-canon-format", "Expected one of %s, received '%s'" % [CANON_FORMATS, format])
	if _major_version(value.get("version", 0)) != CANON_MAJOR_VERSION:
		return _failure("unsupported-canon-version", "Canon major version must be %s" % CANON_MAJOR_VERSION)
	for key in ["characters", "species", "locations"]:
		var collection: Variant = value.get(key, null)
		if not collection is Array and not collection is Dictionary:
			return _failure("invalid-canon-section", "Canon '%s' must be an array or object" % key)
	if not value.get("economy", null) is Dictionary:
		return _failure("invalid-canon-section", "Canon 'economy' must be an object")
	var seen: Dictionary = {}
	for character in _collection_as_array(value.characters, "characters"):
		if not character is Dictionary:
			return _failure("invalid-character", "Every character must be an object")
		var character_id := str(character.get("id", character.get("character_id", ""))).strip_edges()
		var character_name := str(character.get("name", character.get("canonical_name", character.get("display_name", "")))).strip_edges()
		if character_id.is_empty() or character_name.is_empty():
			return _failure("invalid-character", "Every character requires an id and name")
		if seen.has(character_id):
			return _failure("duplicate-character", "Duplicate character id '%s'" % character_id)
		seen[character_id] = true
	return _success(value)


func _validate_continuity(value: Dictionary) -> Dictionary:
	if not _has_exact_keys(value, ["schema", "version", "revision", "updatedAt", "headHash", "events"]):
		return _failure("invalid-continuity-fields", "Continuity document fields do not match schema version 1")
	if str(value.get("schema", "")) != CONTINUITY_SCHEMA:
		return _failure("unsupported-continuity-schema", "Expected '%s'" % CONTINUITY_SCHEMA)
	if _major_version(value.get("version", 0)) != CONTINUITY_VERSION:
		return _failure("unsupported-continuity-version", "Continuity major version must be %s" % CONTINUITY_VERSION)
	var events: Variant = value.get("events", null)
	if not events is Array:
		return _failure("invalid-continuity-events", "Continuity events must be an array")
	if int(value.get("revision", -1)) != events.size():
		return _failure("invalid-continuity-revision", "Continuity revision must equal the event count")
	if not _is_hash(str(value.get("headHash", ""))):
		return _failure("invalid-continuity-head", "Continuity headHash must be a lowercase SHA-256 digest")
	if not _is_canonical_timestamp(str(value.get("updatedAt", ""))):
		return _failure("invalid-continuity-time", "Continuity updatedAt must be canonical UTC ISO-8601")
	var previous_hash := GENESIS_HASH
	var previous_body: Dictionary = {}
	var seen: Dictionary = {}
	for index in range(events.size()):
		var event: Variant = events[index]
		if not event is Dictionary:
			return _failure("invalid-continuity-event", "Event %s must be an object" % index)
		if not _has_exact_keys(event, ["eventId", "sourceExperienceId", "localEventId", "type", "occurredAt", "payload", "previousHash", "hash"]):
			return _failure("invalid-continuity-event-fields", "Event %s fields do not match schema version 1" % index)
		var body := _event_body(event)
		var event_validation := _validate_event_body(body)
		if not event_validation.ok:
			return event_validation
		if seen.has(body.eventId):
			return _failure("duplicate-continuity-event", "Duplicate event id '%s'" % body.eventId)
		seen[body.eventId] = true
		if not previous_body.is_empty() and _event_before(body, previous_body):
			return _failure("invalid-continuity-order", "Continuity events are not canonically ordered")
		if str(event.get("previousHash", "")) != previous_hash:
			return _failure("broken-continuity-link", "Hash chain is broken at event %s" % index)
		var material := body.duplicate(true)
		material["previousHash"] = previous_hash
		var expected_hash := _sha256_hex(_canonical_stringify(material))
		if str(event.get("hash", "")) != expected_hash:
			return _failure("invalid-continuity-hash", "Hash mismatch at event %s" % index)
		previous_hash = expected_hash
		previous_body = body
	if str(value.headHash) != previous_hash:
		return _failure("invalid-continuity-head", "Continuity headHash does not match the chain tip")
	return _success(value)


func _rebuild_character_index() -> void:
	_character_index.clear()
	for character in get_characters():
		if not character is Dictionary:
			continue
		var canonical: Dictionary = character.duplicate(true)
		var character_id := str(canonical.get("id", canonical.get("character_id", "")))
		var character_name := str(canonical.get("name", canonical.get("canonical_name", canonical.get("display_name", ""))))
		_index_character_key(character_id, canonical)
		_index_character_key(character_name, canonical)
		var aliases: Variant = canonical.get("aliases", [])
		if aliases is Array:
			for alias in aliases:
				_index_character_key(str(alias), canonical)


func _index_character_key(value: String, character: Dictionary) -> void:
	var key := _lookup_key(value)
	if not key.is_empty() and not _character_index.has(key):
		_character_index[key] = character


func _lookup_key(value: String) -> String:
	return value.strip_edges().to_lower().replace("_", "-").replace(" ", "-")


func _collection_as_array(value: Variant, collection_key := "") -> Array:
	if value is Array:
		return value.duplicate(true)
	if value is Dictionary:
		if not collection_key.is_empty() and value.get(collection_key, null) is Array:
			return value[collection_key].duplicate(true)
		var result: Array = []
		for key in value:
			var entry: Variant = value[key]
			if entry is Dictionary:
				var copy: Dictionary = entry.duplicate(true)
				if not copy.has("id") and not copy.has("character_id"):
					copy["id"] = str(key)
				result.append(copy)
			else:
				result.append(entry)
		return result
	return []


func _project_id() -> String:
	return str(_bindings.get("project_id", DEFAULT_PROJECT_ID))


func _empty_continuity(updated_at := "") -> Dictionary:
	return {
		"schema": CONTINUITY_SCHEMA,
		"version": CONTINUITY_VERSION,
		"revision": 0,
		"updatedAt": _now_iso() if updated_at.is_empty() else updated_at,
		"headHash": GENESIS_HASH,
		"events": [],
	}


func _normalize_event_body(type: String, payload: Dictionary, local_event_id: String, occurred_at: String) -> Dictionary:
	var source_id := _project_id().strip_edges()
	var local_id := local_event_id.strip_edges()
	if source_id.is_empty() or source_id.length() > 256:
		return _failure("invalid-source-experience", "sourceExperienceId must be 1-256 characters")
	if local_id.is_empty() or local_id.length() > 256:
		return _failure("invalid-local-event-id", "localEventId must be 1-256 characters")
	if type not in EVENT_TYPES:
		return _failure("unknown-event-type", "Unknown continuity event type '%s'" % type)
	var body := {
		"eventId": "%s::%s" % [source_id.uri_encode(), local_id.uri_encode()],
		"sourceExperienceId": source_id,
		"localEventId": local_id,
		"type": type,
		"occurredAt": _now_iso() if occurred_at.strip_edges().is_empty() else occurred_at,
		"payload": payload.duplicate(true),
	}
	var validation := _validate_event_body(body)
	return validation if not validation.ok else _success(body)


func _validate_event_body(body: Dictionary) -> Dictionary:
	if not _has_exact_keys(body, ["eventId", "sourceExperienceId", "localEventId", "type", "occurredAt", "payload"]):
		return _failure("invalid-continuity-event-fields", "Event body fields do not match schema version 1")
	for key in ["eventId", "sourceExperienceId", "localEventId", "type", "occurredAt"]:
		var text := str(body.get(key, "")).strip_edges()
		if text.is_empty() or text.length() > 256:
			return _failure("invalid-continuity-event", "Event field '%s' must be 1-256 characters" % key)
	var expected_id := "%s::%s" % [
		str(body.sourceExperienceId).uri_encode(),
		str(body.localEventId).uri_encode(),
	]
	if body.eventId != expected_id:
		return _failure("invalid-continuity-event-id", "eventId does not match its idempotency key")
	if body.type not in EVENT_TYPES:
		return _failure("unknown-event-type", "Unknown continuity event type '%s'" % body.type)
	if not _is_canonical_timestamp(str(body.occurredAt)):
		return _failure("invalid-event-time", "occurredAt must use YYYY-MM-DDTHH:MM:SS.sssZ")
	if not body.get("payload", null) is Dictionary:
		return _failure("invalid-event-payload", "Continuity payload must be an object")
	if not _is_json_value(body.payload):
		return _failure("invalid-event-payload", "Continuity payload must contain only finite JSON values")
	var typed_validation := _validate_typed_payload(str(body.type), body.payload)
	if not typed_validation.ok:
		return typed_validation
	return _success(body)


func _validate_typed_payload(type: String, payload: Dictionary) -> Dictionary:
	for key in ["characterId", "factionId", "realmId", "commitmentId", "contractId", "debtId", "discoveryId"]:
		if payload.has(key) and not _valid_identifier(payload[key]):
			return _failure("invalid-event-payload", "payload.%s must be a non-empty string no longer than 256 characters" % key)
	for key in ["trustDelta", "reputationDelta"]:
		if payload.has(key) and not _finite_number(payload[key]):
			return _failure("invalid-event-payload", "payload.%s must be a finite number" % key)
	if type in ["promise-made", "promise-kept", "promise-broken"] and not _valid_identifier(payload.get("commitmentId", null)):
		return _failure("invalid-event-payload", "Promise events require payload.commitmentId")
	if type in ["contract-created", "contract-completed", "contract-breached"] and not _valid_identifier(payload.get("contractId", null)):
		return _failure("invalid-event-payload", "Contract events require payload.contractId")
	if type in ["debt-incurred", "debt-paid"]:
		if not _valid_identifier(payload.get("debtId", null)):
			return _failure("invalid-event-payload", "Debt events require payload.debtId")
		if not _finite_number(payload.get("amount", null)) or float(payload.amount) <= 0.0:
			return _failure("invalid-event-payload", "Debt events require a positive payload.amount")
		if payload.has("currency") and not _valid_identifier(payload.currency):
			return _failure("invalid-event-payload", "payload.currency must be a valid identifier")
	if type in ["realm-entered", "realm-completed"] and not _valid_identifier(payload.get("realmId", null)):
		return _failure("invalid-event-payload", "Realm events require payload.realmId")
	if type in ["character-met", "dialogue"] and not _valid_identifier(payload.get("characterId", null)):
		return _failure("invalid-event-payload", "Character events require payload.characterId")
	if type == "discovery" and not _valid_identifier(payload.get("discoveryId", null)):
		return _failure("invalid-event-payload", "Discovery events require payload.discoveryId")
	return _success(payload)


func _valid_identifier(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 256


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _is_json_value(value: Variant) -> bool:
	if value == null or value is String or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for entry in value:
			if not _is_json_value(entry):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _is_json_value(value[key]):
				return false
		return true
	return false


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func _event_body(event: Dictionary) -> Dictionary:
	return {
		"eventId": event.get("eventId", ""),
		"sourceExperienceId": event.get("sourceExperienceId", ""),
		"localEventId": event.get("localEventId", ""),
		"type": event.get("type", ""),
		"occurredAt": event.get("occurredAt", ""),
		"payload": event.get("payload", {}).duplicate(true) if event.get("payload", null) is Dictionary else null,
	}


func _event_bodies(document: Dictionary) -> Array:
	var result: Array = []
	var events: Variant = document.get("events", [])
	if events is Array:
		for event in events:
			if event is Dictionary:
				result.append(_event_body(event))
	return result


func _merge_continuity(left: Dictionary, right: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}
	for body in _event_bodies(left) + _event_bodies(right):
		var event_id := str(body.eventId)
		if by_id.has(event_id):
			if _canonical_stringify(by_id[event_id]) != _canonical_stringify(body):
				continuity_rejected.emit("idempotency-conflict", "Conflicting continuity event '%s'" % event_id)
				return {}
		else:
			by_id[event_id] = body
	var bodies: Array = by_id.values()
	var updated_at := str(left.get("updatedAt", ""))
	if str(right.get("updatedAt", "")) > updated_at:
		updated_at = str(right.updatedAt)
	return _rebuild_continuity(bodies, updated_at)


func _rebuild_continuity(event_bodies: Array, updated_at: String) -> Dictionary:
	var bodies := event_bodies.duplicate(true)
	bodies.sort_custom(_event_before)
	var events: Array = []
	var previous_hash := GENESIS_HASH
	for body in bodies:
		if not body is Dictionary:
			continuity_rejected.emit("invalid-continuity-event", "Cannot rebuild a non-object event")
			return {}
		var validation := _validate_event_body(body)
		if not validation.ok:
			continuity_rejected.emit(validation.code, validation.detail)
			return {}
		var material: Dictionary = body.duplicate(true)
		material["previousHash"] = previous_hash
		var hash := _sha256_hex(_canonical_stringify(material))
		material["hash"] = hash
		events.append(material)
		previous_hash = hash
	return {
		"schema": CONTINUITY_SCHEMA,
		"version": CONTINUITY_VERSION,
		"revision": events.size(),
		"updatedAt": _now_iso() if updated_at.is_empty() else updated_at,
		"headHash": previous_hash,
		"events": events,
	}


func _event_before(left: Dictionary, right: Dictionary) -> bool:
	for key in ["occurredAt", "sourceExperienceId", "localEventId", "type"]:
		var left_value := str(left.get(key, ""))
		var right_value := str(right.get(key, ""))
		if left_value != right_value:
			return left_value < right_value
	return false


func _canonical_stringify(value: Variant) -> String:
	if value == null or value is String or value is bool:
		return JSON.stringify(value)
	if value is int:
		return str(value)
	if value is float:
		return str(int(value)) if value == floor(value) else JSON.stringify(value)
	if value is Array:
		var entries: PackedStringArray = []
		for entry in value:
			entries.append(_canonical_stringify(entry))
		return "[" + ",".join(entries) + "]"
	if value is Dictionary:
		var keys := value.keys()
		keys.sort()
		var fields: PackedStringArray = []
		for key in keys:
			fields.append("%s:%s" % [JSON.stringify(str(key)), _canonical_stringify(value[key])])
		return "{" + ",".join(fields) + "}"
	return JSON.stringify(value)


func _sha256_hex(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _is_canonical_timestamp(value: String) -> bool:
	if value.length() != 24:
		return false
	var pattern := RegEx.new()
	if pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$") != OK:
		return false
	return pattern.search(value) != null


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true, false) + ".000Z"


func _store_and_publish(snapshot: Dictionary, publish: bool) -> bool:
	if not _persist_continuity(snapshot):
		continuity_rejected.emit("storage-write-failed", "Continuity could not be persisted")
		return false
	_continuity = snapshot.duplicate(true)
	if publish and OS.has_feature("web"):
		_web_publish(_continuity)
	continuity_exported.emit(_continuity.duplicate(true))
	continuity_ready.emit(_continuity.duplicate(true))
	return true


func _major_version(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var text := str(value).strip_edges()
	return int(text.get_slice(".", 0)) if not text.is_empty() else 0


func _parse_json(text: String, label: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return _failure("empty-%s" % label, "%s JSON is empty" % label.capitalize())
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		return _failure("invalid-%s-json" % label, "%s at line %s" % [parser.get_error_message(), parser.get_error_line()])
	return _success(parser.data)


func _read_text_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _persist_continuity(snapshot: Dictionary) -> bool:
	var text := _canonical_stringify(snapshot)
	if OS.has_feature("web"):
		var previous := _web_read(continuity_storage_key)
		if not previous.is_empty():
			_web_write(continuity_storage_key + ".backup", previous)
		if not _web_write(continuity_storage_key, text):
			return false
		if _web_read(continuity_storage_key) != text:
			return false
		return _web_write(continuity_storage_key + ".backup", text)
	var temporary_path := continuity_file_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	var source := ProjectSettings.globalize_path(temporary_path)
	var target := ProjectSettings.globalize_path(continuity_file_path)
	var backup := ProjectSettings.globalize_path(continuity_file_path + ".backup")
	if FileAccess.file_exists(continuity_file_path):
		DirAccess.copy_absolute(target, backup)
		DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(source, target) == OK


func _default_bindings() -> Dictionary:
	return {
		"format": "snapkitty-canon-binding",
		"version": 1,
		"project_id": DEFAULT_PROJECT_ID,
		"state_schema": "snapkitty-life/v1",
	}


func _install_web_bridge() -> void:
	var script := """
(() => {
  const root = window;
  const name = "SnapKittyCanonBridgeV1";
  const bridge = root[name] || {};
  const decode = (value) => new TextDecoder().decode(
    Uint8Array.from(atob(value), (char) => char.charCodeAt(0))
  );
  bridge.read = (key64) => {
    try { return root.localStorage.getItem(decode(key64)) || ""; }
    catch (_) { return ""; }
  };
  bridge.write = (key64, value64) => {
    try { root.localStorage.setItem(decode(key64), decode(value64)); return true; }
    catch (_) { return false; }
  };
  bridge.remove = (key64) => {
    try { root.localStorage.removeItem(decode(key64)); return true; }
    catch (_) { return false; }
  };
  bridge.resolve = (url64) => {
    try { return new URL(decode(url64), root.location.href).href; }
    catch (_) { return ""; }
  };
  bridge.listeners = bridge.listeners || new Set();
  bridge.channels = bridge.channels || new Map();
  bridge.listen = (key64, inbox64, channel64, protocol64, sender64) => {
    const key = decode(key64), inbox = decode(inbox64), channel = decode(channel64);
    const protocol = decode(protocol64), sender = decode(sender64);
    const signature = `${key}|${inbox}|${channel}|${sender}`;
    if (bridge.listeners.has(signature)) return true;
    const accept = (message) => {
      if (!message || message.protocol !== protocol || message.kind !== "snapshot") return;
      if (message.senderId === sender || !message.snapshot) return;
      root.localStorage.setItem(inbox, JSON.stringify(message.snapshot));
    };
    root.addEventListener("storage", (event) => {
      if (event.key === key && event.newValue) root.localStorage.setItem(inbox, event.newValue);
    });
    root.addEventListener("message", (event) => {
      if (event.origin !== root.location.origin) return;
      accept(event.data);
    });
    if (typeof root.BroadcastChannel === "function") {
      const receiver = new root.BroadcastChannel(channel);
      receiver.addEventListener("message", (event) => accept(event.data));
      bridge.channels.set(signature, receiver);
    }
    bridge.listeners.add(signature);
    return true;
  };
  bridge.publish = (channel64, protocol64, sender64, value64) => {
    try {
      const channel = decode(channel64);
      const message = {protocol: decode(protocol64), kind: "snapshot",
        senderId: decode(sender64), snapshot: JSON.parse(decode(value64))};
      const origin = root.location.origin;
      if (typeof root.BroadcastChannel === "function") {
        const publisher = new root.BroadcastChannel(channel);
        publisher.postMessage(message);
        publisher.close();
      }
      root.postMessage(message, origin);
      if (root.parent && root.parent !== root) root.parent.postMessage(message, origin);
      if (root.opener && !root.opener.closed) root.opener.postMessage(message, origin);
      return true;
    } catch (_) { return false; }
  };
  root[name] = bridge;
  return true;
})()
"""
	_web_bridge_ready = bool(JavaScriptBridge.eval(script, false))
	if _web_bridge_ready:
		var expression := "window.SnapKittyCanonBridgeV1.listen('%s','%s','%s','%s','%s')" % [
			_to_base64(continuity_storage_key),
			_to_base64(_inbox_storage_key()),
			_to_base64(CONTINUITY_CHANNEL),
			_to_base64(CONTINUITY_PROTOCOL),
			_to_base64(_instance_id),
		]
		JavaScriptBridge.eval(expression, false)


func _web_read(key: String) -> String:
	if not _web_bridge_ready:
		return ""
	var result: Variant = JavaScriptBridge.eval(
		"window.SnapKittyCanonBridgeV1.read('%s')" % _to_base64(key), false
	)
	return str(result) if result != null else ""


func _web_resolve_url(url: String) -> String:
	if not _web_bridge_ready:
		return url
	var result: Variant = JavaScriptBridge.eval(
		"window.SnapKittyCanonBridgeV1.resolve('%s')" % _to_base64(url), false
	)
	var resolved := str(result) if result != null else ""
	return url if resolved.is_empty() else resolved


func _web_write(key: String, value: String) -> bool:
	if not _web_bridge_ready:
		return false
	return bool(JavaScriptBridge.eval(
		"window.SnapKittyCanonBridgeV1.write('%s','%s')" % [_to_base64(key), _to_base64(value)], false
	))


func _web_remove(key: String) -> bool:
	if not _web_bridge_ready:
		return false
	return bool(JavaScriptBridge.eval(
		"window.SnapKittyCanonBridgeV1.remove('%s')" % _to_base64(key), false
	))


func _web_publish(snapshot: Dictionary) -> bool:
	if not _web_bridge_ready:
		return false
	return bool(JavaScriptBridge.eval(
		"window.SnapKittyCanonBridgeV1.publish('%s','%s','%s','%s')" % [
			_to_base64(CONTINUITY_CHANNEL),
			_to_base64(CONTINUITY_PROTOCOL),
			_to_base64(_instance_id),
			_to_base64(_canonical_stringify(snapshot)),
		], false
	))


func _to_base64(value: String) -> String:
	return Marshalls.raw_to_base64(value.to_utf8_buffer())


func _inbox_storage_key() -> String:
	return continuity_storage_key + ".inbox." + _instance_id


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "code": "", "detail": ""}


func _failure(code: String, detail: String) -> Dictionary:
	return {"ok": false, "value": null, "code": code, "detail": detail}
