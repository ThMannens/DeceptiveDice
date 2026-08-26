extends RefCounted

const CommitReveal = preload("res://src/protocol/commit_reveal.gd")

signal outbound_message(message: Dictionary)
signal roll_ready(roll: int)
signal commits_ready(commits: Array)
signal claims_ready(claims: Array)
signal challenges_ready(challenges: Array)
signal reveals_ready(true_rolls: Array, reveals: Array)
signal protocol_failed(message: String)

const KIND_COMMIT := "commit"
const KIND_CLAIM_COMMIT := "claim_commit"
const KIND_CLAIM_REVEAL := "claim_reveal"
const KIND_CHALLENGE_COMMIT := "challenge_commit"
const KIND_CHALLENGE_REVEAL := "challenge_reveal"
const KIND_ROLL_REVEAL := "roll_reveal"

var match_id := ""
var exchange_number := 0
var local_player := -1
var remote_player := -1
var local_roll := 0
var failed := false

var commits := [null, null]
var claim_commits := ["", ""]
var claim_reveals := [null, null]
var challenge_commits := ["", ""]
var challenge_reveals := [null, null]
var roll_reveals := [null, null]

var _roller_secret := ""
var _observer_secret := ""
var _claim_nonce := ""
var _challenge_nonce := ""
var _local_claim := -1
var _local_challenge := false
var _claim_submitted := false
var _challenge_submitted := false
var _commits_emitted := false
var _claims_emitted := false
var _challenges_emitted := false
var _reveals_emitted := false


func begin(new_match_id: String, new_exchange_number: int, player: int) -> void:
	match_id = new_match_id
	exchange_number = new_exchange_number
	local_player = player
	remote_player = 1 - player
	_roller_secret = CommitReveal.generate_secret()
	_observer_secret = CommitReveal.generate_secret()
	var packet := {
		"roll_commit": CommitReveal.secret_commit(_roller_secret),
		"observer_secret": _observer_secret,
	}
	commits[local_player] = packet
	_send(KIND_COMMIT, "COMMIT", packet)


func submit_claim(value: int) -> String:
	if failed:
		return "The exchange protocol has failed"
	if local_roll == 0:
		return "The private roll is not ready"
	if _claim_submitted:
		return "A claim was already submitted"
	if value < local_roll or value > 20:
		return "Claim must be between the private roll and 20"
	_claim_submitted = true
	_local_claim = value
	_claim_nonce = CommitReveal.generate_secret()
	claim_commits[local_player] = CommitReveal.decision_commit("claim", _claim_nonce, value)
	_send(KIND_CLAIM_COMMIT, "CLAIM", {"commit": claim_commits[local_player]})
	_maybe_reveal_claim()
	return ""


func submit_challenge(challenge: bool) -> String:
	if failed:
		return "The exchange protocol has failed"
	if not _claims_emitted:
		return "Claims are not ready"
	if _challenge_submitted:
		return "A challenge choice was already submitted"
	_challenge_submitted = true
	_local_challenge = challenge
	_challenge_nonce = CommitReveal.generate_secret()
	challenge_commits[local_player] = CommitReveal.decision_commit("challenge", _challenge_nonce, challenge)
	_send(KIND_CHALLENGE_COMMIT, "CHALLENGE", {"commit": challenge_commits[local_player]})
	_maybe_reveal_challenge()
	return ""


func receive(message: Dictionary) -> void:
	if failed:
		return
	var envelope_error := _validate_envelope(message)
	if not envelope_error.is_empty():
		_fail(envelope_error)
		return
	var kind := str(message["kind"])
	var payload: Dictionary = message["payload"]
	match kind:
		KIND_COMMIT:
			_receive_commit(payload)
		KIND_CLAIM_COMMIT:
			_receive_claim_commit(payload)
		KIND_CLAIM_REVEAL:
			_receive_claim_reveal(payload)
		KIND_CHALLENGE_COMMIT:
			_receive_challenge_commit(payload)
		KIND_CHALLENGE_REVEAL:
			_receive_challenge_reveal(payload)
		KIND_ROLL_REVEAL:
			_receive_roll_reveal(payload)
		_:
			_fail("Unknown exchange protocol message '%s'" % kind)


func _receive_commit(payload: Dictionary) -> void:
	if commits[remote_player] != null:
		_fail("Duplicate commit message")
		return
	if not payload.has("roll_commit") or not payload.has("observer_secret"):
		_fail("Malformed commit message")
		return
	commits[remote_player] = payload.duplicate(true)
	local_roll = CommitReveal.derive_roll(_roller_secret, str(payload["observer_secret"]))
	if not _commits_emitted:
		_commits_emitted = true
		commits_ready.emit(commits.duplicate(true))
		roll_ready.emit(local_roll)


func _receive_claim_commit(payload: Dictionary) -> void:
	if not _commits_emitted:
		_fail("Claim commit arrived before both roll commits")
		return
	if not claim_commits[remote_player].is_empty():
		_fail("Duplicate claim commit")
		return
	claim_commits[remote_player] = str(payload.get("commit", ""))
	if claim_commits[remote_player].is_empty():
		_fail("Malformed claim commit")
		return
	_maybe_reveal_claim()


func _maybe_reveal_claim() -> void:
	if not _claim_submitted or claim_commits[remote_player].is_empty() or claim_reveals[local_player] != null:
		return
	var reveal := {"value": _local_claim, "nonce": _claim_nonce}
	claim_reveals[local_player] = reveal
	_send(KIND_CLAIM_REVEAL, "CLAIM", reveal)
	_maybe_emit_claims()


func _receive_claim_reveal(payload: Dictionary) -> void:
	if claim_commits[remote_player].is_empty() or claim_commits[local_player].is_empty():
		_fail("Claim reveal arrived before both claim commits")
		return
	if claim_reveals[remote_player] != null:
		_fail("Duplicate claim reveal")
		return
	var value := int(payload.get("value", 0))
	var nonce := str(payload.get("nonce", ""))
	if value < 1 or value > 20 or not CommitReveal.verify_decision("claim", nonce, value, claim_commits[remote_player]):
		_fail("Claim reveal did not match its commitment")
		return
	claim_reveals[remote_player] = {"value": value, "nonce": nonce}
	_maybe_emit_claims()


func _maybe_emit_claims() -> void:
	if _claims_emitted or claim_reveals[0] == null or claim_reveals[1] == null:
		return
	_claims_emitted = true
	claims_ready.emit([int(claim_reveals[0]["value"]), int(claim_reveals[1]["value"])])


func _receive_challenge_commit(payload: Dictionary) -> void:
	if not _claims_emitted:
		_fail("Challenge commit arrived before claims were revealed")
		return
	if not challenge_commits[remote_player].is_empty():
		_fail("Duplicate challenge commit")
		return
	challenge_commits[remote_player] = str(payload.get("commit", ""))
	if challenge_commits[remote_player].is_empty():
		_fail("Malformed challenge commit")
		return
	_maybe_reveal_challenge()


func _maybe_reveal_challenge() -> void:
	if not _challenge_submitted or challenge_commits[remote_player].is_empty() or challenge_reveals[local_player] != null:
		return
	var reveal := {"value": _local_challenge, "nonce": _challenge_nonce}
	challenge_reveals[local_player] = reveal
	_send(KIND_CHALLENGE_REVEAL, "CHALLENGE", reveal)
	_maybe_emit_challenges()


func _receive_challenge_reveal(payload: Dictionary) -> void:
	if challenge_commits[remote_player].is_empty() or challenge_commits[local_player].is_empty():
		_fail("Challenge reveal arrived before both challenge commits")
		return
	if challenge_reveals[remote_player] != null:
		_fail("Duplicate challenge reveal")
		return
	var value = payload.get("value")
	var nonce := str(payload.get("nonce", ""))
	if typeof(value) != TYPE_BOOL or not CommitReveal.verify_decision("challenge", nonce, value, challenge_commits[remote_player]):
		_fail("Challenge reveal did not match its commitment")
		return
	challenge_reveals[remote_player] = {"value": value, "nonce": nonce}
	_maybe_emit_challenges()


func _maybe_emit_challenges() -> void:
	if _challenges_emitted or challenge_reveals[0] == null or challenge_reveals[1] == null:
		return
	_challenges_emitted = true
	challenges_ready.emit([bool(challenge_reveals[0]["value"]), bool(challenge_reveals[1]["value"])])
	var reveal := {"secret": _roller_secret}
	roll_reveals[local_player] = reveal
	_send(KIND_ROLL_REVEAL, "REVEAL", reveal)
	_maybe_emit_reveals()


func _receive_roll_reveal(payload: Dictionary) -> void:
	if not _challenges_emitted:
		_fail("Roll reveal arrived before challenges were revealed")
		return
	if roll_reveals[remote_player] != null:
		_fail("Duplicate roll reveal")
		return
	var secret := str(payload.get("secret", ""))
	if not CommitReveal.verify_secret(secret, str(commits[remote_player]["roll_commit"])):
		_fail("Roll reveal did not match its commitment")
		return
	var remote_roll := CommitReveal.derive_roll(secret, _observer_secret)
	if int(claim_reveals[remote_player]["value"]) < remote_roll:
		_fail("Remote claim was below its true roll")
		return
	roll_reveals[remote_player] = {"secret": secret, "roll": remote_roll}
	_maybe_emit_reveals()


func _maybe_emit_reveals() -> void:
	if _reveals_emitted or roll_reveals[0] == null or roll_reveals[1] == null:
		return
	_reveals_emitted = true
	var true_rolls := [0, 0]
	true_rolls[local_player] = local_roll
	true_rolls[remote_player] = int(roll_reveals[remote_player]["roll"])
	reveals_ready.emit(true_rolls, roll_reveals.duplicate(true))


func _send(kind: String, phase: String, payload: Dictionary) -> void:
	outbound_message.emit({
		"type": "exchange",
		"match_id": match_id,
		"exchange_number": exchange_number,
		"phase": phase,
		"sender": local_player,
		"kind": kind,
		"payload": payload.duplicate(true),
	})


func _validate_envelope(message: Dictionary) -> String:
	for field in ["type", "match_id", "exchange_number", "phase", "sender", "kind", "payload"]:
		if not message.has(field):
			return "Exchange message is missing '%s'" % field
	if message["type"] != "exchange":
		return "Unexpected protocol message type"
	if str(message["match_id"]) != match_id or int(message["exchange_number"]) != exchange_number:
		return "Exchange message targets the wrong match or exchange"
	if int(message["sender"]) != remote_player:
		return "Exchange message has the wrong sender"
	if typeof(message["payload"]) != TYPE_DICTIONARY:
		return "Exchange message payload must be a dictionary"
	return ""


func _fail(message: String) -> void:
	failed = true
	protocol_failed.emit(message)
