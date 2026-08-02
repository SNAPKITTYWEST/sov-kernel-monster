# NpcBrain — Pure GDScript sovereign NPC simulation
# No Rust dependency for Phase 1. Simulates the WORM memory chain, needs engine,
# relationship derivation, and NOVA dialogue prompt building.
# When the GDExtension is compiled, swap this out for SnapKittyNPC.

class_name NpcBrain
extends RefCounted

var id:          String = ""
var para_name:   String = ""
var age:         int    = 25
var personality: Dictionary = {}

# Needs vector: 0.0 = critical, 1.0 = full
var needs: Dictionary = {
	"hunger":  1.0,
	"energy":  1.0,
	"social":  1.0,
	"fun":     1.0,
	"hygiene": 0.9,
	"comfort": 1.0,
}

const NEED_DECAY: Dictionary = {
	"hunger":  0.10,
	"energy":  0.06,
	"social":  0.07,
	"fun":     0.08,
	"hygiene": 0.03,
	"comfort": 0.04,
}

# WORM-simulated memory chain
var memory_chain: Array = []
var chain_head:   String = ""

# Current action label (shown in HUD)
var current_action: String = "idle"

func setup(p_name: String, p_age: int, pers: Dictionary) -> String:
	para_name   = p_name
	age         = p_age
	personality = pers
	chain_head  = (p_name + str(p_age)).sha256_text().left(16).to_upper()
	id = "PARA-%s-%04d" % [p_name.to_upper(), randi() % 9999]
	return id

func tick_needs(delta_hours: float) -> void:
	for need in NEED_DECAY:
		needs[need] = clampf(needs[need] - NEED_DECAY[need] * delta_hours, 0.0, 1.0)

func fill_need(need: String, amount: float) -> void:
	if needs.has(need):
		needs[need] = minf(1.0, needs[need] + amount)

func most_critical_need() -> String:
	var worst     = "hunger"
	var worst_val = 2.0
	for need in needs:
		if needs[need] < worst_val:
			worst_val = needs[need]
			worst     = need
	return worst

func wellbeing() -> float:
	var total = 0.0
	for v in needs.values():
		total += v
	return total / float(needs.size())

func seal_event(kind: String, with_who: String, desc: String, weight: float) -> String:
	var ts      = int(Time.get_unix_time_from_system())
	var content = "%s:%s:%s:%.3f:%d" % [kind, with_who, desc, weight, ts]
	var seal    = (chain_head + content).sha256_text().left(16).to_upper()
	memory_chain.append({
		"kind":        kind,
		"with_who":    with_who,
		"description": desc,
		"weight":      weight,
		"seal":        seal,
		"ts":          ts,
	})
	chain_head = seal
	return seal

func relationship_with(other_id: String) -> Dictionary:
	var bond         = 0.0
	var has_betrayal = false
	var count        = 0
	for ev in memory_chain:
		if ev.with_who == other_id:
			bond  += float(ev.weight)
			count += 1
			if ev.kind in ["BETRAYAL", "CONFLICT", "ARGUMENT"]:
				has_betrayal = true
	bond = clampf(bond, -1.0, 1.0)
	var rel_type: String
	if count == 0:
		rel_type = "Stranger"
	elif has_betrayal and bond < 0.3:
		rel_type = "Estranged"
	elif bond >= 0.7:
		rel_type = "Close Friend"
	elif bond >= 0.3:
		rel_type = "Friend"
	elif bond <= -0.3:
		rel_type = "Enemy"
	else:
		rel_type = "Acquaintance"
	return {"bond": bond, "type": rel_type, "has_betrayal": has_betrayal, "count": count}

func classify_tone(rel: Dictionary) -> String:
	if rel.get("has_betrayal", false) and rel.get("bond", 0.0) < 0.2:
		return "Guarded"
	var bond = rel.get("bond", 0.0)
	if bond >= 0.7:  return "Warm"
	if bond >= 0.3:  return "Friendly"
	if bond <= -0.3: return "Cold"
	if needs.social < 0.25: return "Eager"
	if needs.energy < 0.25: return "Tired"
	return "Neutral"

func build_nova_prompt(speaker_id: String, speaker_name: String, message: String) -> String:
	var rel  = relationship_with(speaker_id)
	var tone = classify_tone(rel)
	var sys  = "You are %s, age %d.\n" % [para_name, age]
	sys += "Big Five personality: openness=%.1f, conscientiousness=%.1f, extraversion=%.1f, agreeableness=%.1f, neuroticism=%.1f.\n" % [
		personality.get("openness",          0.6),
		personality.get("conscientiousness", 0.6),
		personality.get("extraversion",      0.5),
		personality.get("agreeableness",     0.6),
		personality.get("neuroticism",       0.3),
	]
	sys += "Your relationship with %s: %s (bond score: %.2f).\n" % [speaker_name, rel.get("type", "Stranger"), rel.get("bond", 0.0)]
	if rel.get("has_betrayal", false):
		sys += "IMPORTANT: This person has betrayed your trust before. Be measured. Do not open up easily.\n"
	if rel.get("bond", 0.0) >= 0.7:
		sys += "You trust this person deeply. Be warm, genuine, and open.\n"
	if needs.hunger < 0.2:
		sys += "You are quite hungry. "
	if needs.energy < 0.2:
		sys += "You are exhausted. "
	if needs.social < 0.2:
		sys += "You have been lonely and genuinely crave this connection. "
	sys += "\nDialogue tone: %s. Respond in 1-2 sentences only. Stay fully in character." % tone
	return sys + "\n\n%s says to you: \"%s\"\n%s responds:" % [speaker_name, message, para_name]
