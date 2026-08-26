extends RefCounted

const KIND_ATTACK := "ATTACK"
const KIND_STANCE := "STANCE"
const KIND_SWAP := "SWAP"

const TARGET_ENEMY := "ENEMY"
const TARGET_SELF := "SELF"
const TARGET_ADJACENT_ALLY := "ADJACENT_ALLY"

const DEFINITIONS := {
	"light_attack": {
		"display_name": "Light attack",
		"kind": KIND_ATTACK,
		"target_mode": TARGET_ENEMY,
		"attack_modifier": 0,
		"defence_modifier": 0,
		"damage_modifier": 0,
		"allowed_positions": [],
	},
	"heavy_attack": {
		"display_name": "Heavy attack",
		"kind": KIND_ATTACK,
		"target_mode": TARGET_ENEMY,
		"attack_modifier": -4,
		"defence_modifier": 0,
		"damage_modifier": 8,
		"allowed_positions": [3, 4],
	},
	"defensive_stance": {
		"display_name": "Defensive stance",
		"kind": KIND_STANCE,
		"target_mode": TARGET_SELF,
		"attack_modifier": 0,
		"defence_modifier": 0,
		"damage_modifier": 0,
		"allowed_positions": [],
	},
	"swap": {
		"display_name": "Swap",
		"kind": KIND_SWAP,
		"target_mode": TARGET_ADJACENT_ALLY,
		"attack_modifier": 0,
		"defence_modifier": 0,
		"damage_modifier": 0,
		"allowed_positions": [],
	},
}


static func has_move(move_id: String) -> bool:
	return DEFINITIONS.has(move_id)


static func get_move(move_id: String) -> Dictionary:
	if not has_move(move_id):
		return {}
	return DEFINITIONS[move_id].duplicate(true)


static func is_attack(move_id: String) -> bool:
	return has_move(move_id) and DEFINITIONS[move_id]["kind"] == KIND_ATTACK
