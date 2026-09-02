extends RefCounted

## Scripted policies that read match state and emit intents (G3).
##
## Bots exist so a full match can run without a second human: workstream G4 plays
## two of them against each other and asserts the match terminates. They are also
## the sanity baseline for balance questions, because a policy that never lies and
## a policy that always lies bracket the range a real player moves between.
##
## A policy is pure in the same sense the rules core is: it reads state and
## returns a choice. It never applies an event, never rolls, and never holds a
## reference to a coordinator, so the same policy drives hot-seat, the network
## coordinator, or a transcript generator without changes.

const Moves = preload("res://src/core/moves.gd")

## Claims its true roll every time. The honest baseline: it never takes padding
## damage and never wins a bluff, so a match between two of these measures what
## the raw combat numbers do with no deception at all.
const POLICY_HONEST := "HONEST"
## Claims 20 every time. The opposite extreme: maximum padding, so it is caught
## constantly and is the fastest way to see whether padding damage is punishing
## enough to matter.
const POLICY_MAX_PAD := "MAX_PAD"

const VALID_POLICIES := [POLICY_HONEST, POLICY_MAX_PAD]


var policy := POLICY_HONEST
## Bots must not call randi() directly, because a full-match test that fails has
## to be reproducible from its seed alone.
var _rng := RandomNumberGenerator.new()


func _init(bot_policy: String = POLICY_HONEST, seed_value: int = 0) -> void:
	policy = bot_policy if bot_policy in VALID_POLICIES else POLICY_HONEST
	_rng.seed = seed_value


## Picks a character, a move, and a target for the active player's turn.
##
## Returns an empty dictionary when the player has no legal action, which the
## caller must treat as a stalled turn rather than as a pass: the phase does not
## advance until the active player acts.
func choose_action(state: Dictionary, player: int) -> Dictionary:
	var actors := _available_actors(state, player)
	if actors.is_empty():
		return {}
	var actor: Dictionary = actors[_rng.randi_range(0, actors.size() - 1)]

	# Heavy attack whenever the position allows it, so the position restriction
	# and its modifiers are exercised rather than only ever the light attack path.
	var move_id := "light_attack"
	if int(actor["position"]) in Moves.get_move("heavy_attack")["allowed_positions"]:
		move_id = "heavy_attack"

	var targets := _enemy_targets(state, player)
	if targets.is_empty():
		return {}
	var target: Dictionary = targets[_rng.randi_range(0, targets.size() - 1)]
	return {
		"actor_id": str(actor["id"]),
		"move_id": move_id,
		"target_id": str(target["id"]),
	}


## The claim this policy makes for a given true roll.
##
## Capped at the roll from below by the rules and at 20 from above by the die, so
## a max-padding bot on a natural 20 claims 20 honestly without special-casing.
func choose_claim(state: Dictionary, player: int, true_roll: int) -> int:
	var cap := _claim_cap(state, player)
	match policy:
		POLICY_MAX_PAD:
			return mini(cap, 20)
		_:
			return mini(cap, true_roll) if cap < true_roll else true_roll


## Whether to challenge the opponent's claim.
##
## The honest bot never challenges, so it never takes a wrong-call cost; the
## padding bot challenges every claim, which is the behaviour the exposure rule
## exists to punish. Between them they cover both sides of that rule.
func choose_challenge(_state: Dictionary, _player: int, _opponent_claim: int) -> bool:
	return policy == POLICY_MAX_PAD


## The Scribe's Audit can cap a character's next claim below 20. A bot that
## ignored it would submit an illegal claim and stall the match, so the cap is
## read here rather than left to the caller.
func _claim_cap(state: Dictionary, player: int) -> int:
	var action: Dictionary = state["exchange"]["action"]
	if action.is_empty():
		return 20
	var attacker_player := int(action["player"])
	var character_id := str(action["actor_id"]) if player == attacker_player else str(action["target_id"])
	for character in state["teams"][player]["characters"]:
		if str(character["id"]) == character_id:
			return int(character["effect_counters"].get("audit_claim_cap", 20))
	return 20


func _available_actors(state: Dictionary, player: int) -> Array:
	var actors: Array = []
	for character in state["teams"][player]["characters"]:
		if character["is_alive"] and str(character["id"]) not in state["teams"][player]["used_character_ids"]:
			actors.append(character)
	return actors


func _enemy_targets(state: Dictionary, player: int) -> Array:
	var targets: Array = []
	for character in state["teams"][1 - player]["characters"]:
		if character["is_alive"]:
			targets.append(character)
	return targets
