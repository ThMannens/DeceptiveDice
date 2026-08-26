extends RefCounted

const OUTCOME_HONEST_PASS := "HONEST_PASS"
const OUTCOME_PADDED_PASS := "PADDED_PASS"
const OUTCOME_CAUGHT := "CAUGHT"
const OUTCOME_WRONG_CALL := "WRONG_CALL"

const POSITION_DAMAGE_PERCENT := {
	1: 70,
	2: 85,
	3: 100,
	4: 120,
}


static func resolve_exchange(
	attacker: Dictionary,
	defender: Dictionary,
	attack_roll: int,
	attack_claim: int,
	attack_challenged: bool,
	defence_roll: int,
	defence_claim: int,
	defence_challenged: bool,
	attack_modifier: int = 0,
	defence_modifier: int = 0,
	damage_modifier: int = 0,
) -> Dictionary:
	var attack_result := _resolve_claim(attack_roll, attack_claim, attack_challenged, true)
	if not attack_result["ok"]:
		return attack_result
	var defence_result := _resolve_claim(defence_roll, defence_claim, defence_challenged, false)
	if not defence_result["ok"]:
		return defence_result

	var position := int(defender.get("position", 0))
	if not POSITION_DAMAGE_PERCENT.has(position):
		return {"ok": false, "error": "Target position must be between 1 and 4"}

	var result := {
		"ok": true,
		"error": "",
		"attack": attack_result,
		"defence": defence_result,
		"effective_attack": 0,
		"effective_defence": 0,
		"margin": 0,
		"hit": false,
		"miss_reason": "",
		"unscaled_damage": 0,
		"position_damage_percent": POSITION_DAMAGE_PERCENT[position],
		"scaled_damage": 0,
		"attack_damage_multiplier": 1,
		"defence_damage_divisor": 1,
		"hit_damage": 0,
		"attacker_self_damage": int(attack_result["self_damage"]),
		"defender_self_damage": int(defence_result["self_damage"]),
	}

	if attack_result["cancelled"]:
		result["miss_reason"] = "ATTACK_CAUGHT"
		return result

	result["effective_attack"] = int(attack_result["resolved_value"]) + int(attacker["attack"]) + attack_modifier
	result["effective_defence"] = int(defence_result["resolved_value"]) + int(defender["defence"]) + defence_modifier
	result["margin"] = int(result["effective_attack"]) - int(result["effective_defence"])
	if result["margin"] <= 0:
		result["miss_reason"] = "DEFENDED"
		return result

	result["hit"] = true
	result["unscaled_damage"] = maxi(0, int(attacker["damage"]) + damage_modifier + int(result["margin"]))
	result["scaled_damage"] = floori(float(int(result["unscaled_damage"]) * int(result["position_damage_percent"])) / 100.0)

	var modified_damage := int(result["scaled_damage"])
	if attack_result["outcome"] == OUTCOME_WRONG_CALL:
		result["attack_damage_multiplier"] = 2
		modified_damage *= 2
	if defence_result["outcome"] == OUTCOME_WRONG_CALL:
		result["defence_damage_divisor"] = 2
		modified_damage = floori(float(modified_damage) / 2.0)
	result["hit_damage"] = modified_damage
	return result


static func _resolve_claim(roll: int, claim: int, challenged: bool, is_attack: bool) -> Dictionary:
	if roll < 1 or roll > 20:
		return {"ok": false, "error": "True roll must be between 1 and 20"}
	if claim < roll or claim > 20:
		return {"ok": false, "error": "Claim must be between the true roll and 20"}

	var padding := claim - roll
	var is_padded := padding > 0
	var outcome := OUTCOME_HONEST_PASS
	if challenged:
		outcome = OUTCOME_CAUGHT if is_padded else OUTCOME_WRONG_CALL
	elif is_padded:
		outcome = OUTCOME_PADDED_PASS

	return {
		"ok": true,
		"error": "",
		"true_roll": roll,
		"claim": claim,
		"padding": padding,
		"is_padded": is_padded,
		"challenged": challenged,
		"outcome": outcome,
		"resolved_value": roll if outcome == OUTCOME_CAUGHT else claim,
		"locked_in": outcome != OUTCOME_CAUGHT,
		"bluff_effects_fire": is_padded and outcome == OUTCOME_PADDED_PASS,
		"cancelled": is_attack and outcome == OUTCOME_CAUGHT,
		"self_damage": padding if outcome == OUTCOME_CAUGHT else 0,
	}
