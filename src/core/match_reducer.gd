extends RefCounted

const MatchEvent = preload("res://src/core/match_event.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Roster = preload("res://src/core/roster.gd")
const CombatResolver = preload("res://src/core/combat_resolver.gd")
const Moves = preload("res://src/core/moves.gd")


static func apply(state: Dictionary, event: Dictionary) -> Dictionary:
	var validation_error := MatchEvent.validate(event)
	if not validation_error.is_empty():
		return _rejected(state, validation_error)
	if str(event["match_id"]) != str(state.get("match_id", "")):
		return _rejected(state, "Event match_id does not match the current match")
	if int(event["exchange_number"]) != int(state.get("exchange_number", -1)):
		return _rejected(state, "Event exchange_number does not match the current exchange")
	if str(event["phase"]) != str(state.get("phase", "")):
		return _rejected(state, "Event phase does not match the current phase")

	var next_state: Dictionary = state.duplicate(true)
	var effects: Array = []
	var event_type := str(event["type"])
	var error := ""

	match event_type:
		MatchEvent.DRAFT_SUBMITTED:
			error = _apply_draft(next_state, event, effects)
		MatchEvent.FORMATION_SUBMITTED:
			error = _apply_formation(next_state, event, effects)
		MatchEvent.ACTION_SELECTED:
			error = _apply_action(next_state, event, effects)
		MatchEvent.COMMIT_SUBMITTED:
			error = _apply_barrier_submission(next_state, event, "commits", MatchState.PHASE_COMMIT, MatchState.PHASE_CLAIM, effects)
		MatchEvent.CLAIM_SUBMITTED:
			error = _apply_claim(next_state, event, effects)
		MatchEvent.CHALLENGE_SUBMITTED:
			error = _apply_challenge(next_state, event, effects)
		MatchEvent.REVEAL_SUBMITTED:
			error = _apply_barrier_submission(next_state, event, "reveals", MatchState.PHASE_REVEAL, MatchState.PHASE_RESOLVE, effects)
		MatchEvent.EXCHANGE_RESOLVED:
			error = _apply_resolution(next_state, event, effects)
		MatchEvent.PHASE_TIMEOUT:
			error = _apply_timeout(next_state, event, effects)
		MatchEvent.PLAYER_FORFEITED:
			error = _apply_forfeit(next_state, event, effects)

	if not error.is_empty():
		return _rejected(state, error)

	next_state["event_count"] = int(next_state["event_count"]) + 1
	return {
		"ok": true,
		"state": next_state,
		"effects": effects,
		"error": "",
	}


static func _apply_draft(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_DRAFT:
		return "Draft submissions are only accepted during DRAFT"
	var sender := int(event["sender"])
	var team: Dictionary = state["teams"][sender]
	if team["draft_locked"]:
		return "Player %d already submitted a draft" % sender

	var raw_character_ids = event["payload"]["character_ids"]
	if typeof(raw_character_ids) != TYPE_ARRAY:
		return "Draft character_ids must be an array"
	var character_ids: Array = raw_character_ids
	if character_ids.size() != 4:
		return "A draft must contain exactly four characters"
	var unique_ids := {}
	for raw_character_id in character_ids:
		var character_id := str(raw_character_id)
		if not Roster.has_character(character_id):
			return "Draft contains unknown character '%s'" % character_id
		if unique_ids.has(character_id):
			return "Draft characters must be unique"
		unique_ids[character_id] = true

	team["drafted_character_ids"] = character_ids.duplicate()
	team["characters"] = MatchState.create_character_states(character_ids)
	team["draft_locked"] = true
	state["teams"][sender] = team
	effects.append({"type": "draft_locked", "player": sender})

	if state["teams"][0]["draft_locked"] and state["teams"][1]["draft_locked"]:
		_change_phase(state, MatchState.PHASE_PLACEMENT, effects)
	return ""


static func _apply_formation(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_PLACEMENT:
		return "Formation submissions are only accepted during PLACEMENT"
	var sender := int(event["sender"])
	var team: Dictionary = state["teams"][sender]
	if team["formation_locked"]:
		return "Player %d already submitted a formation" % sender

	var raw_character_ids = event["payload"]["character_ids"]
	if typeof(raw_character_ids) != TYPE_ARRAY:
		return "Formation character_ids must be an array"
	var character_ids: Array = raw_character_ids
	if character_ids.size() != 4 or not _same_members(character_ids, team["drafted_character_ids"]):
		return "Formation must contain every drafted character exactly once"

	for position_index in character_ids.size():
		var character_id := str(character_ids[position_index])
		for character in team["characters"]:
			if character["id"] == character_id:
				character["position"] = position_index + 1
				break
	team["formation_locked"] = true
	state["teams"][sender] = team
	effects.append({"type": "formation_locked", "player": sender})

	if state["teams"][0]["formation_locked"] and state["teams"][1]["formation_locked"]:
		var starter := _determine_starting_player(state)
		state["status"] = MatchState.STATUS_ACTIVE
		state["exchange_number"] = 1
		state["round_number"] = 1
		state["active_player"] = starter
		state["starting_player"] = starter
		state["exchange"] = MatchState.create_empty_exchange(1)
		_change_phase(state, MatchState.PHASE_SELECT, effects)
	return ""


static func _apply_action(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_SELECT:
		return "Actions are only accepted during SELECT"
	var sender := int(event["sender"])
	if sender != int(state["active_player"]):
		return "Only the active player may select an action"
	var payload: Dictionary = event["payload"]
	for field in ["actor_id", "move_id", "target_id"]:
		if str(payload[field]).is_empty():
			return "Action field '%s' must not be empty" % field
	var move_id := str(payload["move_id"])
	if not Moves.has_move(move_id):
		return "Unknown move '%s'" % move_id

	var defender := 1 - sender
	var actor_id := str(payload["actor_id"])
	var target_id := str(payload["target_id"])
	var actor_index := _find_character_index(state["teams"][sender], actor_id)
	if actor_index < 0:
		return "Selected actor is not on the active player's team"
	var actor: Dictionary = state["teams"][sender]["characters"][actor_index]
	if not actor["is_alive"]:
		return "A defeated character cannot act"
	if actor_id in state["teams"][sender]["used_character_ids"]:
		return "That character has already acted this round"

	var move := Moves.get_move(move_id)
	var allowed_positions: Array = move["allowed_positions"]
	if not allowed_positions.is_empty() and int(actor["position"]) not in allowed_positions:
		return "%s requires position 3 or 4" % move["display_name"]

	match move["target_mode"]:
		Moves.TARGET_ENEMY:
			var target_index := _find_character_index(state["teams"][defender], target_id)
			if target_index < 0:
				return "Selected target is not on the opposing team"
			if not state["teams"][defender]["characters"][target_index]["is_alive"]:
				return "A defeated character cannot be targeted"
		Moves.TARGET_SELF:
			if target_id != actor_id:
				return "Defensive stance targets the acting character"
		Moves.TARGET_ADJACENT_ALLY:
			var ally_index := _find_character_index(state["teams"][sender], target_id)
			if ally_index < 0 or target_id == actor_id:
				return "Swap requires another allied character"
			var ally: Dictionary = state["teams"][sender]["characters"][ally_index]
			if not ally["is_alive"]:
				return "A defeated character cannot be swapped"
			if absi(int(actor["position"]) - int(ally["position"])) != 1:
				return "Swap requires an adjacent ally"

	if actor["effect_counters"].get("defensive_stance_active", false):
		actor["effect_counters"]["defensive_stance_active"] = false
		state["teams"][sender]["characters"][actor_index] = actor
		effects.append({"type": "status_expired", "player": sender, "character_id": actor_id, "status": "DEFENSIVE_STANCE"})
	state["exchange"]["action"] = {
		"player": sender,
		"actor_id": actor_id,
		"move_id": move_id,
		"target_id": target_id,
	}
	if Moves.is_attack(move_id):
		_change_phase(state, MatchState.PHASE_COMMIT, effects)
	else:
		_change_phase(state, MatchState.PHASE_RESOLVE, effects)
	return ""


static func _apply_claim(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_CLAIM:
		return "Claims are only accepted during CLAIM"
	var value := int(event["payload"]["value"])
	if value < 1 or value > 20:
		return "Claim value must be between 1 and 20"
	return _apply_barrier_submission(state, event, "claims", MatchState.PHASE_CLAIM, MatchState.PHASE_CHALLENGE, effects)


static func _apply_challenge(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_CHALLENGE:
		return "Challenges are only accepted during CHALLENGE"
	if typeof(event["payload"]["challenge"]) != TYPE_BOOL:
		return "Challenge value must be a boolean"
	return _apply_barrier_submission(state, event, "challenges", MatchState.PHASE_CHALLENGE, MatchState.PHASE_REVEAL, effects)


static func _apply_barrier_submission(
	state: Dictionary,
	event: Dictionary,
	field: String,
	expected_phase: String,
	next_phase: String,
	effects: Array,
) -> String:
	if state["phase"] != expected_phase:
		return "%s submissions are only accepted during %s" % [field.capitalize(), expected_phase]
	var sender := int(event["sender"])
	var submissions: Array = state["exchange"][field]
	if submissions[sender] != null:
		return "Player %d already submitted %s" % [sender, field]
	submissions[sender] = event["payload"].duplicate(true)
	state["exchange"][field] = submissions
	effects.append({"type": "%s_received" % field.trim_suffix("s"), "player": sender})
	if _both_submitted(submissions):
		_change_phase(state, next_phase, effects)
	return ""


static func _apply_resolution(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["phase"] != MatchState.PHASE_RESOLVE:
		return "An exchange can only resolve during RESOLVE"

	var action: Dictionary = state["exchange"]["action"]
	var move_id := str(action["move_id"])
	var move := Moves.get_move(move_id)
	if move["kind"] != Moves.KIND_ATTACK:
		var non_attack_error := _apply_non_attack_resolution(state, action, move, effects)
		if not non_attack_error.is_empty():
			return non_attack_error
		_complete_exchange(state, effects)
		return ""

	if not event["payload"].has("true_rolls"):
		return "Attack resolution requires true_rolls"
	var raw_true_rolls = event["payload"]["true_rolls"]
	if typeof(raw_true_rolls) != TYPE_ARRAY or raw_true_rolls.size() != 2:
		return "Resolution true_rolls must contain one roll per player"
	var true_rolls: Array = raw_true_rolls
	for roll in true_rolls:
		if int(roll) < 1 or int(roll) > 20:
			return "Resolution true rolls must be between 1 and 20"

	var attacker_player := int(action["player"])
	var defender_player := 1 - attacker_player
	var attacker_index := _find_character_index(state["teams"][attacker_player], str(action["actor_id"]))
	var defender_index := _find_character_index(state["teams"][defender_player], str(action["target_id"]))
	if attacker_index < 0 or defender_index < 0:
		return "The selected actor or target no longer exists"

	var attack_claim := _claim_value(state["exchange"]["claims"][attacker_player], int(true_rolls[attacker_player]))
	var defence_claim := _claim_value(state["exchange"]["claims"][defender_player], int(true_rolls[defender_player]))
	var attack_challenged := bool(state["exchange"]["challenges"][defender_player].get("challenge", false))
	var defence_challenged := bool(state["exchange"]["challenges"][attacker_player].get("challenge", false))
	var attacker: Dictionary = state["teams"][attacker_player]["characters"][attacker_index]
	var defender: Dictionary = state["teams"][defender_player]["characters"][defender_index]
	var stance_defence_bonus := 5 if defender["effect_counters"].get("defensive_stance_active", false) else 0

	var resolution := CombatResolver.resolve_exchange(
		attacker,
		defender,
		int(true_rolls[attacker_player]),
		attack_claim,
		attack_challenged,
		int(true_rolls[defender_player]),
		defence_claim,
		defence_challenged,
		int(move["attack_modifier"]),
		int(move["defence_modifier"]) + stance_defence_bonus,
		int(move["damage_modifier"]),
	)
	if not resolution["ok"]:
		return str(resolution["error"])

	resolution["exchange_number"] = state["exchange_number"]
	resolution["attacker_player"] = attacker_player
	resolution["defender_player"] = defender_player
	resolution["actor_id"] = action["actor_id"]
	resolution["target_id"] = action["target_id"]
	resolution["move_id"] = move_id
	resolution["stance_defence_bonus"] = stance_defence_bonus
	state["exchange"]["resolution"] = resolution.duplicate(true)
	state["last_resolution"] = resolution.duplicate(true)

	_append_claim_history(state, attacker_player, str(action["actor_id"]), resolution["attack"])
	_append_claim_history(state, defender_player, str(action["target_id"]), resolution["defence"])
	_apply_damage(state, attacker_player, attacker_index, int(resolution["attacker_self_damage"]), "CAUGHT_ATTACK_BLUFF", effects)
	_apply_damage(state, defender_player, defender_index, int(resolution["defender_self_damage"]), "CAUGHT_DEFENCE_BLUFF", effects)
	_apply_damage(state, defender_player, defender_index, int(resolution["hit_damage"]), "ATTACK", effects)

	effects.append({
		"type": "exchange_resolved",
		"exchange_number": state["exchange_number"],
		"resolution": resolution.duplicate(true),
	})
	_complete_exchange(state, effects)
	return ""


static func _apply_non_attack_resolution(
	state: Dictionary,
	action: Dictionary,
	move: Dictionary,
	effects: Array,
) -> String:
	var player := int(action["player"])
	var actor_index := _find_character_index(state["teams"][player], str(action["actor_id"]))
	if actor_index < 0:
		return "The acting character no longer exists"

	var resolution := {
		"ok": true,
		"error": "",
		"exchange_number": state["exchange_number"],
		"attacker_player": player,
		"defender_player": 1 - player,
		"actor_id": action["actor_id"],
		"target_id": action["target_id"],
		"move_id": action["move_id"],
		"hit": false,
		"hit_damage": 0,
		"non_attack": true,
		"summary": "",
	}

	match move["kind"]:
		Moves.KIND_STANCE:
			var actor: Dictionary = state["teams"][player]["characters"][actor_index]
			actor["effect_counters"]["defensive_stance_active"] = true
			state["teams"][player]["characters"][actor_index] = actor
			resolution["summary"] = "DEFENSIVE_STANCE_APPLIED"
			effects.append({
				"type": "status_applied",
				"player": player,
				"character_id": actor["id"],
				"status": "DEFENSIVE_STANCE",
				"defence_bonus": 5,
			})
		Moves.KIND_SWAP:
			var ally_index := _find_character_index(state["teams"][player], str(action["target_id"]))
			if ally_index < 0:
				return "The swap target no longer exists"
			var actor: Dictionary = state["teams"][player]["characters"][actor_index]
			var ally: Dictionary = state["teams"][player]["characters"][ally_index]
			var actor_position := int(actor["position"])
			actor["position"] = ally["position"]
			ally["position"] = actor_position
			state["teams"][player]["characters"][actor_index] = actor
			state["teams"][player]["characters"][ally_index] = ally
			resolution["summary"] = "POSITIONS_SWAPPED"
			effects.append({
				"type": "positions_swapped",
				"player": player,
				"character_id": actor["id"],
				"ally_id": ally["id"],
			})
		_:
			return "Unsupported non-attack move"

	state["exchange"]["resolution"] = resolution.duplicate(true)
	state["last_resolution"] = resolution.duplicate(true)
	effects.append({
		"type": "exchange_resolved",
		"exchange_number": state["exchange_number"],
		"resolution": resolution.duplicate(true),
	})
	return ""


static func _complete_exchange(state: Dictionary, effects: Array) -> void:
	var action: Dictionary = state["exchange"]["action"]
	var acting_player := int(action["player"])
	var actor_id := str(action["actor_id"])
	if actor_id not in state["teams"][acting_player]["used_character_ids"]:
		state["teams"][acting_player]["used_character_ids"].append(actor_id)

	var player_zero_defeated := _all_characters_dead(state["teams"][0])
	var player_one_defeated := _all_characters_dead(state["teams"][1])
	if player_zero_defeated or player_one_defeated:
		state["status"] = MatchState.STATUS_FINISHED
		state["winner_player"] = -1 if player_zero_defeated and player_one_defeated else (1 if player_zero_defeated else 0)
		_change_phase(state, MatchState.PHASE_FINISHED, effects)
		effects.append({
			"type": "match_finished",
			"winner_player": state["winner_player"],
			"reason": "ALL_CHARACTERS_DEFEATED",
		})
		return

	var other_player := 1 - acting_player
	var acting_player_has_turn := _has_unused_living_character(state["teams"][acting_player])
	var other_player_has_turn := _has_unused_living_character(state["teams"][other_player])
	if not acting_player_has_turn and not other_player_has_turn:
		state["round_number"] = int(state["round_number"]) + 1
		state["teams"][0]["used_character_ids"] = []
		state["teams"][1]["used_character_ids"] = []
		state["starting_player"] = _determine_starting_player(state)
		state["active_player"] = state["starting_player"]
		effects.append({"type": "round_started", "round_number": state["round_number"], "starting_player": state["starting_player"]})
	elif other_player_has_turn:
		state["active_player"] = other_player
	else:
		state["active_player"] = acting_player

	state["exchange_number"] = int(state["exchange_number"]) + 1
	state["exchange"] = MatchState.create_empty_exchange(state["exchange_number"])
	_change_phase(state, MatchState.PHASE_SELECT, effects)


static func _claim_value(claim: Dictionary, true_roll: int) -> int:
	if claim.get("timed_out", false):
		return true_roll
	return int(claim.get("value", 0))


static func _append_claim_history(state: Dictionary, player: int, character_id: String, result: Dictionary) -> void:
	state["teams"][player]["claim_history"].append({
		"exchange_number": state["exchange_number"],
		"character_id": character_id,
		"true_roll": result["true_roll"],
		"claim": result["claim"],
		"padding": result["padding"],
		"challenge_result": result["outcome"],
		"locked_in": result["locked_in"],
	})


static func _apply_damage(
	state: Dictionary,
	player: int,
	character_index: int,
	amount: int,
	source: String,
	effects: Array,
) -> void:
	if amount <= 0:
		return
	var character: Dictionary = state["teams"][player]["characters"][character_index]
	var hp_before := int(character["hp"])
	character["hp"] = maxi(0, hp_before - amount)
	character["is_alive"] = int(character["hp"]) > 0
	state["teams"][player]["characters"][character_index] = character
	effects.append({
		"type": "damage_applied",
		"player": player,
		"character_id": character["id"],
		"source": source,
		"amount": amount,
		"hp_before": hp_before,
		"hp_after": character["hp"],
	})


static func _apply_timeout(state: Dictionary, event: Dictionary, effects: Array) -> String:
	var timed_out_sender := int(event["payload"]["timed_out_sender"])
	if timed_out_sender not in [0, 1]:
		return "timed_out_sender must be 0 or 1"
	var phase: String = state["phase"]
	var field := ""
	var fallback: Dictionary = {}
	var next_phase := ""
	match phase:
		MatchState.PHASE_CLAIM:
			field = "claims"
			fallback = {"timed_out": true}
			next_phase = MatchState.PHASE_CHALLENGE
		MatchState.PHASE_CHALLENGE:
			field = "challenges"
			fallback = {"challenge": false, "timed_out": true}
			next_phase = MatchState.PHASE_REVEAL
		MatchState.PHASE_REVEAL:
			field = "reveals"
			fallback = {"secret": "", "timed_out": true}
			next_phase = MatchState.PHASE_RESOLVE
		_:
			return "Timeout outcome for phase %s is not implemented" % phase

	var submissions: Array = state["exchange"][field]
	if submissions[timed_out_sender] != null:
		return "Player %d already submitted during %s" % [timed_out_sender, phase]
	submissions[timed_out_sender] = fallback
	state["exchange"][field] = submissions
	state["exchange"]["timeouts"].append({"phase": phase, "player": timed_out_sender})
	effects.append({"type": "phase_timed_out", "phase": phase, "player": timed_out_sender})
	if _both_submitted(submissions):
		_change_phase(state, next_phase, effects)
	return ""


static func _apply_forfeit(state: Dictionary, event: Dictionary, effects: Array) -> String:
	if state["status"] in [MatchState.STATUS_FINISHED, MatchState.STATUS_ABORTED]:
		return "The match has already ended"
	var forfeiting_player := int(event["sender"])
	state["winner_player"] = 1 - forfeiting_player
	state["status"] = MatchState.STATUS_FINISHED
	_change_phase(state, MatchState.PHASE_FINISHED, effects)
	effects.append({
		"type": "match_finished",
		"winner_player": state["winner_player"],
		"reason": str(event["payload"].get("reason", "forfeit")),
	})
	return ""


static func _determine_starting_player(state: Dictionary) -> int:
	var highest_initiative := [-999, -999]
	for player in [0, 1]:
		for character in state["teams"][player]["characters"]:
			if character["is_alive"]:
				highest_initiative[player] = maxi(highest_initiative[player], int(character["initiative"]))
	return 1 if highest_initiative[1] > highest_initiative[0] else 0


static func _has_unused_living_character(team: Dictionary) -> bool:
	for character in team["characters"]:
		if character["is_alive"] and character["id"] not in team["used_character_ids"]:
			return true
	return false


static func _all_characters_dead(team: Dictionary) -> bool:
	for character in team["characters"]:
		if character["is_alive"]:
			return false
	return true


static func _find_character_index(team: Dictionary, character_id: String) -> int:
	for index in team["characters"].size():
		if str(team["characters"][index]["id"]) == character_id:
			return index
	return -1


static func _same_members(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	var seen := {}
	for value in left:
		var key := str(value)
		if seen.has(key):
			return false
		seen[key] = true
	for value in right:
		if not seen.has(str(value)):
			return false
	return true


static func _both_submitted(submissions: Array) -> bool:
	return submissions[0] != null and submissions[1] != null


static func _change_phase(state: Dictionary, next_phase: String, effects: Array) -> void:
	var previous_phase: String = state["phase"]
	state["phase"] = next_phase
	effects.append({"type": "phase_changed", "from": previous_phase, "to": next_phase})


static func _rejected(state: Dictionary, error: String) -> Dictionary:
	return {
		"ok": false,
		"state": state,
		"effects": [],
		"error": error,
	}
