extends RefCounted

const MatchState = preload("res://src/core/match_state.gd")

const DRAFT_SUBMITTED := "draft_submitted"
const FORMATION_SUBMITTED := "formation_submitted"
const ACTION_SELECTED := "action_selected"
const COMMIT_SUBMITTED := "commit_submitted"
const CLAIM_SUBMITTED := "claim_submitted"
const CHALLENGE_SUBMITTED := "challenge_submitted"
const REVEAL_SUBMITTED := "reveal_submitted"
const PHASE_TIMEOUT := "phase_timeout"
const EXCHANGE_RESOLVED := "exchange_resolved"
const PLAYER_FORFEITED := "player_forfeited"

const VALID_TYPES := [
	DRAFT_SUBMITTED,
	FORMATION_SUBMITTED,
	ACTION_SELECTED,
	COMMIT_SUBMITTED,
	CLAIM_SUBMITTED,
	CHALLENGE_SUBMITTED,
	REVEAL_SUBMITTED,
	PHASE_TIMEOUT,
	EXCHANGE_RESOLVED,
	PLAYER_FORFEITED,
]

const REQUIRED_PAYLOAD_FIELDS := {
	DRAFT_SUBMITTED: ["character_ids"],
	FORMATION_SUBMITTED: ["character_ids"],
	ACTION_SELECTED: ["actor_id", "move_id", "target_id"],
	COMMIT_SUBMITTED: ["roll_commit", "observer_secret"],
	CLAIM_SUBMITTED: ["value"],
	CHALLENGE_SUBMITTED: ["challenge"],
	REVEAL_SUBMITTED: ["secret"],
	PHASE_TIMEOUT: ["timed_out_sender"],
	EXCHANGE_RESOLVED: [],
	PLAYER_FORFEITED: [],
}


static func create(
	event_type: String,
	match_id: String,
	exchange_number: int,
	phase: String,
	sender: int,
	payload: Dictionary = {},
) -> Dictionary:
	return {
		"type": event_type,
		"match_id": match_id,
		"exchange_number": exchange_number,
		"phase": phase,
		"sender": sender,
		"payload": payload,
	}


static func validate(event: Dictionary) -> String:
	for field in ["type", "match_id", "exchange_number", "phase", "sender", "payload"]:
		if not event.has(field):
			return "Event is missing required field '%s'" % field

	var event_type := str(event["type"])
	if event_type not in VALID_TYPES:
		return "Unknown event type '%s'" % event_type
	if str(event["match_id"]).is_empty():
		return "Event match_id must not be empty"
	if str(event["phase"]) not in MatchState.VALID_PHASES:
		return "Unknown event phase '%s'" % str(event["phase"])
	if typeof(event["payload"]) != TYPE_DICTIONARY:
		return "Event payload must be a dictionary"

	var sender := int(event["sender"])
	if event_type in [PHASE_TIMEOUT, EXCHANGE_RESOLVED]:
		if sender != -1:
			return "System event '%s' must use sender -1" % event_type
	elif sender not in [0, 1]:
		return "Player event '%s' must use sender 0 or 1" % event_type

	var payload: Dictionary = event["payload"]
	for field in REQUIRED_PAYLOAD_FIELDS[event_type]:
		if not payload.has(field):
			return "Event '%s' payload is missing '%s'" % [event_type, field]
	return ""
