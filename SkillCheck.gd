## SkillCheck.gd — Unified D20 skill check utility (V12)
## Preload where needed: const SkillCheck = preload("res://SkillCheck.gd")
extends RefCounted
class_name SkillCheck

# ── Skill registry ─────────────────────────────────────────────────────────────
const SKILLS: Dictionary = {
	"STEALTH":          {"name": "Stealth",         "attr": "DEX"},
	"PERCEPTION":       {"name": "Perception",      "attr": "WIS"},
	"LOCKPICK":         {"name": "Lockpick",        "attr": "DEX"},
	"SLEIGHT_OF_HAND":  {"name": "Sleight of Hand", "attr": "DEX"},
	"ATHLETICS":        {"name": "Athletics",       "attr": "STR"},
	"PERSUASION":       {"name": "Persuasion",      "attr": "CHA"},
	"INTIMIDATION":     {"name": "Intimidation",    "attr": "CHA"},
	"DECEPTION":        {"name": "Deception",       "attr": "CHA"},
	"INVESTIGATION":    {"name": "Investigation",   "attr": "INT"},
}

# ── Lock / challenge DCs ───────────────────────────────────────────────────────
static func get_dc(lock_tier: String) -> int:
	match lock_tier:
		"SIMPLE":  return 8
		"COMPLEX": return 13
		"MAGICAL": return 17
		"ARCANE":  return 20
		_:         return 10

# ── Main roll entry point ──────────────────────────────────────────────────────
## Returns: { success: bool, roll: int, bonus: int, total: int,
##            dc: int, crit: bool, fumble: bool, flavor_text: String }
static func roll(skill_id: String, dc: int, player: Node) -> Dictionary:
	var raw: int   = randi_range(1, 20)
	var bonus: int = _calc_bonus(skill_id, player)
	var total: int = raw + bonus
	var crit:  bool = (raw == 20)
	var fumble:bool = (raw == 1)
	var success: bool = crit or (not fumble and total >= dc)
	var flavor: String = _flavor(skill_id, success, crit, fumble, raw, total, dc)
	return {
		"success":     success,
		"roll":        raw,
		"bonus":       bonus,
		"total":       total,
		"dc":          dc,
		"crit":        crit,
		"fumble":      fumble,
		"flavor_text": flavor,
	}

# ── Bonus calculation ──────────────────────────────────────────────────────────
static func _calc_bonus(skill_id: String, player: Node) -> int:
	var gm: Node = Engine.get_singleton("GameManager") \
		if Engine.has_singleton("GameManager") \
		else player.get_node_or_null("/root/GameManager")
	if gm == null:
		return 0

	var bonus: int = 0

	# ── Class bonuses ─────────────────────────────────────────────────────────
	var cls: String = str(gm.get("selected_class") if gm.get("selected_class") != null else "")
	match cls:
		"CUTPURSE":
			if skill_id in ["SLEIGHT_OF_HAND", "LOCKPICK"]:
				bonus += 4
		"ASSASSIN":
			if skill_id == "STEALTH":
				bonus += 3
		"SELLSWORD":
			if skill_id == "INTIMIDATION":
				bonus += 4

	# ── Race bonuses ──────────────────────────────────────────────────────────
	var race: String = str(gm.get("selected_race") if gm.get("selected_race") != null else "")
	match race:
		"HALFLING":
			if skill_id == "STEALTH":
				bonus += 2
		"ELF", "WOOD_ELF", "HIGH_ELF":
			if skill_id == "PERCEPTION":
				bonus += 2
		"DWARF":
			if skill_id in ["LOCKPICK", "INVESTIGATION"]:
				bonus += 4

	# ── Passive / mastery bonuses ─────────────────────────────────────────────
	if gm.has_method("has_passive"):
		if gm.has_passive("MASTERTHIEF") and skill_id in ["LOCKPICK", "SLEIGHT_OF_HAND"]:
			bonus += 3
		if gm.has_passive("TOOLS_BONUS") and skill_id in ["LOCKPICK", "INVESTIGATION"]:
			bonus += 2
		if gm.has_passive("SHADOW_STEP") and skill_id == "STEALTH":
			bonus += 2
		if gm.has_passive("SILVER_TONGUE") and skill_id in ["PERSUASION", "DECEPTION"]:
			bonus += 3

	# ── Relic bonuses ─────────────────────────────────────────────────────────
	if gm.has_method("has_relic"):
		if gm.has_relic("LOCKPICK_MASTER") and skill_id == "LOCKPICK":
			bonus += 3
		if gm.has_relic("SHADOW_CROWN") and skill_id == "STEALTH":
			bonus += 2
		if gm.has_relic("CURSED_MASK") and skill_id == "DECEPTION":
			bonus += 2
		if gm.has_relic("IRON_FIST") and skill_id == "INTIMIDATION":
			bonus += 3

	# ── Gear effect bonuses ───────────────────────────────────────────────────
	if gm.has_method("has_gear_effect"):
		if gm.has_gear_effect("LOCKPICK_BONUS") and skill_id == "LOCKPICK":
			bonus += 2
		if gm.has_gear_effect("PERCEPTION_BONUS") and skill_id == "PERCEPTION":
			bonus += 2

	return bonus

# ── Flavor text ───────────────────────────────────────────────────────────────
static func _flavor(skill_id: String, success: bool, crit: bool, fumble: bool,
					 raw: int, total: int, dc: int) -> String:
	if crit:
		match skill_id:
			"LOCKPICK":        return "NAT 20 — The lock surrenders instantly!"
			"STEALTH":         return "NAT 20 — PERFECT EXECUTION! Not a sound."
			"SLEIGHT_OF_HAND": return "NAT 20 — Gone before they blinked."
			"PERCEPTION":      return "NAT 20 — Your senses flare — nothing escapes you."
			"INTIMIDATION":    return "NAT 20 — They recoil in genuine terror."
			"PERSUASION":      return "NAT 20 — Completely convinced. They believe every word."
			"DECEPTION":       return "NAT 20 — Flawless. Not a flicker of suspicion."
			"INVESTIGATION":   return "NAT 20 — Every clue laid bare. Nothing hidden."
			"ATHLETICS":       return "NAT 20 — Effortless. Pure strength."
			_:                 return "NAT 20 — PERFECT EXECUTION!"

	if fumble:
		match skill_id:
			"LOCKPICK":        return "NAT 1 — Your hands shake — the tumblers scatter."
			"STEALTH":         return "NAT 1 — You trip over your own feet. Everyone heard that."
			"SLEIGHT_OF_HAND": return "NAT 1 — It clatters to the floor loudly."
			"PERCEPTION":      return "NAT 1 — You miss everything obvious."
			"INTIMIDATION":    return "NAT 1 — They laugh in your face."
			"PERSUASION":      return "NAT 1 — You've made things worse somehow."
			"DECEPTION":       return "NAT 1 — They see right through you."
			"INVESTIGATION":   return "NAT 1 — You manage to confuse yourself."
			"ATHLETICS":       return "NAT 1 — Your muscles fail at the worst moment."
			_:                 return "NAT 1 — Critical failure."

	if success:
		match skill_id:
			"LOCKPICK":        return "You slip the lock with practiced ease."
			"STEALTH":         return "You melt into the shadows unseen."
			"SLEIGHT_OF_HAND": return "Clean. They never felt a thing."
			"PERCEPTION":      return "Your eyes catch the telltale detail."
			"INTIMIDATION":    return "They back down — fast."
			"PERSUASION":      return "A convincing argument. They're nodding."
			"DECEPTION":       return "Your lie lands perfectly."
			"INVESTIGATION":   return "You piece it together. The answer is clear."
			"ATHLETICS":       return "Strength carries the day."
			_:                 return "Success. (%d vs DC %d)" % [total, dc]
	else:
		var margin: int = dc - total
		match skill_id:
			"LOCKPICK":
				return "The lock holds. %d short." % margin if margin <= 3 \
					else "Too complex. Your picks skitter uselessly."
			"STEALTH":
				return "A creak — you freeze. Too loud by %d." % margin if margin <= 3 \
					else "Your cover is blown entirely."
			"SLEIGHT_OF_HAND":
				return "A flicker of movement — almost caught."
			"PERCEPTION":
				return "You sense nothing. The detail slips past."
			"INTIMIDATION":
				return "They stand their ground, unmoved."
			"PERSUASION":
				return "They remain skeptical."
			"DECEPTION":
				return "Something about your story doesn't add up."
			"INVESTIGATION":
				return "Nothing useful stands out."
			"ATHLETICS":
				return "Not enough strength. You fall short by %d." % margin
			_:
				return "Failed. (%d vs DC %d)" % [total, dc]
