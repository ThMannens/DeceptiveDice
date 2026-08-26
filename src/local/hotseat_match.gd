extends RefCounted

const MatchEvent = preload("res://src/core/match_event.gd")
const MatchReducer = preload("res://src/core/match_reducer.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Moves = preload("res://src/core/moves.gd")

const PLAYER_NAMES := ["Player 1", "Player 2"]

var state: Dictionary = {}
var true_rolls := [0, 0]
var last_error := ""
var _rng := RandomNumberGenerator.new()


func start_new_match() -> Dictionary:
	_rng.randomize()
	last_error = ""
	true_rolls = [0, 0]
	state = MatchState.create("local-hotseat", PLAYER_NAMES)

	var setup_events := [
		[MatchEvent.DRAFT_SUBMITTED, 0, {"character_ids": ["ledger", "bruiser", "gambler", "hook"]}],
		[MatchEvent.DRAFT_SUBMITTED, 1, {"character_ids": ["mirror", "bruiser", "gambler", "hook"]}],
		[MatchEvent.FORMATION_SUBMITTED, 0, {"character_ids": ["ledger", "gambler", "hook", "bruiser"]}],
		[MatchEvent.FORMATION_SUBMITTED, 1, {"character_ids": ["bruiser", "hook", "gambler", "mirror"]}],
	]
	var result := {"ok": true, "state": state, "effects": [], "error": ""}
	for setup_event in setup_events:
		result = _apply(str(setup_event[0]), int(setup_event[1]), setup_event[2])
		if not result["ok"]:
			return result
	return result


func select_action(actor_id: String, move_id: String, target_id: String) -> Dictionary:
	return _apply(MatchEvent.ACTION_SELECTED, int(state["active_player"]), {
		"actor_id": actor_id,
		"move_id": move_id,
		"target_id": target_id,
	})


func prepare_attack_exchange() -> Dictionary:
	if state.get("phase") != MatchState.PHASE_COMMIT:
		return _local_error("The match is not waiting for dice commits")
	true_rolls = [_rng.randi_range(1, 20), _rng.randi_range(1, 20)]
	var nonce := str(_rng.randi())
	var first := _apply(MatchEvent.COMMIT_SUBMITTED, 0, {
		"roll_commit": "local-0-%s" % nonce,
		"observer_secret": "local-observer-0-%s" % nonce,
	})
	if not first["ok"]:
		return first
	return _apply(MatchEvent.COMMIT_SUBMITTED, 1, {
		"roll_commit": "local-1-%s" % nonce,
		"observer_secret": "local-observer-1-%s" % nonce,
	})


func submit_claim(player: int, value: int) -> Dictionary:
	return _apply(MatchEvent.CLAIM_SUBMITTED, player, {"value": value})


func submit_challenge(player: int, challenge: bool) -> Dictionary:
	return _apply(MatchEvent.CHALLENGE_SUBMITTED, player, {"challenge": challenge})


func resolve_attack_exchange() -> Dictionary:
	var first := _apply(MatchEvent.REVEAL_SUBMITTED, 0, {"secret": "local-reveal-0"})
	if not first["ok"]:
		return first
	var second := _apply(MatchEvent.REVEAL_SUBMITTED, 1, {"secret": "local-reveal-1"})
	if not second["ok"]:
		return second
	return _apply(MatchEvent.EXCHANGE_RESOLVED, -1, {"true_rolls": true_rolls.duplicate()})


func resolve_non_attack_exchange() -> Dictionary:
	return _apply(MatchEvent.EXCHANGE_RESOLVED, -1, {})


func available_actors(player: int) -> Array:
	var available: Array = []
	for character in state["teams"][player]["characters"]:
		if character["is_alive"] and character["id"] not in state["teams"][player]["used_character_ids"]:
			available.append(character)
	return available


func valid_targets(player: int, actor_id: String, move_id: String) -> Array:
	var targets: Array = []
	if not Moves.has_move(move_id):
		return targets
	var move := Moves.get_move(move_id)
	var actor := find_character(player, actor_id)
	if actor.is_empty():
		return targets

	match move["target_mode"]:
		Moves.TARGET_ENEMY:
			for character in state["teams"][1 - player]["characters"]:
				if character["is_alive"]:
					targets.append(character)
		Moves.TARGET_SELF:
			targets.append(actor)
		Moves.TARGET_ADJACENT_ALLY:
			for character in state["teams"][player]["characters"]:
				if character["is_alive"] and character["id"] != actor_id and absi(int(character["position"]) - int(actor["position"])) == 1:
					targets.append(character)
	return targets


func find_character(player: int, character_id: String) -> Dictionary:
	for character in state["teams"][player]["characters"]:
		if character["id"] == character_id:
			return character
	return {}


func _apply(event_type: String, sender: int, payload: Dictionary) -> Dictionary:
	var event := MatchEvent.create(
		event_type,
		str(state["match_id"]),
		int(state["exchange_number"]),
		str(state["phase"]),
		sender,
		payload,
	)
	var result := MatchReducer.apply(state, event)
	if result["ok"]:
		state = result["state"]
		last_error = ""
	else:
		last_error = str(result["error"])
	return result


func _local_error(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "state": state, "effects": [], "error": message}
