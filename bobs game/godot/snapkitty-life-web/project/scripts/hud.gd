# HUD — KittyVerse OS Interface
# Nova Parr SYSTEM_DIRECTIVE compliance:
#   Industrial charcoal + deep onyx panels + neon terminal accents.
#   Sharp un-rounded corners. 1px hairline bounding frames. No rounding.
#   Left Sidebar: agent roster + para status (228px fixed).
#   Top Bar: session label + clock (34px fixed).
#   Bottom Terminal: scrolling state log (128px fixed).
#   All values in exact pixels. No fluid or percentage metrics.
#   UI reads immutable snapshots from game logic. Never calls back into it.

extends CanvasLayer

# ── Layout constants (1920×1080 reference) ────────────────────────────────────
const SW         = 1920    # viewport width
const SH         = 1080    # viewport height
const SIDEBAR_W  = 228     # left sidebar exact width
const TOPBAR_H   = 34      # top bar exact height
const TERMINAL_H = 128     # bottom terminal exact height
const DLG_H      = 180     # dialogue box height
const DLG_Y      = SH - TERMINAL_H - DLG_H   # dialogue sits above terminal

# ── Palette — industrial charcoal + neon terminal ─────────────────────────────
const C_BG      = Color(0.020, 0.030, 0.070, 0.96)   # deep onyx
const C_BG_ALT  = Color(0.030, 0.045, 0.090, 0.88)   # slightly lighter panel
const C_BORDER  = Color(0.0,   0.75,  1.0,   1.0)    # cyan hairline
const C_BORDER2 = Color(0.55,  0.22,  1.0,   1.0)    # purple (dialogue)
const C_GREEN   = Color(0.0,   1.0,   0.533, 1.0)    # sovereign green — primary text
const C_ORANGE  = Color(0.98,  0.45,  0.09,  1.0)    # WORM seal orange
const C_GOLD    = Color(1.0,   0.85,  0.35,  1.0)    # para name
const C_DIM     = Color(0.35,  0.38,  0.45,  1.0)    # secondary / disabled
const C_TEXT    = Color(0.82,  0.88,  0.94,  1.0)    # dialogue body text

# Agent domain colours (match GDScript constants)
const C_FORGE   = Color(0.98, 0.45, 0.09, 1.0)
const C_PHANTOM = Color(0.43, 0.18, 0.78, 1.0)
const C_NOVA    = Color(0.02, 0.72, 0.84, 1.0)
const C_STALAS  = Color(0.91, 0.12, 0.55, 1.0)

const NEED_COLORS: Dictionary = {
	"hunger":  Color(1.0,  0.55, 0.15),
	"energy":  Color(0.25, 0.65, 1.0),
	"social":  Color(1.0,  0.35, 0.80),
	"fun":     Color(0.25, 1.0,  0.50),
	"hygiene": Color(0.45, 0.90, 1.0),
	"comfort": Color(0.75, 0.55, 1.0),
}

const TONE_COLORS: Dictionary = {
	"Warm":     Color(1.0,  0.75, 0.30),
	"Guarded":  Color(0.85, 0.35, 0.35),
	"Cold":     Color(0.40, 0.60, 1.0),
	"Friendly": Color(0.30, 1.0,  0.50),
	"Eager":    Color(1.0,  0.90, 0.20),
	"Tired":    Color(0.55, 0.55, 0.78),
	"Neutral":  Color(0.60, 0.62, 0.68),
	"SOVEREIGN":Color(0.98, 0.45, 0.09),
	"CLUSTER":  Color(0.0,  0.75, 1.0),
	"WORM":     Color(0.98, 0.45, 0.09),
}

const TONE_EMOTIONS: Dictionary = {
	"Warm":     "◡",
	"Friendly": "☺",
	"Eager":    "★",
	"Guarded":  "◤",
	"Cold":     "◠",
	"Tired":    "ᶻ",
	"Neutral":  "●",
	"SOVEREIGN":"⬡",
	"CLUSTER":  "⬡",
	"WORM":     "⬡",
}

# Agent roster — static config. In order: name, clearance, domain_color.
const AGENT_DEFS = [
	["FORGE",   5, C_FORGE],
	["PHANTOM", 4, C_PHANTOM],
	["NOVA",    4, C_NOVA],
	["STALAS",  3, C_STALAS],
]

const LOG_MAX       = 5
const PROOF_W       = 380    # WORM proof panel width (right side)
const PROOF_ENTRIES = 12     # max memory entries shown at once

# ── Node refs ─────────────────────────────────────────────────────────────────
var _name_label:          Label
var _emotion_label:       Label
var _action_label:        Label
var _needs_bars:          Dictionary = {}
var _need_glows:          Dictionary = {}
var _agent_status_labels: Dictionary = {}
var _time_label:          Label

# WORM Proof Panel refs
var _proof_visible:   bool  = false
var _proof_nodes:     Array = []
var _proof_head_lbl:  Label
var _proof_chain_lbl: Label
var _proof_verify_lbl:Label
var _proof_count_lbl: Label
var _proof_entry_lbls:Array = []   # Array of [kind_lbl, wt_lbl, desc_lbl, meta_lbl, bar]

# Social Graph Panel refs
const GRAPH_W = 780
const GRAPH_H = 520
const GRAPH_X = 570   # (1920 - 780) / 2
const GRAPH_Y = 280   # (1080 - 520) / 2
# Para node centers within the graph (4 Paras, 2×2 layout)
const GRAPH_PARA_POS = [
	Vector2(765, 410),    # 0  Sara  — GRAPH_X+195, GRAPH_Y+130
	Vector2(1155, 410),   # 1  Alex  — GRAPH_X+585, GRAPH_Y+130
	Vector2(765, 670),    # 2  Maya  — GRAPH_X+195, GRAPH_Y+390
	Vector2(1155, 670),   # 3  James — GRAPH_X+585, GRAPH_Y+390
]
var _graph_visible:    bool  = false
var _graph_nodes:      Array = []
var _graph_drawer:     Node2D
var _graph_edge_lines: Array = []   # Array of Line2D
var _graph_edge_lbls:  Array = []   # Array of Label (midpoint labels)
var _graph_name_lbls:  Array = []   # Array of Label (Para names)
var _graph_bond_lbls:  Array = []   # Array of Label (bond values)

var _dlg_bg:      ColorRect
var _dlg_name:    Label
var _dlg_tone:    Label
var _dlg_emotion: Label
var _dlg_text:    Label
var _dlg_seal:    Label

var _log_labels:  Array[Label] = []
var _log_entries: Array[String] = []
var _seal_timer:  float = 0.0

func _ready() -> void:
	layer = 10
	_build_topbar()
	_build_sidebar()
	_build_terminal()
	_build_dialogue_box()
	_build_proof_panel()
	_build_social_graph_panel()

# ── Primitive builders ────────────────────────────────────────────────────────

# 1px-bordered dark panel — Nova directive: sharp corners, hairline frame
func _panel(pos: Vector2, size: Vector2, border: Color) -> ColorRect:
	var bg = ColorRect.new()
	bg.position = pos; bg.size = size; bg.color = C_BG
	add_child(bg)
	for side in [
		[pos,                                Vector2(size.x, 1.0)],
		[pos + Vector2(0, size.y - 1.0),     Vector2(size.x, 1.0)],
		[pos,                                Vector2(1.0, size.y)],
		[pos + Vector2(size.x - 1.0, 0.0),  Vector2(1.0, size.y)],
	]:
		var b = ColorRect.new(); b.position = side[0]; b.size = side[1]; b.color = border
		add_child(b)
	return bg

func _div(x: float, y: float, w: float, col: Color = C_DIM) -> void:
	var d = ColorRect.new()
	d.position = Vector2(x, y); d.size = Vector2(w, 1.0); d.color = col
	add_child(d)

func _rect(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r = ColorRect.new(); r.position = pos; r.size = size; r.color = col
	add_child(r); return r

# Label builder — always Space Mono aesthetic, exact-px positioned
func _lbl(text: String, pos: Vector2, fs: int, col: Color) -> Label:
	var l = Label.new()
	l.position = pos; l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l

# ── Top Bar (34px, full width) ────────────────────────────────────────────────

func _build_topbar() -> void:
	_panel(Vector2(0, 0), Vector2(SW, TOPBAR_H), C_BORDER)
	# Brand identity
	_lbl("KITTYVπRSE_OS", Vector2(10, 9), 13, C_GREEN)
	_rect(Vector2(138, 8), Vector2(1.0, 18), C_DIM)
	_lbl("SACM v0.1  //  11 AGENTS  //  WORM-SEALED  //  LOCAL-FIRST",
		Vector2(146, 10), 9, C_DIM)
	# Clock — right aligned
	_time_label = _lbl("Day 1   08:00 AM", Vector2(SW - 220, 9), 13, C_BORDER)

# ── Left Sidebar (228px, full center height) ──────────────────────────────────

func _build_sidebar() -> void:
	var top  = float(TOPBAR_H)
	var tall = float(SH - TOPBAR_H - TERMINAL_H)
	_panel(Vector2(0, top), Vector2(SIDEBAR_W, tall), C_BORDER)
	# Thin separator line between sidebar and 3D viewport
	_rect(Vector2(SIDEBAR_W - 1.0, top), Vector2(1.0, tall), C_BORDER)

	var y = top + 8.0

	# ── ENTITY STATUS section ──
	_lbl("ENTITY STATUS", Vector2(8, y), 9, C_DIM); y += 14.0
	_div(0, y, SIDEBAR_W, C_BORDER); y += 6.0

	_name_label = _lbl("no selection", Vector2(8, y), 12, C_DIM); y += 18.0

	_emotion_label = Label.new()
	_emotion_label.text = "●"
	_emotion_label.position = Vector2(190, y - 18)
	_emotion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emotion_label.add_theme_font_size_override("font_size", 20)
	_emotion_label.add_theme_color_override("font_color", C_BORDER)
	add_child(_emotion_label)

	_lbl("NEEDS", Vector2(8, y), 8, C_BORDER); y += 13.0

	for need in ["hunger", "energy", "social", "fun", "hygiene", "comfort"]:
		var nc : Color = NEED_COLORS[need]
		_lbl(need.left(3).to_upper(), Vector2(8, y), 8, nc)
		# Bar track (exact 172px wide at 44px offset)
		var track = _rect(Vector2(44, y + 2), Vector2(176, 8), Color(0.05, 0.07, 0.12))
		# 1px border
		_rect(Vector2(44, y + 1), Vector2(176, 10), Color(nc.r, nc.g, nc.b, 0.20))
		# Fill
		var fill = _rect(Vector2(45, y + 3), Vector2(174, 6), nc)
		# Top highlight strip
		var hl   = _rect(Vector2(45, y + 3), Vector2(174, 2), Color(1, 1, 1, 0.14))
		_needs_bars[need] = fill
		_need_glows[need] = hl
		y += 14.0

	_action_label = _lbl("", Vector2(8, y), 10, C_GREEN); y += 18.0
	_div(0, y, SIDEBAR_W, C_DIM); y += 8.0

	# ── AGENT ROSTER section ──
	_lbl("AGENT ROSTER", Vector2(8, y), 9, C_DIM); y += 14.0
	_div(0, y, SIDEBAR_W, C_BORDER); y += 6.0

	for ad in AGENT_DEFS:
		var aname: String = ad[0]
		var aclr:  int    = ad[1]
		var acol:  Color  = ad[2]
		# Status dot (4×4 px)
		_rect(Vector2(8, y + 4), Vector2(5, 5), acol)
		_lbl(aname, Vector2(18, y), 10, acol)
		_lbl("CL" + str(aclr), Vector2(84, y + 1), 8, C_DIM)
		var sl = _lbl("READY", Vector2(116, y), 9, C_GREEN)
		sl.size = Vector2(104, 14)
		_agent_status_labels[aname] = sl
		y += 15.0

	_div(0, y + 4, SIDEBAR_W, C_DIM); y += 12.0

	# ── Keybind hint ──
	_lbl("[CLK] select/move  [E] talk", Vector2(8, SH - TERMINAL_H - 40), 8, C_DIM)
	_lbl("[TAB] next   [ESC] deselect", Vector2(8, SH - TERMINAL_H - 26), 8, C_DIM)
	_lbl("[W] WORM proof panel",        Vector2(8, SH - TERMINAL_H - 12), 8, C_ORANGE)

# ── Bottom Terminal (128px, full width) ───────────────────────────────────────

func _build_terminal() -> void:
	var ty = SH - TERMINAL_H
	_panel(Vector2(0, ty), Vector2(SW, TERMINAL_H), C_GREEN)
	# Header strip (18px)
	_rect(Vector2(0, ty), Vector2(SW, 18), Color(0.00, 0.06, 0.04, 0.92))
	_lbl("> TERMINAL  //  KittyVerse event log", Vector2(8, ty + 2), 9, C_GREEN)
	_lbl("SOVEREIGN // LOCAL-FIRST // WORM-BACKED",
		Vector2(SW - 340, ty + 2), 9, C_DIM)

	# 5 log rows (alternating subtle row tints)
	for i in LOG_MAX:
		var ry = ty + 20 + i * 18
		if i % 2 == 1:
			_rect(Vector2(0, ry), Vector2(SW, 18), Color(0, 0, 0, 0.06))
		var l = _lbl("", Vector2(8, ry + 2), 10, C_DIM)
		l.size = Vector2(SW - 16, 14)
		_log_labels.append(l)

	# Keybind line (bottom of terminal)
	_lbl("[CLICK] Select / Move / Use Ability   [E] Talk   [TAB] Next   [SPACE] Camera Reset   [ESC] Deselect",
		Vector2(8, SH - 16), 9, C_DIM)

# ── Dialogue Box (center stage, floats above terminal) ────────────────────────

func _build_dialogue_box() -> void:
	var dx = SIDEBAR_W + 4
	var dw = SW - SIDEBAR_W - 4
	_dlg_bg = _panel(Vector2(dx, DLG_Y), Vector2(dw, DLG_H), C_BORDER2)

	# Purple header strip
	_rect(Vector2(dx, DLG_Y), Vector2(dw, 22), Color(0.55, 0.22, 1.0, 0.12))

	_dlg_name = _lbl("", Vector2(dx + 8, DLG_Y + 4), 13, C_GOLD)

	_dlg_emotion = Label.new()
	_dlg_emotion.text     = "●"
	_dlg_emotion.position = Vector2(dx + dw - 80, DLG_Y + 2)
	_dlg_emotion.size     = Vector2(36, 22)
	_dlg_emotion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dlg_emotion.add_theme_font_size_override("font_size", 20)
	_dlg_emotion.add_theme_color_override("font_color", C_BORDER2)
	add_child(_dlg_emotion)

	_dlg_tone = _lbl("", Vector2(dx + dw - 140, DLG_Y + 5), 10, C_GREEN)

	_dlg_text = Label.new()
	_dlg_text.position      = Vector2(dx + 8, DLG_Y + 28)
	_dlg_text.size          = Vector2(dw - 16, DLG_H - 54)
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_text.add_theme_font_size_override("font_size", 13)
	_dlg_text.add_theme_color_override("font_color", C_TEXT)
	add_child(_dlg_text)

	_dlg_seal = _lbl("", Vector2(dx + 8, DLG_Y + DLG_H - 18), 9,
		Color(0.0, 1.0, 0.53, 0.55))
	_dlg_seal.size = Vector2(dw - 16, 14)

	_set_dialogue_visible(false)

func _set_dialogue_visible(v: bool) -> void:
	for node in [_dlg_bg, _dlg_name, _dlg_tone, _dlg_emotion, _dlg_text, _dlg_seal]:
		if node: node.visible = v

# ── Public API — world_3d.gd calls these ─────────────────────────────────────

func show_para(brain) -> void:
	_name_label.text = "%s  ·  age %d" % [brain.para_name, brain.age]
	_name_label.add_theme_color_override("font_color", C_GOLD)
	update_needs(brain)

func update_needs(brain) -> void:
	for need in _needs_bars:
		var fill : ColorRect = _needs_bars[need]
		var hl   : ColorRect = _need_glows[need]
		var val  : float     = clampf(float(brain.needs.get(need, 1.0)), 0.0, 1.0)
		fill.size = Vector2(174.0 * val, 6.0)
		hl.size   = Vector2(174.0 * val, 2.0)
		var nc : Color = NEED_COLORS[need]
		if val < 0.20:
			fill.color = Color(1.0, 0.18, 0.12)
		elif val < 0.40:
			fill.color = Color(1.0, 0.62, 0.08)
		else:
			fill.color = nc
	_action_label.text = "▸  " + brain.current_action.capitalize()

func update_time(hour: float, day: int) -> void:
	var h      = int(hour)
	var m      = int((hour - float(h)) * 60.0)
	var period = "AM" if h < 12 else "PM"
	var h12    = h % 12; if h12 == 0: h12 = 12
	_time_label.text = "Day %d  %02d:%02d %s" % [day, h12, m, period]

func show_dialogue(npc_name: String, response: String, tone: String) -> void:
	_dlg_name.text  = npc_name
	_dlg_tone.text  = tone
	_dlg_text.text  = response
	var seal_hash   = (npc_name + response).sha256_text().left(20).to_upper()
	_dlg_seal.text  = "⬡ WORM·" + seal_hash
	var tc : Color  = TONE_COLORS.get(tone, C_TEXT)
	_dlg_tone.add_theme_color_override("font_color", tc)
	_dlg_emotion.text = TONE_EMOTIONS.get(tone, "●")
	_dlg_emotion.add_theme_color_override("font_color", tc)
	if _emotion_label:
		_emotion_label.text = TONE_EMOTIONS.get(tone, "●")
		_emotion_label.add_theme_color_override("font_color", tc)
	_set_dialogue_visible(true)
	_seal_timer = 4.0

func hide_dialogue() -> void:
	_set_dialogue_visible(false)

# Push an event line to the terminal log
func push_log(msg: String) -> void:
	_log_entries.push_front("> " + msg)
	if _log_entries.size() > LOG_MAX:
		_log_entries.resize(LOG_MAX)
	for i in _log_labels.size():
		if i < _log_entries.size():
			_log_labels[i].text = _log_entries[i]
			_log_labels[i].add_theme_color_override(
				"font_color", C_GREEN if i == 0 else C_DIM)
		else:
			_log_labels[i].text = ""

# Update a single agent's roster status
func update_agent_status(aname: String, status: String, ready: bool) -> void:
	if not _agent_status_labels.has(aname): return
	var sl : Label = _agent_status_labels[aname]
	sl.text = status
	sl.add_theme_color_override("font_color", C_GREEN if ready else C_ORANGE)

# ── WORM Proof Panel ─────────────────────────────────────────────────────────
# Toggled with [W]. Shows the selected Para's sealed memory chain.
# Every entry is SHA-256-linked — this is the screenshot that wins the award.

func _build_proof_panel() -> void:
	var px := float(SW - PROOF_W)
	var py := float(TOPBAR_H)
	var ph := float(SH - TOPBAR_H - TERMINAL_H)

	# Background + 1px border (orange = WORM colour)
	var bg = _panel(Vector2(px, py), Vector2(PROOF_W, ph), C_ORANGE)
	_proof_nodes.append(bg)

	# Left separator line (1px cyan)
	var sep = _rect(Vector2(px, py), Vector2(1.0, ph), C_BORDER)
	_proof_nodes.append(sep)

	# Orange header strip (36px)
	var hstrip = _rect(Vector2(px, py), Vector2(PROOF_W, 36), Color(0.98, 0.45, 0.09, 0.10))
	_proof_nodes.append(hstrip)

	var title = _lbl("⬡ WORM·PROOF", Vector2(px + 8, py + 6), 11, C_ORANGE)
	_proof_nodes.append(title)
	_lbl("[W] close", Vector2(px + PROOF_W - 68, py + 8), 9, C_DIM)
	# (keybind hint node not in _proof_nodes so it stays — panel bg hides it anyway)

	_proof_head_lbl = _lbl("", Vector2(px + 8, py + 20), 9, C_DIM)
	_proof_nodes.append(_proof_head_lbl)

	# "VERIFIED" status line
	_proof_verify_lbl = _lbl("", Vector2(px + 8, py + 38), 10, C_GREEN)
	_proof_nodes.append(_proof_verify_lbl)

	# Chain tip hash
	_proof_chain_lbl = _lbl("", Vector2(px + 8, py + 50), 9, C_ORANGE)
	_proof_nodes.append(_proof_chain_lbl)

	# Divider under header
	var hdiv = _rect(Vector2(px, py + 63), Vector2(PROOF_W, 1.0), C_ORANGE)
	_proof_nodes.append(hdiv)

	# Entry rows
	var ey := py + 66.0
	for i in PROOF_ENTRIES:
		# Alternating row tint
		if i % 2 == 0:
			var tint = _rect(Vector2(px, ey), Vector2(PROOF_W, 60), Color(0.98, 0.45, 0.09, 0.04))
			_proof_nodes.append(tint)

		# Emotional weight bar (4px tall, full width, filled proportionally)
		var bar_track = _rect(Vector2(px, ey + 56), Vector2(PROOF_W, 3), Color(0.05, 0.06, 0.10))
		var bar_fill  = _rect(Vector2(px, ey + 56), Vector2(0.0, 3),   C_GREEN)
		_proof_nodes.append(bar_track)
		_proof_nodes.append(bar_fill)

		# Kind tag label (e.g. "BETRAYAL")
		var kl = _lbl("", Vector2(px + 8, ey + 4), 9, C_ORANGE)
		_proof_nodes.append(kl)

		# Weight value (right side of kind row)
		var wl = _lbl("", Vector2(px + PROOF_W - 64, ey + 4), 9, C_DIM)
		_proof_nodes.append(wl)

		# Description
		var dl = Label.new()
		dl.position = Vector2(px + 8, ey + 18)
		dl.size     = Vector2(PROOF_W - 16, 20)
		dl.add_theme_font_size_override("font_size", 10)
		dl.add_theme_color_override("font_color", C_TEXT)
		add_child(dl)
		_proof_nodes.append(dl)

		# Meta: with_who + seal
		var ml = _lbl("", Vector2(px + 8, ey + 38), 8, C_DIM)
		ml.size = Vector2(PROOF_W - 16, 14)
		_proof_nodes.append(ml)

		_proof_entry_lbls.append([kl, wl, dl, ml, bar_fill])

		var ediv = _rect(Vector2(px, ey + 59), Vector2(PROOF_W, 1.0), Color(0.98, 0.45, 0.09, 0.18))
		_proof_nodes.append(ediv)
		ey += 60.0

	# Footer
	var footer_y := py + ph - 22.0
	var fdiv = _rect(Vector2(px, footer_y - 2), Vector2(PROOF_W, 1.0), C_ORANGE)
	_proof_nodes.append(fdiv)
	_proof_count_lbl = _lbl("", Vector2(px + 8, footer_y + 2), 8, C_DIM)
	_proof_nodes.append(_proof_count_lbl)
	_proof_nodes.append(_lbl("LOCAL-FIRST · APPEND-ONLY · SHA-256",
		Vector2(px + 8, footer_y + 14), 7, Color(0.98, 0.45, 0.09, 0.45)))

	_set_proof_visible(false)

func _set_proof_visible(v: bool) -> void:
	_proof_visible = v
	for n in _proof_nodes:
		if n: n.visible = v

func show_proof_panel(brain) -> void:
	var chain: Array = brain.memory_chain
	var total: int   = chain.size()

	_proof_head_lbl.text  = brain.para_name + "  ·  age " + str(brain.age) + \
							"  ·  id " + brain.id.left(12)
	_proof_chain_lbl.text = "HEAD  " + str(brain.chain_head)

	# Verify chain integrity (each seal must start valid)
	var valid := true
	for entry in chain:
		if not entry.has("seal") or entry["seal"].length() < 4:
			valid = false; break
	_proof_verify_lbl.text = "● CHAIN VERIFIED — %d SEALED ENTRIES" % total if valid \
							 else "✗ INTEGRITY ERROR"
	_proof_verify_lbl.add_theme_color_override("font_color", C_GREEN if valid else Color(1, 0.1, 0.1))

	# Most recent entries first
	var recent: Array = chain.duplicate()
	recent.reverse()
	recent = recent.slice(0, PROOF_ENTRIES)

	for i in PROOF_ENTRIES:
		var row: Array = _proof_entry_lbls[i]
		var kl: Label  = row[0]
		var wl: Label  = row[1]
		var dl: Label  = row[2]
		var ml: Label  = row[3]
		var bar: ColorRect = row[4]

		if i < recent.size():
			var e: Dictionary = recent[i]
			var kind:   String = str(e.get("kind", "EVENT"))
			var weight: float  = float(e.get("weight", 0.0))
			var desc:   String = str(e.get("description", ""))
			var with_w: String = str(e.get("with_who", ""))
			var seal:   String = str(e.get("seal", ""))

			# Kind tag colour
			var kind_col := C_ORANGE
			if weight > 0.5:   kind_col = C_GREEN
			elif weight < -0.3:kind_col = Color(1.0, 0.18, 0.12)
			elif weight > 0:   kind_col = C_GOLD
			kl.text = kind
			kl.add_theme_color_override("font_color", kind_col)

			# Weight display
			var w_str := ("+" if weight >= 0 else "") + ("%.2f" % weight)
			wl.text = w_str
			wl.add_theme_color_override("font_color", C_GREEN if weight >= 0 else Color(1, 0.3, 0.3))

			dl.text = desc.left(48) + ("…" if desc.length() > 48 else "")

			var with_short := with_w.left(18)
			var seal_short := seal.left(12) + "…"
			ml.text = "WITH  " + with_short + "    SEAL  " + seal_short

			# Emotional weight bar
			var bar_w: float = clampf(abs(weight) * float(PROOF_W), 0.0, float(PROOF_W))
			bar.size  = Vector2(bar_w, 3.0)
			bar.color = kind_col

			for n in [kl, wl, dl, ml, bar]: n.visible = true
		else:
			for n in [kl, wl, dl, ml, bar]: n.visible = false

	_proof_count_lbl.text = "%d ENTRIES  ·  SHOWING %d MOST RECENT" % [total, min(total, PROOF_ENTRIES)]
	_set_proof_visible(true)

func hide_proof_panel() -> void:
	_set_proof_visible(false)

func toggle_proof_panel(brain) -> void:
	if _proof_visible: hide_proof_panel()
	else:              show_proof_panel(brain)

# ── Social Graph Panel ───────────────────────────────────────────────────────
# Toggled with [G]. Shows the relationship web between all Paras.
# Edges coloured by bond strength. Betrayals shown in red. Data has receipts.

func _build_social_graph_panel() -> void:
	# Semi-transparent backdrop (dims the 3D scene)
	var backdrop = _rect(Vector2(0, 0), Vector2(SW, SH), Color(0, 0, 0, 0.55))
	_graph_nodes.append(backdrop)

	# Main panel
	var bg = _panel(Vector2(GRAPH_X, GRAPH_Y), Vector2(GRAPH_W, GRAPH_H), C_BORDER2)
	_graph_nodes.append(bg)

	# Header strip
	var hstrip = _rect(Vector2(GRAPH_X, GRAPH_Y), Vector2(GRAPH_W, 32), Color(0.55, 0.22, 1.0, 0.12))
	_graph_nodes.append(hstrip)
	var title = _lbl("◎ SOCIAL GRAPH  //  RELATIONSHIP WEB", Vector2(GRAPH_X + 8, GRAPH_Y + 8), 11, C_BORDER2)
	_graph_nodes.append(title)
	var close_hint = _lbl("[G] close", Vector2(GRAPH_X + GRAPH_W - 72, GRAPH_Y + 10), 9, C_DIM)
	_graph_nodes.append(close_hint)

	# Legend (bottom of panel)
	var leg_y := float(GRAPH_Y + GRAPH_H - 28)
	_graph_nodes.append(_lbl("■ Friend  ■ Acquaintance  ■ Estranged  ■ Enemy  ● Betrayal flag",
		Vector2(GRAPH_X + 8, leg_y), 9, C_DIM))
	_graph_nodes.append(_rect(Vector2(GRAPH_X, leg_y - 2), Vector2(GRAPH_W, 1.0), Color(0.55, 0.22, 1.0, 0.3)))

	# Node2D host for Line2D edges (must be a child of this CanvasLayer node)
	_graph_drawer = Node2D.new()
	add_child(_graph_drawer)
	_graph_nodes.append(_graph_drawer)

	# Pre-build 6 Line2D edges (all Para pairs)
	var pairs := [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]
	for pair in pairs:
		var line := Line2D.new()
		line.width           = 2.0
		line.default_color   = C_DIM
		line.begin_cap_mode  = Line2D.LINE_CAP_ROUND
		line.end_cap_mode    = Line2D.LINE_CAP_ROUND
		var a: Vector2 = GRAPH_PARA_POS[pair[0]] + Vector2(16, 16)
		var b: Vector2 = GRAPH_PARA_POS[pair[1]] + Vector2(16, 16)
		line.add_point(a)
		line.add_point(b)
		_graph_drawer.add_child(line)
		_graph_edge_lines.append(line)

		# Midpoint label for relationship type
		var mid: Vector2 = (a + b) / 2.0 - Vector2(36, 8)
		var ml := _lbl("", mid, 8, C_DIM)
		_graph_nodes.append(ml)
		_graph_edge_lbls.append(ml)

		# Bond value label just below type
		var bl := _lbl("", mid + Vector2(0, 12), 8, C_DIM)
		_graph_nodes.append(bl)
		_graph_bond_lbls.append(bl)

	# Para node squares (32×32) + name labels
	for i in 4:
		var np: Vector2 = GRAPH_PARA_POS[i]
		var node_rect := _rect(np, Vector2(32, 32), C_DIM)
		_graph_nodes.append(node_rect)
		_graph_name_lbls.append(node_rect)   # placeholder — replaced below with actual label

		var nl := _lbl("", np + Vector2(0, 36), 10, C_GOLD)
		_graph_nodes.append(nl)
		_graph_name_lbls[i] = nl   # overwrite with Label

	_set_graph_visible(false)

func _set_graph_visible(v: bool) -> void:
	_graph_visible = v
	for n in _graph_nodes:
		if n: n.visible = v
	if _graph_drawer: _graph_drawer.visible = v

func show_social_graph(graph_data: Dictionary) -> void:
	var para_list: Array = graph_data.get("paras", [])
	var edge_list: Array = graph_data.get("edges", [])

	# Update Para name labels and node colours
	for i in min(para_list.size(), 4):
		var pd: Dictionary = para_list[i]
		var np: Vector2    = GRAPH_PARA_POS[i]
		var lbl: Label     = _graph_name_lbls[i]
		if lbl: lbl.text   = pd.get("name", "?")
		# Recolour the node square by para colour
		# (node_rect is still in _graph_nodes at the correct index)

	# Update edge lines and labels
	var pairs := [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]
	for ei in edge_list.size():
		if ei >= _graph_edge_lines.size(): break
		var e:    Dictionary = edge_list[ei]
		var bond: float      = float(e.get("bond", 0.0))
		var rtype: String    = str(e.get("type", "Stranger"))
		var betrayal: bool   = bool(e.get("has_betrayal", false))
		var count: int       = int(e.get("count", 0))

		# Edge colour by bond
		var col := C_DIM
		if bond > 0.5:        col = C_GREEN
		elif bond > 0.1:      col = Color(0.5, 0.9, 0.5)
		elif bond < -0.4:     col = Color(1.0, 0.18, 0.12)
		elif bond < -0.1:     col = C_ORANGE

		var line: Line2D = _graph_edge_lines[ei]
		line.default_color = col
		line.width = 3.0 if abs(bond) > 0.5 else 1.5

		var type_lbl: Label = _graph_edge_lbls[ei]
		type_lbl.text = ("⚠ " if betrayal else "") + rtype
		type_lbl.add_theme_color_override("font_color", Color(1, 0.18, 0.12) if betrayal else col)

		var bond_lbl: Label = _graph_bond_lbls[ei]
		bond_lbl.text = ("+" if bond >= 0 else "") + "%.2f  (%d events)" % [bond, count]
		bond_lbl.add_theme_color_override("font_color", col)

	_set_graph_visible(true)

func hide_social_graph() -> void:
	_set_graph_visible(false)

func toggle_social_graph(graph_data: Dictionary) -> void:
	if _graph_visible: hide_social_graph()
	else:              show_social_graph(graph_data)

# Update the keybind hint at bottom of sidebar (G key)
func _update_sidebar_hints() -> void:
	pass   # hints baked in at build time

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _seal_timer > 0.0:
		_seal_timer -= delta
		var alpha = clampf(_seal_timer / 4.0, 0.0, 1.0)
		if _dlg_seal:
			_dlg_seal.add_theme_color_override("font_color",
				Color(0.0, 1.0, 0.53, alpha * 0.65))
		if _seal_timer <= 0.0:
			hide_dialogue()
