extends SceneTree

## G4 — two scripted bots play complete matches through the reducer.
##
## Asserts the three properties the spec names: the match terminates, no state
## hash mismatch occurs, and HP stays within bounds throughout. Termination is
## the load-bearing one. Every other test drives a fixed number of exchanges, so
## a rule that lets a match run forever — a turn that never advances, a round that
## never rolls over, a character that can act twice — is invisible to all of them.
##
## Runs the reducer directly rather than a coordinator, because the coordinators
## carry a transport or an RNG and this test needs neither. Rolls are supplied
## from a seeded generator standing in for what commit-reveal would derive.

const BotPolicy = preload("res://src/bots/bot_policy.gd")
const MatchEvent = preload("res://src/core/match_event.gd")
const MatchReducer = preload("res://src/core/match_reducer.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Moves = preload("res://src/core/moves.gd")
const StateHash = preload("res://src/core/state_hash.gd")

## Above any plausible match length. A real match ends in tens of exchanges, so
## reaching this means the state machine stopped making progress.
const MAX_EXCHANGES := 2000
## Enough seeds that a rule which stalls only on particular roll sequences shows
## up, without making the suite slow.
const MATCH_COUNT := 12

var _failed := false


func _initialize() -> void:
	var lengths: Array = []
	for seed_value in MATCH_COUNT:
		var summary := _play_match(seed_value)
		if _failed:
			break
		lengths.append(int(summary["exchanges"]))

	if not _failed:
		lengths.sort()
		print("PASS: %d bot matches, %d to %d exchanges (median %d)" % [
			MATCH_COUNT, lengths[0], lengths[-1], lengths[lengths.size() / 2],
		])
	_finish(1 if _failed else 0)


func _play_match(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# One honest bot against one that always pads: the two extremes of the claim
	# decision, so a single match exercises both sides of every resolution row.
	var bots := [
		BotPolicy.new(BotPolicy.POLICY_HONEST, seed_value),
		BotPolicy.new(BotPolicy.POLICY_MAX_PAD, seed_value + 1000),
	]

	var state := MatchState.create("g4-seed-%d" % seed_value, ["honest", "padder"])
	state = _apply(state, MatchEvent.DRAFT_SUBMITTED, 0, {"character_ids": ["scribe", "knight", "bard", "rogue"]})
	state = _apply(state, MatchEvent.DRAFT_SUBMITTED, 1, {"character_ids": ["wizard", "knight", "bard", "rogue"]})
	state = _apply(state, MatchEvent.FORMATION_SUBMITTED, 0, {"character_ids": ["scribe", "bard", "rogue", "knight"]})
	state = _apply(state, MatchEvent.FORMATION_SUBMITTED, 1, {"character_ids": ["knight", "rogue", "bard", "wizard"]})
	if _failed:
		return {"exchanges": 0}

	var exchanges := 0
	while str(state["status"]) == MatchState.STATUS_ACTIVE:
		exchanges += 1
		if exchanges > MAX_EXCHANGES:
			_fail("seed %d did not terminate within %d exchanges" % [seed_value, MAX_EXCHANGES])
			return {"exchanges": exchanges}

		var before_exchange := int(state["exchange_number"])
		state = _play_exchange(state, bots, rng, seed_value)
		if _failed:
			return {"exchanges": exchanges}
		_check_hp_bounds(state, seed_value)
		if _failed:
			return {"exchanges": exchanges}

		# Progress, not just legality: an exchange that resolves without advancing
		# the counter would loop forever below the MAX_EXCHANGES ceiling.
		if str(state["status"]) == MatchState.STATUS_ACTIVE and int(state["exchange_number"]) <= before_exchange:
			_fail("seed %d resolved exchange %d without advancing" % [seed_value, before_exchange])
			return {"exchanges": exchanges}

	if int(state["winner_player"]) not in [0, 1]:
		_fail("seed %d finished with no winner" % seed_value)
	return {"exchanges": exchanges}


func _play_exchange(state: Dictionary, bots: Array, rng: RandomNumberGenerator, seed_value: int) -> Dictionary:
	var player := int(state["active_player"])
	var action: Dictionary = bots[player].choose_action(state, player)
	if action.is_empty():
		_fail("seed %d: the active player had no legal action" % seed_value)
		return state
	state = _apply(state, MatchEvent.ACTION_SELECTED, player, action)
	if _failed:
		return state

	# Stance and swap resolve immediately, with no dice at all.
	if not Moves.is_attack(str(action["move_id"])):
		return _apply(state, MatchEvent.EXCHANGE_RESOLVED, -1, {})

	for sender in [0, 1]:
		state = _apply(state, MatchEvent.COMMIT_SUBMITTED, sender, {
			"roll_commit": "bot-%d" % sender,
			"observer_secret": "bot-observer-%d" % sender,
		})
	if _failed:
		return state

	# Stands in for the value commit-reveal would derive. The bots never see it
	# before claiming, which is the only property that matters here.
	var true_rolls := [rng.randi_range(1, 20), rng.randi_range(1, 20)]
	for sender in [0, 1]:
		state = _apply(state, MatchEvent.CLAIM_SUBMITTED, sender, {
			"value": bots[sender].choose_claim(state, sender, int(true_rolls[sender])),
		})
	if _failed:
		return state

	for sender in [0, 1]:
		var opponent_claim := int(state["exchange"]["claims"][1 - sender].get("value", 0))
		state = _apply(state, MatchEvent.CHALLENGE_SUBMITTED, sender, {
			"challenge": bots[sender].choose_challenge(state, sender, opponent_claim),
		})
	if _failed:
		return state

	for sender in [0, 1]:
		state = _apply(state, MatchEvent.REVEAL_SUBMITTED, sender, {"secret": "bot-reveal-%d" % sender})
	if _failed:
		return state

	var before := StateHash.hash_state(state)
	state = _apply(state, MatchEvent.EXCHANGE_RESOLVED, -1, {"true_rolls": true_rolls})
	if _failed:
		return state
	# Both peers hash the same state after every resolution, so the hash has to be
	# a function of the state alone. Re-hashing an unchanged copy catches any map
	# iteration or float formatting that leaked non-determinism into the encoding.
	if StateHash.hash_state(state) != StateHash.hash_state(state.duplicate(true)):
		_fail("seed %d: state hash is not stable across identical states" % seed_value)
	if before == StateHash.hash_state(state):
		_fail("seed %d: resolving an exchange did not change the state hash" % seed_value)
	return state


## HP never below zero and never above the character's starting maximum.
func _check_hp_bounds(state: Dictionary, seed_value: int) -> void:
	for player in [0, 1]:
		for character in state["teams"][player]["characters"]:
			var hp := int(character["hp"])
			var max_hp := int(character["max_hp"])
			if hp < 0 or hp > max_hp:
				_fail("seed %d: %s has %d HP, outside 0..%d" % [
					seed_value, str(character["id"]), hp, max_hp,
				])
				return
			# A dead character must read as dead, or the win check never fires.
			if (hp == 0) != (not bool(character["is_alive"])):
				_fail("seed %d: %s has %d HP but is_alive is %s" % [
					seed_value, str(character["id"]), hp, character["is_alive"],
				])
				return


func _apply(state: Dictionary, event_type: String, sender: int, payload: Dictionary) -> Dictionary:
	if _failed:
		return state
	var event := MatchEvent.create(
		event_type,
		str(state["match_id"]),
		int(state["exchange_number"]),
		str(state["phase"]),
		sender,
		payload,
	)
	var result := MatchReducer.apply(state, event)
	if not result["ok"]:
		_fail("%s from player %d was rejected: %s" % [event_type, sender, str(result["error"])])
		return state
	return result["state"]


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("FAIL: %s" % message)


func _finish(code: int) -> void:
	var result_file := FileAccess.open("res://tests/full-match-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(str(code))
	quit(code)
