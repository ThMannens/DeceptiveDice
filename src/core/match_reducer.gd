extends RefCounted

const MatchEvent = preload("res://src/core/match_event.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Roster = preload("res://src/core/roster.gd")
const CombatResolver = preload("res://src/core/combat_resolver.gd")
const Moves = preload("res://src/core/moves.gd")
const Kits = preload("res://src/core/kits.gd")

## A challenge outcome that would otherwise settle for nothing is paid on the
## character's next defence instead, weakened by this much. It covers both a wrong
## call that cost the challenger nothing and a correct call that won the challenger
## nothing, so neither side of the challenge decision is ever free.
const EXPOSED_DEFENCE_PENALTY := 5
## Kept under its original key because the interface and the transcripts read it
## by name; it now marks exposure from either side of a challenge.
const COUNTER_EXPOSED := "exposed_after_wrong_call"


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

	# A kit may cap how high this character is allowed to claim.
	var sender := int(event["sender"])
	var claimant := _exchange_claimant(state, sender)
	if not claimant.is_empty():
		var ceiling := Kits.claim_ceiling(claimant)
		if value > int(ceiling["ceiling"]):
			return "Claim value is capped at %d this turn" % int(ceiling["ceiling"])
	return _apply_barrier_submission(state, event, "claims", MatchState.PHASE_CLAIM, MatchState.PHASE_CHALLENGE, effects)


## The character making this player's claim in the current exchange: the actor if
## they are attacking, otherwise the target defending against it.
static func _exchange_claimant(state: Dictionary, player: int) -> Dictionary:
	var action: Dictionary = state["exchange"]["action"]
	if action.is_empty():
		return {}
	var attacker_player := int(action["player"])
	var character_id := str(action["actor_id"]) if player == attacker_player else str(action["target_id"])
	var index := _find_character_index(state["teams"][player], character_id)
	if index < 0:
		return {}
	return state["teams"][player]["characters"][index]


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
	var true_rolls: Array = raw_true_rolls.duplicate()

	# A player who never produced a valid reveal is treated as caught at the worst
	# roll the claim allows, which is 1. Substituting the roll rather than adding a
	# separate damage path keeps the whole caught pipeline — kit hooks, exposure,
	# claim history — identical to being caught honestly. Refusing to reveal must
	# never beat being caught, so it resolves as the worst possible catch.
	var failed_reveals := _failed_reveal_players(state)
	for player in failed_reveals:
		# The opponent cannot know this roll, so whatever the payload carried for
		# it is not trusted and not required to be in range.
		true_rolls[player] = 1

	for player in [0, 1]:
		if player in failed_reveals:
			continue
		if int(true_rolls[player]) < 1 or int(true_rolls[player]) > 20:
			return "Resolution true rolls must be between 1 and 20"

	var attacker_player := int(action["player"])
	var defender_player := 1 - attacker_player
	var attacker_index := _find_character_index(state["teams"][attacker_player], str(action["actor_id"]))
	var defender_index := _find_character_index(state["teams"][defender_player], str(action["target_id"]))
	if attacker_index < 0 or defender_index < 0:
		return "The selected actor or target no longer exists"

	var attack_claim := _claim_value(state["exchange"]["claims"][attacker_player], int(true_rolls[attacker_player]))
	var defence_claim := _claim_value(state["exchange"]["claims"][defender_player], int(true_rolls[defender_player]))
	# A failed reveal counts as challenged whether or not the opponent called it,
	# so the claim is discarded rather than standing on an unverifiable roll.
	var attack_challenged := bool(state["exchange"]["challenges"][defender_player].get("challenge", false)) or attacker_player in failed_reveals
	var defence_challenged := bool(state["exchange"]["challenges"][attacker_player].get("challenge", false)) or defender_player in failed_reveals
	var attacker: Dictionary = state["teams"][attacker_player]["characters"][attacker_index]
	var defender: Dictionary = state["teams"][defender_player]["characters"][defender_index]
	var stance_defence_bonus := 5 if defender["effect_counters"].get("defensive_stance_active", false) else 0
	# A wrong call the defender made on a previous exchange leaves them exposed
	# on this one. Applied as a defence penalty so it uses the same path as the
	# stance bonus and shows up in the calculation breakdown.
	var exposure_penalty := EXPOSED_DEFENCE_PENALTY if defender["effect_counters"].get(COUNTER_EXPOSED, false) else 0
	if exposure_penalty > 0:
		defender["effect_counters"][COUNTER_EXPOSED] = false
		state["teams"][defender_player]["characters"][defender_index] = defender
		effects.append({
			"type": "status_expired",
			"player": defender_player,
			"character_id": defender["id"],
			"status": "EXPOSED",
		})

	var kit_notes: Array = []

	# Bookkeeping immunity is decided before anything else, because an immune claim
	# locks in automatically and the challenge against it never happens at all.
	# Bookkeeping works on padding, so it needs the true rolls the reveal produced.
	var attack_padding := attack_claim - int(true_rolls[attacker_player])
	var defence_padding := defence_claim - int(true_rolls[defender_player])

	var attack_immunity := Kits.claim_is_immune(
		attacker,
		attack_padding,
		state["teams"][attacker_player]["recorded_paddings"],
	)
	if bool(attack_immunity["immune"]):
		kit_notes.append_array(attack_immunity["notes"])
		attack_challenged = false
	var defence_immunity := Kits.claim_is_immune(
		defender,
		defence_padding,
		state["teams"][defender_player]["recorded_paddings"],
	)
	if bool(defence_immunity["immune"]):
		kit_notes.append_array(defence_immunity["notes"])
		defence_challenged = false

	var attack_damage_kit := Kits.attack_damage_modifier(attacker)
	kit_notes.append_array(attack_damage_kit["notes"])
	var margin_suppression := Kits.suppresses_margin_bonus(attacker)
	kit_notes.append_array(margin_suppression["notes"])

	# A wrong call is absorbed by the challenger's kit, so it is the defender who
	# decides whether the attack claim's wrong-call bonus applies, and the attacker
	# who decides the same for the defence claim.
	var absorb_attack_wrong_call := false
	if attack_challenged:
		var attack_absorption := Kits.absorbs_wrong_call(defender)
		absorb_attack_wrong_call = bool(attack_absorption["absorbed"])
		if absorb_attack_wrong_call:
			kit_notes.append_array(attack_absorption["notes"])
	var absorb_defence_wrong_call := false
	if defence_challenged:
		var defence_absorption := Kits.absorbs_wrong_call(attacker)
		absorb_defence_wrong_call = bool(defence_absorption["absorbed"])
		if absorb_defence_wrong_call:
			kit_notes.append_array(defence_absorption["notes"])

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
		int(move["defence_modifier"]) + stance_defence_bonus - exposure_penalty,
		int(move["damage_modifier"]) + int(attack_damage_kit["modifier"]),
		bool(margin_suppression["suppressed"]),
		absorb_attack_wrong_call,
		absorb_defence_wrong_call,
		attacker_player in failed_reveals,
		defender_player in failed_reveals,
	)
	if not resolution["ok"]:
		return str(resolution["error"])

	resolution["exchange_number"] = state["exchange_number"]
	resolution["failed_reveal_players"] = failed_reveals.duplicate()
	resolution["attacker_player"] = attacker_player
	resolution["defender_player"] = defender_player
	resolution["actor_id"] = action["actor_id"]
	resolution["target_id"] = action["target_id"]
	resolution["move_id"] = move_id
	resolution["stance_defence_bonus"] = stance_defence_bonus
	resolution["exposure_penalty"] = exposure_penalty
	# Kept so the interface can show the calculation term by term rather than
	# only its totals.
	resolution["move_attack_modifier"] = int(move["attack_modifier"])
	resolution["move_defence_modifier"] = int(move["defence_modifier"])
	resolution["move_damage_modifier"] = int(move["damage_modifier"])
	resolution["kit_damage_modifier"] = int(attack_damage_kit["modifier"])

	# A landed hit can be multiplied by the attacker's kit, and can drag the target
	# forward or hit an already-front target harder.
	resolution["kit_damage_multiplier"] = 1
	resolution["drag_extra_damage"] = 0
	resolution["drag_steps_forward"] = 0
	if bool(resolution["hit"]):
		var damage_kit := Kits.hit_damage_multiplier(attacker, resolution["attack"])
		var multiplier := int(damage_kit["multiplier"])
		if multiplier != 1:
			kit_notes.append_array(damage_kit["notes"])
			resolution["kit_damage_multiplier"] = multiplier
			resolution["hit_damage"] = int(resolution["hit_damage"]) * multiplier
		var hit_kit := Kits.on_hit(attacker, defender)
		if int(hit_kit["extra_damage"]) > 0 or int(hit_kit["steps_forward"]) > 0:
			kit_notes.append_array(hit_kit["notes"])
			resolution["drag_extra_damage"] = int(hit_kit["extra_damage"])
			resolution["drag_steps_forward"] = int(hit_kit["steps_forward"])
			resolution["hit_damage"] = int(resolution["hit_damage"]) + int(hit_kit["extra_damage"])

	# Kit hooks settle the caught-bluff damage before any of it lands. The attacker's
	# padding is resolved first, then the defender's, so the note order is stable.
	var attack_bluff := _settle_caught_bluff(
		attacker,
		defender,
		int(resolution["attacker_self_damage"]),
		kit_notes,
	)
	var defence_bluff := _settle_caught_bluff(
		defender,
		attacker,
		int(resolution["defender_self_damage"]),
		kit_notes,
	)
	resolution["attacker_self_damage"] = 0 if attack_bluff["redirected"] else int(attack_bluff["amount"])
	resolution["defender_self_damage"] = 0 if defence_bluff["redirected"] else int(defence_bluff["amount"])
	resolution["attacker_reflected_damage"] = int(attack_bluff["amount"]) if attack_bluff["redirected"] else 0
	resolution["defender_reflected_damage"] = int(defence_bluff["amount"]) if defence_bluff["redirected"] else 0
	_apply_wrong_call_exposure(state, resolution, attacker_player, attacker_index, defender_player, defender_index, effects)

	_update_recorded_paddings(state, attacker_player, attacker, attack_padding, attack_immunity, kit_notes, effects)
	_update_recorded_paddings(state, defender_player, defender, defence_padding, defence_immunity, kit_notes, effects)

	_append_claim_history(state, attacker_player, str(action["actor_id"]), resolution["attack"])
	_append_claim_history(state, defender_player, str(action["target_id"]), resolution["defence"])
	_apply_damage(state, attacker_player, attacker_index, int(resolution["attacker_self_damage"]), "CAUGHT_ATTACK_BLUFF", effects)
	_apply_damage(state, defender_player, defender_index, int(resolution["defender_self_damage"]), "CAUGHT_DEFENCE_BLUFF", effects)
	# Reflected padding is dealt by the challenger, so it lands on the bluffer as a
	# separate source that position scaling does not touch.
	_apply_damage(state, attacker_player, attacker_index, int(resolution["attacker_reflected_damage"]), "REFLECTED_ATTACK_BLUFF", effects)
	_apply_damage(state, defender_player, defender_index, int(resolution["defender_reflected_damage"]), "REFLECTED_DEFENCE_BLUFF", effects)
	_apply_damage(state, defender_player, defender_index, int(resolution["hit_damage"]), "ATTACK", effects)

	# Board movement caused by kits, after damage so a lethal hit still kills in
	# place rather than shuffling a corpse up the formation.
	if bool(attack_bluff["evaded"]):
		_swap_with_nearest_ally(state, attacker_player, attacker_index, effects)
	if bool(defence_bluff["evaded"]):
		_swap_with_nearest_ally(state, defender_player, defender_index, effects)
	if int(resolution["drag_steps_forward"]) > 0:
		_pull_toward_front(state, defender_player, defender_index, int(resolution["drag_steps_forward"]), effects)

	# Bookkeeping runs before the new cap is imposed, so an expiring cap from a
	# previous exchange clears without wiping the one this exchange just earned.
	_run_after_exchange_hooks(state, resolution, effects)

	# A correct challenge may cap the caught character's next claim.
	if str(resolution["attack"]["outcome"]) == CombatResolver.OUTCOME_CAUGHT:
		_impose_claim_cap(state, defender, attacker_player, attacker_index, resolution["attack"], kit_notes, effects)
	if str(resolution["defence"]["outcome"]) == CombatResolver.OUTCOME_CAUGHT:
		_impose_claim_cap(state, attacker, defender_player, defender_index, resolution["defence"], kit_notes, effects)

	resolution["kit_effects"] = kit_notes.duplicate(true)
	state["exchange"]["resolution"] = resolution.duplicate(true)
	state["last_resolution"] = resolution.duplicate(true)

	for note in kit_notes:
		effects.append({
			"type": "kit_effect_fired",
			"character_id": note["character_id"],
			"effect": note["effect"],
			"detail": note["detail"],
		})
	effects.append({
		"type": "exchange_resolved",
		"exchange_number": state["exchange_number"],
		"resolution": resolution.duplicate(true),
	})
	_complete_exchange(state, effects)
	return ""


## Settles one caught bluff through the kit hooks: the bluffer's kit may reduce the
## padding damage, then the challenger's kit may redirect what remains.
static func _settle_caught_bluff(
	bluffer: Dictionary,
	challenger: Dictionary,
	amount: int,
	kit_notes: Array,
) -> Dictionary:
	if amount <= 0:
		return {"amount": 0, "redirected": false, "evaded": false}

	# A kit may sidestep the damage entirely by moving instead. That happens before
	# any reduction, because nothing is taken and nothing is left to reflect.
	var evasion := Kits.evades_padding_by_swapping(bluffer)
	if bool(evasion["evades"]):
		kit_notes.append_array(evasion["notes"])
		return {"amount": 0, "redirected": false, "evaded": true}

	var modified := Kits.modify_self_damage(bluffer, amount)
	kit_notes.append_array(modified["notes"])
	var settled := int(modified["amount"])

	var redirection := Kits.redirect_self_damage(challenger, settled)
	kit_notes.append_array(redirection["notes"])
	return {"amount": settled, "redirected": bool(redirection["redirect"]), "evaded": false}


## Runs the after_exchange hook for both characters in the exchange. Kits may only
## set counters on their own character, so the reducer writes them back one by one.
static func _run_after_exchange_hooks(state: Dictionary, resolution: Dictionary, effects: Array) -> void:
	var attacker_player := int(resolution["attacker_player"])
	var defender_player := int(resolution["defender_player"])
	var participants := [
		[attacker_player, str(resolution["actor_id"]), resolution["attack"], resolution["defence"]],
		[defender_player, str(resolution["target_id"]), resolution["defence"], resolution["attack"]],
	]

	for participant in participants:
		var player := int(participant[0])
		var character_id := str(participant[1])
		var own_claim: Dictionary = participant[2]
		var opposing_claim: Dictionary = participant[3]
		var index := _find_character_index(state["teams"][player], character_id)
		if index < 0:
			continue
		var character: Dictionary = state["teams"][player]["characters"][index]
		var hook := Kits.after_exchange(character, own_claim, opposing_claim)
		var counters: Dictionary = hook["counters"]
		if counters.is_empty():
			continue
		for key in counters:
			character["effect_counters"][key] = counters[key]
		state["teams"][player]["characters"][index] = character
		for note in hook["notes"]:
			effects.append({
				"type": "kit_effect_fired",
				"character_id": note["character_id"],
				"effect": note["effect"],
				"detail": note["detail"],
			})


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

	# Deaths are cleared off the formation once everything else has settled. Damage
	# and kit movement both run before this, so a lethal hit still kills in place
	# and only then is the body moved out of the rank it was holding.
	for player in 2:
		_compact_formation(state, player, effects)

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
		_clear_round_scoped_counters(state)
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


## Moves the dead to the back so they never hold a rank the living need. A body
## left at position 3 otherwise walls off everyone behind it: Drag and the swap
## move both step through the next position up, and neither can step onto or past
## a corpse. The living keep their relative order and close up toward the front,
## then the dead fill the remaining ranks from the back.
static func _compact_formation(state: Dictionary, player: int, effects: Array) -> void:
	var characters: Array = state["teams"][player]["characters"]

	var living_indices: Array = []
	var dead_indices: Array = []
	for index in characters.size():
		if bool(characters[index]["is_alive"]):
			living_indices.append(index)
		else:
			dead_indices.append(index)
	if dead_indices.is_empty():
		return

	# Front-most first, so the living end up at the highest positions with their
	# order among themselves unchanged.
	living_indices.sort_custom(func(left, right): return int(characters[left]["position"]) > int(characters[right]["position"]))
	dead_indices.sort_custom(func(left, right): return int(characters[left]["position"]) > int(characters[right]["position"]))

	var next_position := characters.size()
	var ordered: Array = living_indices + dead_indices
	for index in ordered:
		var character: Dictionary = characters[index]
		var previous_position := int(character["position"])
		if previous_position != next_position:
			character["position"] = next_position
			characters[index] = character
			effects.append({
				"type": "position_changed",
				"player": player,
				"character_id": character["id"],
				"from_position": previous_position,
				"to_position": next_position,
				"reason": "FORMATION_COMPACTED",
			})
		next_position -= 1

	state["teams"][player]["characters"] = characters


## A wrong call normally punishes the challenger through the damage figure: an
## attacker wrongly challenged deals double, a defender wrongly challenged takes
## half. Neither applies when the attack produced no damage at all, which used to
## make challenging free for a defender who expected to win the roll. In that case
## the cost is deferred instead: the challenger defends at a penalty next time.
static func _apply_wrong_call_exposure(
	state: Dictionary,
	resolution: Dictionary,
	attacker_player: int,
	attacker_index: int,
	defender_player: int,
	defender_index: int,
	effects: Array,
) -> void:
	if int(resolution["hit_damage"]) > 0:
		return

	# The defender challenged an honest attacker.
	if str(resolution["attack"]["outcome"]) == CombatResolver.OUTCOME_WRONG_CALL:
		_expose_character(state, defender_player, defender_index, effects)
	# The attacker challenged an honest defender. Their wrong call halves damage
	# that never existed, so it is equally free without this.
	if str(resolution["defence"]["outcome"]) == CombatResolver.OUTCOME_WRONG_CALL:
		_expose_character(state, attacker_player, attacker_index, effects)

	# Catching a padded defence normally pays out by dropping the claim to the true
	# roll, which lets an attack through that the bluff would have stopped. When the
	# attack deals nothing regardless, that payout does not exist and the read was
	# free for the bluffer. Kits are allowed to wipe the padding damage on top of
	# that, so the reward cannot rest on it either: the caught defender is exposed
	# instead, and pays on their next defence.
	if str(resolution["defence"]["outcome"]) == CombatResolver.OUTCOME_CAUGHT:
		_expose_character(state, defender_player, defender_index, effects)


static func _expose_character(state: Dictionary, player: int, character_index: int, effects: Array) -> void:
	var character: Dictionary = state["teams"][player]["characters"][character_index]
	if not bool(character["is_alive"]):
		return
	character["effect_counters"][COUNTER_EXPOSED] = true
	state["teams"][player]["characters"][character_index] = character
	effects.append({
		"type": "status_applied",
		"player": player,
		"character_id": character["id"],
		"status": "EXPOSED",
		"defence_penalty": EXPOSED_DEFENCE_PENALTY,
	})


## Maintains one player's Bookkeeping ledger for the claim they just made.
##
## A claim that consumed an entry spends it and records nothing, so the same padding
## has to be earned again before it protects another claim. Any other recording claim
## puts its padding on the ledger, once: a padding already listed stays listed rather
## than stacking a duplicate that would grant two immunities.
static func _update_recorded_paddings(
	state: Dictionary,
	player: int,
	character: Dictionary,
	padding: int,
	immunity: Dictionary,
	kit_notes: Array,
	effects: Array,
) -> void:
	if not Kits.records_padding(character):
		return
	var recorded: Array = state["teams"][player]["recorded_paddings"]

	if bool(immunity.get("immune", false)):
		var consumed := int(immunity["consumes_padding"])
		recorded.erase(consumed)
		state["teams"][player]["recorded_paddings"] = recorded
		kit_notes.append({
			"character_id": str(character["id"]),
			"effect": Kits.EFFECT_BOOKKEEPING,
			"detail": "PADDING_CONSUMED",
			"padding": consumed,
		})
		effects.append({
			"type": "padding_consumed",
			"player": player,
			"character_id": character["id"],
			"padding": consumed,
		})
		return

	if padding in recorded:
		return
	recorded.append(padding)
	recorded.sort()
	state["teams"][player]["recorded_paddings"] = recorded
	kit_notes.append({
		"character_id": str(character["id"]),
		"effect": Kits.EFFECT_BOOKKEEPING,
		"detail": "PADDING_RECORDED",
		"padding": padding,
	})
	effects.append({
		"type": "padding_recorded",
		"player": player,
		"character_id": character["id"],
		"padding": padding,
	})


## Swaps a character with the living ally directly in front of them, falling back to
## the one behind when they are already at the front. Does nothing with no ally left.
static func _swap_with_nearest_ally(state: Dictionary, player: int, character_index: int, effects: Array) -> void:
	var characters: Array = state["teams"][player]["characters"]
	var character: Dictionary = characters[character_index]
	if not bool(character["is_alive"]):
		return
	var position := int(character["position"])

	var ally_index := -1
	for candidate_position in [position + 1, position - 1]:
		for index in characters.size():
			var candidate: Dictionary = characters[index]
			if index != character_index and bool(candidate["is_alive"]) and int(candidate["position"]) == candidate_position:
				ally_index = index
				break
		if ally_index >= 0:
			break
	if ally_index < 0:
		return

	var ally: Dictionary = characters[ally_index]
	character["position"] = int(ally["position"])
	ally["position"] = position
	characters[character_index] = character
	characters[ally_index] = ally
	state["teams"][player]["characters"] = characters
	effects.append({
		"type": "positions_swapped",
		"player": player,
		"character_id": character["id"],
		"ally_id": ally["id"],
	})


## Moves a character toward the front, swapping with whoever occupies each position
## it passes through so no two characters ever share a rank.
static func _pull_toward_front(state: Dictionary, player: int, character_index: int, steps: int, effects: Array) -> void:
	var characters: Array = state["teams"][player]["characters"]
	var character: Dictionary = characters[character_index]
	if not bool(character["is_alive"]):
		return

	for _step in steps:
		var position := int(character["position"])
		if position >= 4:
			break
		var occupant_index := -1
		for index in characters.size():
			if index != character_index and int(characters[index]["position"]) == position + 1:
				occupant_index = index
				break
		character["position"] = position + 1
		if occupant_index >= 0:
			var occupant: Dictionary = characters[occupant_index]
			occupant["position"] = position
			characters[occupant_index] = occupant
		characters[character_index] = character
		effects.append({
			"type": "position_changed",
			"player": player,
			"character_id": character["id"],
			"from_position": position,
			"to_position": position + 1,
		})
	state["teams"][player]["characters"] = characters


## Lets the challenger's kit cap the caught character's next claim.
static func _impose_claim_cap(
	state: Dictionary,
	challenger: Dictionary,
	caught_player: int,
	caught_index: int,
	caught_claim: Dictionary,
	kit_notes: Array,
	effects: Array,
) -> void:
	var cap_hook := Kits.imposes_claim_cap(challenger, caught_claim)
	var cap := int(cap_hook["cap"])
	if cap >= 20:
		return
	kit_notes.append_array(cap_hook["notes"])
	var character: Dictionary = state["teams"][caught_player]["characters"][caught_index]
	character["effect_counters"][Kits.COUNTER_AUDIT_CAP] = cap
	state["teams"][caught_player]["characters"][caught_index] = character
	effects.append({
		"type": "claim_cap_imposed",
		"player": caught_player,
		"character_id": character["id"],
		"cap": cap,
	})


## Kit state scoped to "this round" is dropped when the round rolls over.
static func _clear_round_scoped_counters(state: Dictionary) -> void:
	var round_scoped: Array = Kits.round_scoped_counters()
	for player in 2:
		var characters: Array = state["teams"][player]["characters"]
		for index in characters.size():
			var character: Dictionary = characters[index]
			for key in round_scoped:
				character["effect_counters"].erase(key)
			characters[index] = character
		state["teams"][player]["characters"] = characters


## The players whose reveal never arrived or arrived unusable.
##
## Covers both the timeout fallback written by _apply_timeout and a reveal whose
## secret failed verification at the protocol layer, which forwards an empty
## secret rather than aborting: the spec requires a bad reveal to resolve as
## caught, because aborting would let a losing player escape by disconnecting.
static func _failed_reveal_players(state: Dictionary) -> Array:
	var players: Array = []
	for player in [0, 1]:
		var reveal = state["exchange"]["reveals"][player]
		if reveal == null:
			continue
		if bool(reveal.get("timed_out", false)) or str(reveal.get("secret", "")).is_empty():
			players.append(player)
	return players


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
