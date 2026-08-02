# WorldMain — KittyVerse sovereign life simulation director
# Draws the house, spawns furniture + Paras, runs the game loop.
# NEXUS dispatches. FORGE builds. LEDGER seals. Life happens.

extends Node2D

# ── Layout ─────────────────────────────────────────────────────────────────────
const HOUSE_CENTER = Vector2(960, 540)
const HOUSE_W      = 820.0
const HOUSE_H      = 620.0
const WALL_T       = 14.0

const COL_BG       = Color(0.06, 0.07, 0.10)
const COL_GARDEN   = Color(0.28, 0.46, 0.26)
const COL_FLOOR    = Color(0.82, 0.74, 0.60)
const COL_FLOOR_2  = Color(0.74, 0.68, 0.58)
const COL_WALL     = Color(0.28, 0.22, 0.18)
const COL_PATH     = Color(0.65, 0.60, 0.50)

# ── Para definitions [name, age, personality, spawn_offset, color] ─────────────
const PARA_DEFS = [
	["Sara",  29, {openness=0.78, conscientiousness=0.62, extraversion=0.78, agreeableness=0.88, neuroticism=0.32}, Vector2(-180,  30), Color(1.00, 0.42, 0.62)],
	["Alex",  34, {openness=0.55, conscientiousness=0.88, extraversion=0.40, agreeableness=0.52, neuroticism=0.26}, Vector2(-60,  -20), Color(0.42, 1.00, 0.72)],
	["Maya",  22, {openness=0.95, conscientiousness=0.48, extraversion=0.88, agreeableness=0.72, neuroticism=0.48}, Vector2( 80,   40), Color(1.00, 0.88, 0.24)],
	["James", 41, {openness=0.50, conscientiousness=0.90, extraversion=0.32, agreeableness=0.60, neuroticism=0.55}, Vector2(210,  -30), Color(0.42, 0.60, 1.00)],
]

# ── Furniture definitions [name, need, fill_rate, color, offset_from_center] ──
const FURN_DEFS = [
	["Fridge",   "hunger",  0.50, Color(0.75, 0.88, 0.98), Vector2(-310, -220)],
	["Stove",    "hunger",  0.40, Color(0.92, 0.60, 0.28), Vector2(-230, -220)],
	["Table",    "hunger",  0.25, Color(0.72, 0.55, 0.38), Vector2(-270, -155)],
	["Bed A",    "energy",  0.70, Color(0.55, 0.55, 0.90), Vector2( 210, -200)],
	["Bed B",    "energy",  0.70, Color(0.45, 0.65, 0.90), Vector2( 310, -200)],
	["Sofa",     "comfort", 0.45, Color(0.70, 0.48, 0.38), Vector2(  20,  175)],
	["TV",       "fun",     0.38, Color(0.18, 0.18, 0.20), Vector2(-120,  145)],
	["Computer", "fun",     0.35, Color(0.28, 0.80, 0.80), Vector2( 220,  165)],
	["Toilet",   "hygiene", 0.55, Color(0.92, 0.92, 0.94), Vector2( 305,   30)],
	["Shower",   "hygiene", 0.50, Color(0.65, 0.82, 1.00), Vector2( 305,  110)],
	["Bookshelf","fun",     0.30, Color(0.62, 0.42, 0.22), Vector2(-310,  100)],
	["Piano",    "fun",     0.42, Color(0.20, 0.18, 0.18), Vector2(-130, -215)],
]

var paras:         Array = []
var furniture:     Array = []
var selected_para: Node  = null
var hud:           Node  = null
var camera:        Camera2D = null

var game_hour:    float = 8.0
var day:          int   = 1
const GAME_SPEED  = 0.4   # game-hours per real second

var is_dialogue_open: bool = false

# ── Boot ───────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_camera()
	_build_hud()
	_spawn_furniture()
	_spawn_paras()
	_seed_history()
	_select_para(paras[0])

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.position = HOUSE_CENTER
	camera.zoom     = Vector2(0.92, 0.92)
	add_child(camera)

func _build_hud() -> void:
	hud = load("res://scripts/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

func _spawn_furniture() -> void:
	for d in FURN_DEFS:
		var f = StaticBody2D.new()
		f.name = d[0]
		f.position = HOUSE_CENTER + d[4]
		f.set_meta("label",        d[0])
		f.set_meta("need_satisfied", d[1])
		f.set_meta("fill_rate",    d[2])
		f.set_meta("fcolor",       d[3])
		f.set_meta("is_occupied",  false)
		var cs    = CollisionShape2D.new()
		var rect  = RectangleShape2D.new()
		rect.size = Vector2(52, 36)
		cs.shape  = rect
		f.add_child(cs)
		furniture.append(f)
		add_child(f)

func _spawn_paras() -> void:
	var para_scene = preload("res://scenes/Para.tscn")
	for d in PARA_DEFS:
		var p: Node = para_scene.instantiate()
		p.position  = HOUSE_CENTER + d[3]
		p.setup(d[0], d[1], d[2], d[4])
		p.connect("dialogue_ready", _on_dialogue_ready)
		p.connect("needs_critical",  _on_needs_critical)
		add_child(p)
		paras.append(p)

func _seed_history() -> void:
	if paras.size() < 2: return
	var sara  = paras[0]
	var alex  = paras[1]
	# Sara and Alex: deep friendship, then Alex broke her trust
	sara.brain.seal_event("FIRST_MEETING",  alex.brain.id, "Met at university orientation",      0.30)
	alex.brain.seal_event("FIRST_MEETING",  sara.brain.id, "She was the only person who waved",  0.35)
	sara.brain.seal_event("FRIENDSHIP",     alex.brain.id, "Became inseparable second year",      0.60)
	alex.brain.seal_event("FRIENDSHIP",     sara.brain.id, "Closest friend I ever had",           0.60)
	sara.brain.seal_event("SHARED_SECRET",  alex.brain.id, "Told him about her father leaving",   0.80)
	alex.brain.seal_event("KEPT_PROMISE",   sara.brain.id, "Showed up at 3am when she called",    0.85)
	sara.brain.seal_event("BETRAYAL",       alex.brain.id, "Told everyone what I told him. Hurt.",  -0.75)
	alex.brain.seal_event("GUILT",          sara.brain.id, "I betrayed her confidence. Regret.",   -0.40)

	if paras.size() >= 4:
		var maya  = paras[2]
		var james = paras[3]
		maya.brain.seal_event("FIRST_MEETING",  james.brain.id, "New neighbour — intriguing",    0.20)
		james.brain.seal_event("FIRST_MEETING", maya.brain.id,  "She knocked at 11pm for sugar", 0.15)
		james.brain.seal_event("ARGUMENT",      maya.brain.id,  "The 2am music was too much",    -0.50)
		maya.brain.seal_event("APOLOGY",        james.brain.id, "Left brownies at his door",      0.35)
		james.brain.seal_event("FORGIVENESS",   maya.brain.id,  "The brownies were very good",    0.40)
		maya.brain.seal_event("COLLABORATION",  james.brain.id, "Built something together",        0.45)

# ── Game Loop ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var hours = delta * GAME_SPEED
	game_hour += hours
	if game_hour >= 24.0:
		game_hour -= 24.0
		day += 1

	for p in paras:
		p.tick_game_hour(hours)

	if selected_para and hud:
		hud.update_needs(selected_para.brain)
		hud.update_time(game_hour, day)

	queue_redraw()

# ── Drawing ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_background()
	_draw_house()
	_draw_furniture()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), COL_BG)
	# Garden
	var hl = HOUSE_CENTER - Vector2(HOUSE_W / 2 + 80, HOUSE_H / 2 + 60)
	draw_rect(Rect2(hl, Vector2(HOUSE_W + 160, HOUSE_H + 120)), COL_GARDEN)
	# Path to door (bottom center)
	var path_x = HOUSE_CENTER.x - 30
	var path_y = HOUSE_CENTER.y + HOUSE_H / 2
	draw_rect(Rect2(Vector2(path_x, path_y), Vector2(60, 80)), COL_PATH)

func _draw_house() -> void:
	var tl = HOUSE_CENTER - Vector2(HOUSE_W / 2, HOUSE_H / 2)
	var wt = WALL_T

	# Bedroom floor (slightly different shade)
	var bed_x = tl.x + HOUSE_W * 0.56
	draw_rect(Rect2(Vector2(bed_x + wt, tl.y + wt), Vector2(HOUSE_W * 0.44 - wt * 2, HOUSE_H * 0.50 - wt)), COL_FLOOR_2)
	# Main floor
	draw_rect(Rect2(tl + Vector2(wt, wt), Vector2(HOUSE_W - wt * 2, HOUSE_H - wt * 2)), COL_FLOOR)

	# Outer walls
	draw_rect(Rect2(tl,                                  Vector2(HOUSE_W, wt)),        COL_WALL)  # top
	draw_rect(Rect2(tl + Vector2(0, HOUSE_H - wt),       Vector2(HOUSE_W, wt)),        COL_WALL)  # bottom
	draw_rect(Rect2(tl,                                  Vector2(wt, HOUSE_H)),        COL_WALL)  # left
	draw_rect(Rect2(tl + Vector2(HOUSE_W - wt, 0),       Vector2(wt, HOUSE_H)),        COL_WALL)  # right

	# Interior divider — horizontal (separates bedroom from main)
	var div_y = tl.y + HOUSE_H * 0.50
	var gap_x = tl.x + HOUSE_W * 0.55
	draw_rect(Rect2(Vector2(gap_x, div_y), Vector2(HOUSE_W * 0.45 - wt, wt)), COL_WALL)

	# Interior divider — vertical (separates bathroom from bedroom)
	var bath_x = tl.x + HOUSE_W * 0.72
	draw_rect(Rect2(Vector2(bath_x, div_y + wt), Vector2(wt, HOUSE_H * 0.50 - wt * 2)), COL_WALL)

	# Door gap hint (bottom wall center — opening)
	draw_rect(Rect2(Vector2(HOUSE_CENTER.x - 28, tl.y + HOUSE_H - wt), Vector2(56, wt)), COL_FLOOR)

	# Room labels
	var font = ThemeDB.fallback_font
	draw_string(font, tl + Vector2(22, 22 + 14), "KITCHEN / LIVING",    HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.42, 0.32))
	draw_string(font, tl + Vector2(HOUSE_W * 0.58, 22 + 14), "BEDROOM",  HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.42, 0.32))
	draw_string(font, tl + Vector2(HOUSE_W * 0.74, HOUSE_H * 0.54 + 14), "BATH", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.50, 0.42, 0.32))

func _draw_furniture() -> void:
	var font = ThemeDB.fallback_font
	for f in furniture:
		var pos     = f.position
		var col: Color = f.get_meta("fcolor", Color.GRAY)
		var label   = f.get_meta("label", "")
		var occupied: bool = f.get_meta("is_occupied", false)
		var draw_col = col.darkened(0.35) if occupied else col
		var rect_tl  = pos - Vector2(26, 18)
		draw_rect(Rect2(rect_tl, Vector2(52, 36)), draw_col)
		draw_rect(Rect2(rect_tl, Vector2(52, 36)), Color(1, 1, 1, 0.18), false, 1.0)
		draw_string(font, pos + Vector2(-26, 30), label, HORIZONTAL_ALIGNMENT_LEFT, 54, 10, Color(1, 1, 1, 0.80))

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(get_global_mouse_position())
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:    _cycle_para()
			KEY_E:      _try_talk()
			KEY_ESCAPE: _close_dialogue()

func _handle_click(world_pos: Vector2) -> void:
	# Click on a Para?
	for p in paras:
		if p.position.distance_to(world_pos) < 26.0:
			_select_para(p)
			return

	if not selected_para: return

	# Click on furniture?
	for f in furniture:
		if f.position.distance_to(world_pos) < 38.0:
			selected_para.interact_with_furniture(f)
			return

	# Click on floor — move
	var tl = HOUSE_CENTER - Vector2(HOUSE_W / 2 - WALL_T, HOUSE_H / 2 - WALL_T)
	var br = HOUSE_CENTER + Vector2(HOUSE_W / 2 - WALL_T, HOUSE_H / 2 - WALL_T)
	if world_pos.x > tl.x and world_pos.x < br.x and world_pos.y > tl.y and world_pos.y < br.y:
		selected_para.move_to(world_pos)

func _select_para(p: Node) -> void:
	if selected_para:
		selected_para.set_selected(false)
	selected_para = p
	p.set_selected(true)
	if hud: hud.show_para(p.brain)

func _cycle_para() -> void:
	if paras.is_empty(): return
	var idx = paras.find(selected_para)
	idx = (idx + 1) % paras.size()
	_select_para(paras[idx])

func _try_talk() -> void:
	if not selected_para or is_dialogue_open: return
	for p in paras:
		if p == selected_para: continue
		if selected_para.position.distance_to(p.position) < 90.0:
			is_dialogue_open = true
			p.say_to(selected_para, "Hey, how have you been?")
			return

func _close_dialogue() -> void:
	is_dialogue_open = false
	if hud: hud.hide_dialogue()

# ── Signal handlers ────────────────────────────────────────────────────────────

func _on_dialogue_ready(npc_name: String, response: String, tone: String) -> void:
	is_dialogue_open = false
	if hud: hud.show_dialogue(npc_name, response, tone)

func _on_needs_critical(npc_name: String, need: String) -> void:
	var furn = _find_free_furniture(need)
	if not furn: return
	for p in paras:
		if p.brain.para_name == npc_name and p.state == p.ParaState.IDLE:
			p.interact_with_furniture(furn)
			return

func _find_free_furniture(need: String) -> Node:
	for f in furniture:
		if f.get_meta("need_satisfied", "") == need and not f.get_meta("is_occupied", false):
			return f
	return null
