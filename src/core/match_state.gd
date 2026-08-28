extends RefCounted

const Roster = preload("res://src/core/roster.gd")

const STATUS_DRAFT := "DRAFT"
const STATUS_ACTIVE := "ACTIVE"
const STATUS_FINISHED := "FINISHED"
const STATUS_ABORTED := "ABORTED"

const PHASE_DRAFT := "DRAFT"
const PHASE_PLACEMENT := "PLACEMENT"
const PHASE_SELECT := "SELECT"
const PHASE_COMMIT := "COMMIT"
const PHASE_CLAIM := "CLAIM"
const PHASE_CHALLENGE := "CHALLENGE"
const PHASE_REVEAL := "REVEAL"
const PHASE_RESOLVE := "RESOLVE"
const PHASE_FINISHED := "FINISHED"

const VALID_PHASES := [
	PHASE_DRAFT,
	PHASE_PLACEMENT,
	PHASE_SELECT,
	PHASE_COMMIT,
	PHASE_CLAIM,
	PHASE_CHALLENGE,
	PHASE_REVEAL,
	PHASE_RESOLVE,
	PHASE_FINISHED,
]


static func create(match_id: String, player_ids: Array) -> Dictionary:
	assert(not match_id.is_empty(), "match_id must not be empty")
	assert(player_ids.size() == 2, "A match requires exactly two players")
	assert(str(player_ids[0]) != str(player_ids[1]), "Player ids must be unique")

	return {
		"schema_version": 1,
		"match_id": match_id,
		"status": STATUS_DRAFT,
		"phase": PHASE_DRAFT,
		"exchange_number": 0,
		"round_number": 0,
		"active_player": -1,
		"starting_player": -1,
		"winner_player": -1,
		"teams": [
			_create_team(str(player_ids[0])),
			_create_team(str(player_ids[1])),
		],
		"exchange": create_empty_exchange(0),
		"last_resolution": {},
		"event_count": 0,
	}


static func create_empty_exchange(exchange_number: int) -> Dictionary:
	return {
		"number": exchange_number,
		"action": {},
		"commits": [null, null],
		"claims": [null, null],
		"challenges": [null, null],
		"reveals": [null, null],
		"timeouts": [],
		"resolution": {},
	}


static func create_character_states(character_ids: Array) -> Array:
	var characters: Array = []
	for raw_character_id in character_ids:
		characters.append(Roster.create_character_state(str(raw_character_id)))
	return characters


static func _create_team(player_id: String) -> Dictionary:
	return {
		"player_id": player_id,
		"draft_locked": false,
		"formation_locked": false,
		"drafted_character_ids": [],
		"characters": [],
		"used_character_ids": [],
		"claim_history": [],
		# Paddings this player has on record for Bookkeeping. Distinct from
		# claim_history, which is an append-only audit log: entries here are
		# consumed when they grant immunity and must be earned again.
		"recorded_paddings": [],
		"effect_counters": {},
	}
