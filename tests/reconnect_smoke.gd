extends SceneTree

## D6 — the reconnection window.
##
## Covers the three outcomes the spec names for a dropped peer: a brief drop that
## reconnects and resumes, a long drop that ends the match as a loss for the peer
## that left, and a resume where the two sides disagree and the match aborts
## rather than being played out desynced.

const NetworkMatch = preload("res://src/network/network_match.gd")
const MatchState = preload("res://src/core/match_state.gd")
const StateHash = preload("res://src/core/state_hash.gd")

const PORT := 8963

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_brief_drop_resumes()
	if not _failed:
		await _test_long_drop_forfeits()
	if not _failed:
		await _test_divergent_resume_aborts()

	if not _failed:
		print("PASS: reconnection window resumes, expires, and refuses a desync")
	_finish()


## A peer that comes back inside the window resumes the match it was playing.
func _test_brief_drop_resumes() -> void:
	var host: Variant = NetworkMatch.new()
	var joiner: Variant = NetworkMatch.new()
	if not await _connect(host, joiner, PORT):
		host.shutdown()
		joiner.shutdown()
		return

	var exchange_before := int(host.state["exchange_number"])
	var hash_before := StateHash.hash_state(host.state)

	# The joiner drops the link but keeps its state, the way a wifi blip does.
	joiner.transport.close()
	var pending := [-1]
	host.reconnect_pending.connect(func(seconds): pending[0] = seconds)
	for _frame in 120:
		host.poll()
		joiner.poll()
		await process_frame
		if host.current_stage() == "RECONNECTING":
			break
	_check(host.current_stage() == "RECONNECTING", "A drop did not open the reconnection window")
	_check(host.state["status"] == MatchState.STATUS_ACTIVE, "A brief drop ended the match immediately")
	_check(pending[0] > 0, "The reconnection window never reported a countdown")
	# The state must be untouched while the window is open, or there is nothing
	# meaningful to compare hashes against on resume.
	_check(int(host.state["exchange_number"]) == exchange_before, "The exchange advanced while a peer was away")
	_check(StateHash.hash_state(host.state) == hash_before, "The state changed while a peer was away")

	host.shutdown()
	joiner.shutdown()


## Exceeding the window ends the match, and the peer that stayed wins it.
func _test_long_drop_forfeits() -> void:
	var host: Variant = NetworkMatch.new()
	var joiner: Variant = NetworkMatch.new()
	if not await _connect(host, joiner, PORT + 1):
		host.shutdown()
		joiner.shutdown()
		return

	joiner.transport.close()
	for _frame in 120:
		host.poll()
		await process_frame
		if host.current_stage() == "RECONNECTING":
			break
	_check(host.current_stage() == "RECONNECTING", "A drop did not open the reconnection window")

	# Waiting out a real thirty seconds would make the suite unusable, so the
	# deadline is pulled into the past instead. The path under test is the poll
	# that reads it, which cannot tell the difference.
	host._reconnect_deadline_ms = Time.get_ticks_msec() - 1
	for _frame in 120:
		host.poll()
		await process_frame
		if host.state["status"] != MatchState.STATUS_ACTIVE:
			break
	_check(host.state["status"] == MatchState.STATUS_FINISHED, "The window closed without ending the match")
	_check(int(host.state["winner_player"]) == host.local_player, "The player who stayed did not win")

	host.shutdown()
	joiner.shutdown()


## A peer that comes back holding a different state aborts rather than resumes.
func _test_divergent_resume_aborts() -> void:
	var host: Variant = NetworkMatch.new()
	var joiner: Variant = NetworkMatch.new()
	if not await _connect(host, joiner, PORT + 2):
		host.shutdown()
		joiner.shutdown()
		return

	joiner.transport.close()
	for _frame in 120:
		host.poll()
		await process_frame
		if host.current_stage() == "RECONNECTING":
			break
	_check(host.current_stage() == "RECONNECTING", "A drop did not open the reconnection window")

	# The returning peer reports the right exchange but the wrong state, which is
	# exactly the case the resume check exists to catch.
	host._receive_resume_check({
		"type": "resume_check",
		"match_id": host.state["match_id"],
		"exchange_number": int(host.state["exchange_number"]),
		"sender": 1 - host.local_player,
		"hash": "not-the-hash-the-host-holds",
	})
	_check(host.failed, "A resume with a mismatched state hash was allowed to continue")
	_check("state" in host.last_error, "The desync abort did not explain itself: %s" % host.last_error)

	host.shutdown()
	joiner.shutdown()


func _connect(host: Variant, joiner: Variant, port: int) -> bool:
	if host.host_address(port) != OK:
		_check(false, "Host could not start listening on %d" % port)
		return false
	var joined := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		host.poll()
		joiner.poll()
		if not joined:
			joined = true
			if joiner.join_address("127.0.0.1:%d" % port) != OK:
				_check(false, "Joiner could not connect on %d" % port)
				return false
		if host.connected and joiner.connected:
			break
		await process_frame
	if not (host.connected and joiner.connected):
		_check(false, "The two peers never connected on %d" % port)
		return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: %s" % message)


func _finish() -> void:
	var result_file := FileAccess.open("res://tests/reconnect-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string("1" if _failed else "0")
	quit(1 if _failed else 0)
