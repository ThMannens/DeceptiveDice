extends RefCounted

const ExchangeProtocol = preload("res://src/protocol/exchange_protocol.gd")
const ManualSignalCode = preload("res://src/network/manual_signal_code.gd")
const MatchEvent = preload("res://src/core/match_event.gd")
const MatchReducer = preload("res://src/core/match_reducer.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Moves = preload("res://src/core/moves.gd")
const StateHash = preload("res://src/core/state_hash.gd")
const DirectTransport = preload("res://src/network/direct_transport.gd")
const WebRTCTransport = preload("res://src/network/webrtc_transport.gd")

const PLAYER_NAMES := ["Player 1", "Player 2"]
const DEFAULT_ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
]

signal connection_code_ready(code: String, kind: String)
signal status_changed(message: String)
signal state_changed()
signal stage_changed(stage: String)
signal resolution_ready()
signal match_failed(message: String)

var state: Dictionary = {}
var true_rolls := [0, 0]
var last_error := ""
var local_player := -1
var manual_code := ""
var connected := false
var failed := false

var transport: RefCounted
var exchange_protocol: RefCounted

var _local_hashes: Dictionary = {}
var _remote_hashes: Dictionary = {}
var _current_stage := "LOBBY"
var _match_id := ""
var _manual_mode := false
var _manual_kind := ""
var _manual_description: Dictionary = {}
var _manual_candidates: Array = []
var _manual_code_emitted := false
## Set when the match runs over the plain address-based transport rather than
## the WebRTC signalling-code path.
var _address_mode := false


## Listens for an opponent on this machine. The hosting player shares the
## address shown by DirectTransport.local_addresses() instead of a signal code.
func host_address(port: int = DirectTransport.DEFAULT_PORT) -> Error:
	_reset()
	local_player = 0
	_address_mode = true
	_match_id = "lan-%s" % Crypto.new().generate_random_bytes(16).hex_encode()
	_create_address_transport()
	var error: Error = transport.host(port)
	if error != OK:
		return error
	status_changed.emit("Waiting for the other player to connect")
	_set_stage("DIRECT_HOST_WAITING")
	return OK


## Connects to a hosting player at "address" or "address:port".
func join_address(address_text: String) -> Error:
	var parsed := parse_address(address_text)
	if not parsed["ok"]:
		last_error = str(parsed["error"])
		return ERR_INVALID_DATA
	_reset()
	local_player = 1
	_address_mode = true
	# The host owns the match id and sends it once the link is up.
	_match_id = ""
	_create_address_transport()
	var error: Error = transport.join(str(parsed["host"]), int(parsed["port"]))
	if error != OK:
		return error
	status_changed.emit("Connecting to %s" % address_text.strip_edges())
	_set_stage("DIRECT_CONNECTING")
	return OK


## Splits "host", "host:port", or an IPv6 literal into its parts.
static func parse_address(address_text: String) -> Dictionary:
	var text := address_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "Enter the address the host gave you"}
	var host := text
	var port := DirectTransport.DEFAULT_PORT
	# Only treat a colon as a port separator when it is the last one, so IPv6
	# literals without a port are still accepted.
	var separator := text.rfind(":")
	if separator > 0 and text.count(":") == 1:
		host = text.substr(0, separator)
		var port_text := text.substr(separator + 1)
		if not port_text.is_valid_int():
			return {"ok": false, "error": "The port must be a number"}
		port = int(port_text)
		if port < 1 or port > 65535:
			return {"ok": false, "error": "The port must be between 1 and 65535"}
	if host.is_empty():
		return {"ok": false, "error": "Enter the address the host gave you"}
	return {"ok": true, "host": host, "port": port}


func _create_address_transport() -> void:
	transport = DirectTransport.new()
	transport.connected.connect(_on_transport_connected)
	transport.message_received.connect(_on_transport_message)
	transport.disconnected.connect(_on_transport_disconnected)
	transport.transport_failed.connect(_fail)


func host_direct() -> Error:
	_reset()
	local_player = 0
	_manual_mode = true
	_manual_kind = "offer"
	_match_id = "direct-%s" % Crypto.new().generate_random_bytes(16).hex_encode()
	status_changed.emit("Creating a direct connection offer")
	_set_stage("DIRECT_HOST_PREPARING")
	var error := _create_direct_transport(true)
	if error != OK:
		return error
	return transport.start_offer()


func join_direct(offer_code: String) -> Error:
	var decoded := ManualSignalCode.decode(offer_code, "offer")
	if not decoded["ok"]:
		last_error = str(decoded["error"])
		return ERR_INVALID_DATA
	_reset()
	local_player = 1
	_manual_mode = true
	_manual_kind = "answer"
	_match_id = str(decoded["payload"]["match_id"])
	status_changed.emit("Creating a direct connection answer")
	_set_stage("DIRECT_JOIN_PREPARING")
	var error := _create_direct_transport(false)
	if error != OK:
		return error
	_apply_manual_bundle(decoded["payload"])
	return OK


func accept_direct_answer(answer_code: String) -> Error:
	if not _manual_mode or local_player != 0 or transport == null:
		return ERR_UNCONFIGURED
	var decoded := ManualSignalCode.decode(answer_code, "answer")
	if not decoded["ok"]:
		last_error = str(decoded["error"])
		return ERR_INVALID_DATA
	if str(decoded["payload"]["match_id"]) != _match_id:
		last_error = "This answer belongs to a different connection offer"
		return ERR_INVALID_DATA
	status_changed.emit("Connecting directly to the other player")
	_set_stage("DIRECT_CONNECTING")
	_apply_manual_bundle(decoded["payload"])
	return OK


func poll() -> void:
	if transport != null:
		transport.poll()
		if _manual_mode and not _address_mode:
			_poll_manual_code()


func shutdown() -> void:
	if transport != null:
		transport.close()
	connected = false
	exchange_protocol = null
	transport = null


func select_action(actor_id: String, move_id: String, target_id: String) -> Dictionary:
	if not connected:
		return _local_error("The peer connection is not ready")
	if state.get("phase") != MatchState.PHASE_SELECT:
		return _local_error("The match is not waiting for an action")
	if int(state.get("active_player", -1)) != local_player:
		return _local_error("Wait for the other player to act")
	var payload := {
		"actor_id": actor_id,
		"move_id": move_id,
		"target_id": target_id,
	}
	var result := _preview_event(MatchEvent.ACTION_SELECTED, local_player, payload)
	if not result["ok"]:
		return _remember_result(result)
	var send_error: Error = transport.send_message({
		"type": "action",
		"match_id": state["match_id"],
		"exchange_number": state["exchange_number"],
		"sender": local_player,
		"payload": payload,
	})
	if send_error != OK:
		return _local_error("Could not send the action to the peer")
	_accept_result(result)
	_after_action_selected()
	return result


func submit_claim(player: int, value: int) -> Dictionary:
	if player != local_player:
		return _local_error("Only the local player can submit this claim")
	if exchange_protocol == null:
		return _local_error("The dice exchange is not ready")
	var error: String = exchange_protocol.submit_claim(value)
	if not error.is_empty():
		return _local_error(error)
	last_error = ""
	_set_stage("WAIT_CLAIM")
	return _success_result()


func submit_challenge(player: int, challenge: bool) -> Dictionary:
	if player != local_player:
		return _local_error("Only the local player can submit this challenge")
	if exchange_protocol == null:
		return _local_error("The dice exchange is not ready")
	var error: String = exchange_protocol.submit_challenge(challenge)
	if not error.is_empty():
		return _local_error(error)
	last_error = ""
	_set_stage("WAIT_CHALLENGE")
	return _success_result()


func continue_after_resolution() -> void:
	if state.get("status") == MatchState.STATUS_FINISHED:
		_set_stage("FINISHED")
	elif int(state.get("active_player", -1)) == local_player:
		_set_stage("SELECT")
	else:
		_set_stage("WAIT_ACTION")


func available_actors(player: int) -> Array:
	var available: Array = []
	if state.is_empty():
		return available
	for character in state["teams"][player]["characters"]:
		if character["is_alive"] and character["id"] not in state["teams"][player]["used_character_ids"]:
			available.append(character)
	return available


func valid_targets(player: int, actor_id: String, move_id: String) -> Array:
	var targets: Array = []
	if state.is_empty() or not Moves.has_move(move_id):
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
	if state.is_empty():
		return {}
	for character in state["teams"][player]["characters"]:
		if character["id"] == character_id:
			return character
	return {}


func current_stage() -> String:
	return _current_stage


func _reset() -> void:
	shutdown()
	state = {}
	true_rolls = [0, 0]
	last_error = ""
	connected = false
	failed = false
	exchange_protocol = null
	transport = null
	_local_hashes.clear()
	_remote_hashes.clear()
	_current_stage = "LOBBY"
	_match_id = ""
	manual_code = ""
	_manual_mode = false
	_manual_kind = ""
	_manual_description = {}
	_manual_candidates.clear()
	_manual_code_emitted = false
	_address_mode = false


func _create_direct_transport(host_peer: bool) -> Error:
	transport = WebRTCTransport.new()
	transport.local_signal_created.connect(_collect_manual_signal)
	transport.connected.connect(_on_transport_connected)
	transport.message_received.connect(_on_transport_message)
	transport.disconnected.connect(_on_transport_disconnected)
	transport.transport_failed.connect(_fail)
	var error: Error = transport.initialize(host_peer, DEFAULT_ICE_SERVERS)
	if error != OK:
		_fail("Could not initialize WebRTC")
	return error


func _collect_manual_signal(payload: Dictionary) -> void:
	match str(payload.get("kind", "")):
		"sdp":
			_manual_description = payload.duplicate(true)
		"ice":
			_manual_candidates.append({
				"media": str(payload.get("media", "")),
				"index": int(payload.get("index", 0)),
				"name": str(payload.get("name", "")),
			})


func _poll_manual_code() -> void:
	if _manual_code_emitted or _manual_kind.is_empty() or _manual_description.is_empty():
		return
	if not transport.is_gathering_complete():
		return
	_manual_code_emitted = true
	manual_code = ManualSignalCode.encode(_manual_kind, _match_id, _manual_description, _manual_candidates)
	if _manual_kind == "offer":
		status_changed.emit("Offer ready. Send it to the other player, then paste their answer")
		_set_stage("DIRECT_HOST_OFFER")
	else:
		status_changed.emit("Answer ready. Send it back to the host")
		_set_stage("DIRECT_JOIN_ANSWER")
	connection_code_ready.emit(manual_code, _manual_kind)


func _apply_manual_bundle(bundle: Dictionary) -> void:
	transport.accept_signal({
		"kind": "sdp",
		"description_type": str(bundle["description_type"]),
		"sdp": str(bundle["sdp"]),
	})
	for candidate in bundle["candidates"]:
		transport.accept_signal({
			"kind": "ice",
			"media": str(candidate["media"]),
			"index": int(candidate["index"]),
			"name": str(candidate["name"]),
		})


func _on_transport_connected() -> void:
	connected = true
	if _address_mode and local_player == 0:
		# The joiner has no match id yet, so the host sends it before play.
		transport.send_message({"type": "MATCH_ID", "match_id": _match_id})
	elif _address_mode and local_player == 1:
		# Wait for the host to name the match before building local state.
		status_changed.emit("Connected. Waiting for the host to start the match")
		return
	_setup_match_state()
	status_changed.emit("Connected to the other player")
	if int(state["active_player"]) == local_player:
		_set_stage("SELECT")
	else:
		_set_stage("WAIT_ACTION")


func _setup_match_state() -> void:
	state = MatchState.create(_match_id, PLAYER_NAMES)
	var setup_events := [
		[MatchEvent.DRAFT_SUBMITTED, 0, {"character_ids": ["ledger", "bruiser", "gambler", "hook"]}],
		[MatchEvent.DRAFT_SUBMITTED, 1, {"character_ids": ["mirror", "bruiser", "gambler", "hook"]}],
		[MatchEvent.FORMATION_SUBMITTED, 0, {"character_ids": ["ledger", "gambler", "hook", "bruiser"]}],
		[MatchEvent.FORMATION_SUBMITTED, 1, {"character_ids": ["bruiser", "hook", "gambler", "mirror"]}],
	]
	for setup_event in setup_events:
		var result := _preview_event(str(setup_event[0]), int(setup_event[1]), setup_event[2])
		if not result["ok"]:
			_fail(str(result["error"]))
			return
		_accept_result(result, false)
	state_changed.emit()


## The joiner on the address transport learns the match id from the host, then
## builds the same starting state the host already has.
func _receive_match_id(message: Dictionary) -> void:
	if not _address_mode or local_player != 1 or not _match_id.is_empty():
		return
	_match_id = str(message.get("match_id", ""))
	if _match_id.is_empty():
		_fail("The host sent an invalid match id")
		return
	_setup_match_state()
	status_changed.emit("Connected to the other player")
	if int(state["active_player"]) == local_player:
		_set_stage("SELECT")
	else:
		_set_stage("WAIT_ACTION")


func _on_transport_message(message: Dictionary) -> void:
	if failed:
		return
	match str(message.get("type", "")):
		"MATCH_ID":
			_receive_match_id(message)
		"action":
			_receive_action(message)
		"exchange":
			if exchange_protocol == null:
				_fail("Received dice data before an attack began")
			else:
				exchange_protocol.receive(message)
		"state_hash":
			_receive_state_hash(message)
		"forfeit":
			_receive_forfeit(message)
		_:
			_fail("Received an unknown gameplay message")


func _receive_action(message: Dictionary) -> void:
	var envelope_error := _validate_gameplay_envelope(message)
	if not envelope_error.is_empty():
		_fail(envelope_error)
		return
	if int(message["sender"]) != 1 - local_player:
		_fail("The action has the wrong sender")
		return
	var payload = message.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		_fail("The action payload is malformed")
		return
	var result := _preview_event(MatchEvent.ACTION_SELECTED, int(message["sender"]), payload)
	if not result["ok"]:
		_fail("The peer sent an invalid action: %s" % result["error"])
		return
	_accept_result(result)
	_after_action_selected()


func _after_action_selected() -> void:
	if state["phase"] == MatchState.PHASE_COMMIT:
		_start_exchange_protocol()
	else:
		var result := _apply_event(MatchEvent.EXCHANGE_RESOLVED, -1, {})
		if not result["ok"]:
			_fail(str(result["error"]))
			return
		_finish_resolution()


func _start_exchange_protocol() -> void:
	true_rolls = [0, 0]
	exchange_protocol = ExchangeProtocol.new()
	exchange_protocol.outbound_message.connect(func(message):
		if transport.send_message(message) != OK:
			_fail("Could not send dice protocol data")
	)
	exchange_protocol.commits_ready.connect(_on_commits_ready)
	exchange_protocol.roll_ready.connect(_on_roll_ready)
	exchange_protocol.claims_ready.connect(_on_claims_ready)
	exchange_protocol.challenges_ready.connect(_on_challenges_ready)
	exchange_protocol.reveals_ready.connect(_on_reveals_ready)
	exchange_protocol.protocol_failed.connect(_fail)
	_set_stage("WAIT_ROLL")
	exchange_protocol.begin(str(state["match_id"]), int(state["exchange_number"]), local_player)


func _on_commits_ready(commits: Array) -> void:
	for player in [0, 1]:
		var result := _apply_event(MatchEvent.COMMIT_SUBMITTED, player, commits[player])
		if not result["ok"]:
			_fail(str(result["error"]))
			return


func _on_roll_ready(roll: int) -> void:
	true_rolls[local_player] = roll
	_set_stage("CLAIM")


func _on_claims_ready(claims: Array) -> void:
	for player in [0, 1]:
		var result := _apply_event(MatchEvent.CLAIM_SUBMITTED, player, {"value": int(claims[player])})
		if not result["ok"]:
			_fail(str(result["error"]))
			return
	_set_stage("CHALLENGE")


func _on_challenges_ready(challenges: Array) -> void:
	for player in [0, 1]:
		var result := _apply_event(MatchEvent.CHALLENGE_SUBMITTED, player, {"challenge": bool(challenges[player])})
		if not result["ok"]:
			_fail(str(result["error"]))
			return
	_set_stage("WAIT_REVEAL")


func _on_reveals_ready(rolls: Array, reveals: Array) -> void:
	for player in [0, 1]:
		var result := _apply_event(MatchEvent.REVEAL_SUBMITTED, player, {"secret": str(reveals[player]["secret"])})
		if not result["ok"]:
			_fail(str(result["error"]))
			return
	true_rolls = rolls.duplicate()
	var resolution := _apply_event(MatchEvent.EXCHANGE_RESOLVED, -1, {"true_rolls": true_rolls.duplicate()})
	if not resolution["ok"]:
		_fail(str(resolution["error"]))
		return
	_finish_resolution()


func _finish_resolution() -> void:
	var resolved_exchange := int(state["last_resolution"]["exchange_number"])
	var digest := StateHash.hash_state(state)
	_local_hashes[resolved_exchange] = digest
	var send_error: Error = transport.send_message({
		"type": "state_hash",
		"match_id": state["match_id"],
		"exchange_number": resolved_exchange,
		"sender": local_player,
		"hash": digest,
	})
	if send_error != OK:
		_fail("Could not send the state check")
		return
	_compare_hashes(resolved_exchange)
	_set_stage("RESOLUTION")
	resolution_ready.emit()


func _receive_state_hash(message: Dictionary) -> void:
	if str(message.get("match_id", "")) != str(state.get("match_id", "")):
		_fail("State check targets the wrong match")
		return
	if int(message.get("sender", -1)) != 1 - local_player:
		_fail("State check has the wrong sender")
		return
	var exchange_number := int(message.get("exchange_number", -1))
	var digest := str(message.get("hash", ""))
	if exchange_number < 1 or digest.length() != 64:
		_fail("State check is malformed")
		return
	_remote_hashes[exchange_number] = digest
	_compare_hashes(exchange_number)


func _compare_hashes(exchange_number: int) -> void:
	if not _local_hashes.has(exchange_number) or not _remote_hashes.has(exchange_number):
		return
	if _local_hashes[exchange_number] != _remote_hashes[exchange_number]:
		state = state.duplicate(true)
		state["status"] = MatchState.STATUS_ABORTED
		state["phase"] = MatchState.PHASE_FINISHED
		state["winner_player"] = -1
		state_changed.emit()
		_fail("The peers calculated different states after exchange %d. The match was stopped." % exchange_number)
	else:
		status_changed.emit("Exchange %d verified" % exchange_number)


func _receive_forfeit(message: Dictionary) -> void:
	var envelope_error := _validate_gameplay_envelope(message)
	if not envelope_error.is_empty():
		_fail(envelope_error)
		return
	if int(message["sender"]) != 1 - local_player:
		_fail("Forfeit has the wrong sender")
		return
	_apply_peer_forfeit(str(message.get("reason", "forfeit")))


func forfeit() -> void:
	if not connected or state.is_empty() or state["status"] != MatchState.STATUS_ACTIVE:
		return
	transport.send_message({
		"type": "forfeit",
		"match_id": state["match_id"],
		"exchange_number": state["exchange_number"],
		"sender": local_player,
		"reason": "player left",
	})
	var result := _apply_event(MatchEvent.PLAYER_FORFEITED, local_player, {"reason": "player left"})
	if result["ok"]:
		_set_stage("FINISHED")
	shutdown()


func _apply_peer_forfeit(reason: String) -> void:
	if state.is_empty() or state["status"] != MatchState.STATUS_ACTIVE:
		return
	var result := _apply_event(MatchEvent.PLAYER_FORFEITED, 1 - local_player, {"reason": reason})
	if result["ok"]:
		last_error = "The other player left the match"
		_set_stage("FINISHED")


func _on_transport_disconnected(_message: String) -> void:
	if connected and not failed:
		connected = false
		_apply_peer_forfeit("peer connection lost")

func _validate_gameplay_envelope(message: Dictionary) -> String:
	for field in ["match_id", "exchange_number", "sender"]:
		if not message.has(field):
			return "Gameplay message is missing '%s'" % field
	if str(message["match_id"]) != str(state.get("match_id", "")):
		return "Gameplay message targets the wrong match"
	if int(message["exchange_number"]) != int(state.get("exchange_number", -1)):
		return "Gameplay message targets the wrong exchange"
	return ""


func _preview_event(event_type: String, sender: int, payload: Dictionary) -> Dictionary:
	var event := MatchEvent.create(
		event_type,
		str(state["match_id"]),
		int(state["exchange_number"]),
		str(state["phase"]),
		sender,
		payload,
	)
	return MatchReducer.apply(state, event)


func _apply_event(event_type: String, sender: int, payload: Dictionary) -> Dictionary:
	var result := _preview_event(event_type, sender, payload)
	return _remember_result(result)


func _remember_result(result: Dictionary) -> Dictionary:
	if result["ok"]:
		_accept_result(result)
	else:
		last_error = str(result["error"])
	return result


func _accept_result(result: Dictionary, announce: bool = true) -> void:
	state = result["state"]
	last_error = ""
	if announce:
		state_changed.emit()


func _success_result() -> Dictionary:
	return {"ok": true, "state": state, "effects": [], "error": ""}


func _local_error(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "state": state, "effects": [], "error": message}


func _set_stage(stage: String) -> void:
	_current_stage = stage
	stage_changed.emit(stage)


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	last_error = message
	status_changed.emit(message)
	_set_stage("FAILED")
	match_failed.emit(message)
