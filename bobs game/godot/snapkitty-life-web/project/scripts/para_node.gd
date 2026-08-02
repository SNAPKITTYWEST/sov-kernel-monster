# ParaNode — Sovereign NPC character for KittyVerse
# Uses NpcBrain (pure GDScript) — no Rust GDExtension needed for Phase 1.
# Handles movement, drawing, autonomous need-satisfaction, and NOVA dialogue.

extends CharacterBody2D

signal dialogue_ready(npc_name: String, response: String, tone: String)
signal needs_critical(npc_name: String, need: String)

enum ParaState { IDLE, MOVING, EATING, SLEEPING, SOCIALIZING, USING_OBJECT, WORKING }

var brain:       NpcBrain  = null
var para_color:  Color     = Color.WHITE
var is_selected: bool      = false
var move_speed:  float     = 100.0

var target_pos:          Vector2   = Vector2.ZERO
var is_moving:           bool      = false
var state:               ParaState = ParaState.IDLE
var state_timer:         float     = 0.0
var interaction_target:  Node      = null
var auto_tick_timer:     float     = 0.0
const AUTO_TICK_INTERVAL = 6.0

var _pending_name: String = ""

const OLLAMA_URL   = "http://localhost:11434/api/generate"
const OLLAMA_MODEL = "llama3.2"

func setup(p_name: String, p_age: int, personality: Dictionary, color: Color) -> void:
	_pending_name = p_name
	para_color    = color
	brain         = NpcBrain.new()
	brain.setup(p_name, p_age, personality)

func _ready() -> void:
	target_pos = position
	if _pending_name != "" and has_node("NameLabel"):
		$NameLabel.text = _pending_name

func _draw() -> void:
	# Shadow
	draw_circle(Vector2(3, 3), 21.0, Color(0, 0, 0, 0.25))
	# Body
	draw_circle(Vector2.ZERO, 20.0, para_color)
	# Outline
	var outline = Color.WHITE if is_selected else Color(para_color.r * 1.3, para_color.g * 1.3, para_color.b * 1.3, 0.6)
	draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 32, outline, 2.0)
	# Selection ring
	if is_selected:
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 48, Color.WHITE, 2.5)
	# State dot (top-right)
	draw_circle(Vector2(10, -10), 6.0, _state_dot_color())

func _state_dot_color() -> Color:
	match state:
		ParaState.EATING:     return Color(1.0, 0.6, 0.1)
		ParaState.SLEEPING:   return Color(0.4, 0.5, 1.0)
		ParaState.SOCIALIZING: return Color(1.0, 0.9, 0.2)
		ParaState.USING_OBJECT, ParaState.WORKING: return Color(0.3, 1.0, 0.5)
		ParaState.MOVING:     return Color(0.8, 0.8, 0.8)
		_:                    return Color(0.3, 0.3, 0.35)

func _physics_process(delta: float) -> void:
	queue_redraw()

	# Movement
	if is_moving:
		var dir = target_pos - position
		if dir.length() < 3.0:
			is_moving  = false
			velocity   = Vector2.ZERO
			position   = target_pos
			_on_arrived()
		else:
			velocity = dir.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	# State timer countdown
	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0:
			_finish_action()

	# Autonomous tick
	auto_tick_timer += delta
	if auto_tick_timer >= AUTO_TICK_INTERVAL:
		auto_tick_timer = 0.0
		_check_needs()

func move_to(pos: Vector2) -> void:
	target_pos = pos
	is_moving  = true
	state      = ParaState.MOVING
	if brain: brain.current_action = "walking"

func set_selected(sel: bool) -> void:
	is_selected = sel
	queue_redraw()

func tick_game_hour(delta_hours: float) -> void:
	if brain:
		brain.tick_needs(delta_hours)

func get_brain() -> NpcBrain:
	return brain

# ── Interaction ────────────────────────────────────────────────────────────────

func interact_with_furniture(furn: Node) -> void:
	if not furn or furn.get_meta("is_occupied", false):
		return
	interaction_target = furn
	furn.set_meta("is_occupied", true)
	move_to(furn.position + Vector2(35, 0))

func interact_with_para(other: Node) -> void:
	if other == self: return
	interaction_target = other
	move_to(other.position + Vector2(50, 0))

func _on_arrived() -> void:
	if interaction_target:
		_start_interaction()
	else:
		state = ParaState.IDLE
		if brain: brain.current_action = "idle"

func _start_interaction() -> void:
	if not interaction_target: return

	# Furniture
	if interaction_target.has_meta("need_satisfied"):
		var need = interaction_target.get_meta("need_satisfied", "fun")
		state       = _state_for_need(need)
		state_timer = 4.0
		if brain: brain.current_action = _action_label_for_need(need)
	# Another Para — social
	elif interaction_target.has_method("get_brain"):
		state       = ParaState.SOCIALIZING
		state_timer = 5.0
		if brain:
			brain.current_action = "chatting"
			var other_brain = interaction_target.get_brain()
			if other_brain:
				brain.seal_event("SOCIAL_INTERACTION", other_brain.id,
					"Chatted with " + other_brain.para_name, 0.08)
				other_brain.seal_event("SOCIAL_INTERACTION", brain.id,
					"Chatted with " + brain.para_name, 0.08)
				brain.fill_need("social", 0.25)
				other_brain.fill_need("social", 0.25)

func _finish_action() -> void:
	if interaction_target and interaction_target.has_meta("need_satisfied"):
		var need = interaction_target.get_meta("need_satisfied", "fun")
		var fill = float(interaction_target.get_meta("fill_rate", 0.35))
		if brain: brain.fill_need(need, fill)
		interaction_target.set_meta("is_occupied", false)
	interaction_target = null
	state = ParaState.IDLE
	if brain: brain.current_action = "idle"

func _check_needs() -> void:
	if state != ParaState.IDLE: return
	if not brain: return
	var critical = brain.most_critical_need()
	if brain.needs[critical] < 0.3:
		emit_signal("needs_critical", brain.para_name, critical)

func _state_for_need(need: String) -> ParaState:
	match need:
		"hunger": return ParaState.EATING
		"energy": return ParaState.SLEEPING
		_:        return ParaState.USING_OBJECT

func _action_label_for_need(need: String) -> String:
	match need:
		"hunger":  return "eating"
		"energy":  return "sleeping"
		"social":  return "socializing"
		"fun":     return "having fun"
		"hygiene": return "washing up"
		"comfort": return "relaxing"
		_:         return "using " + need

# ── NOVA Dialogue ──────────────────────────────────────────────────────────────

func say_to(speaker: Node, message: String) -> void:
	if not brain: return
	var speaker_brain = speaker.get_brain() if speaker.has_method("get_brain") else null
	var speaker_id   = speaker_brain.id   if speaker_brain else "PLAYER"
	var speaker_name = speaker_brain.para_name if speaker_brain else "Player"

	var prompt = brain.build_nova_prompt(speaker_id, speaker_name, message)
	var rel    = brain.relationship_with(speaker_id)
	var tone   = brain.classify_tone(rel)

	brain.seal_event("DIALOGUE", speaker_id, message.left(50), 0.05)
	if speaker_brain:
		speaker_brain.seal_event("DIALOGUE", brain.id, message.left(50), 0.05)

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, headers, body):
		_on_ollama_done(http, tone, body)
	)
	var req = JSON.stringify({
		"model":   OLLAMA_MODEL,
		"prompt":  prompt,
		"stream":  false,
		"options": {"temperature": 0.8, "num_predict": 70}
	})
	var err = http.request(OLLAMA_URL, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, req)
	if err != OK:
		http.queue_free()
		emit_signal("dialogue_ready", brain.para_name, _fallback_line(tone), tone)

func _on_ollama_done(http: HTTPRequest, tone: String, body: PackedByteArray) -> void:
	http.queue_free()
	var text     = body.get_string_from_utf8()
	var parsed   = JSON.parse_string(text)
	var response = _fallback_line(tone)
	if parsed and parsed.has("response"):
		var raw = (parsed["response"] as String).strip_edges()
		if raw.length() > 0:
			response = raw
	emit_signal("dialogue_ready", brain.para_name, response, tone)

func _fallback_line(tone: String) -> String:
	match tone:
		"Guarded":  return "I'm not sure I want to talk right now."
		"Warm":     return "It's so good to see you. Really."
		"Cold":     return "..."
		"Friendly": return "Hey, good to run into you."
		"Eager":    return "Oh! I was hoping someone would come by."
		"Tired":    return "I really need to rest. Can we talk later?"
		_:          return "Hmm. I'm not sure what to say."
