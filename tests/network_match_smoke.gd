extends SceneTree

const NetworkMatch = preload("res://src/network/network_match.gd")
const StateHash = preload("res://src/core/state_hash.gd")

var host: Variant = NetworkMatch.new()
var joiner: Variant = NetworkMatch.new()
var started_at := 0
var action_submitted := false
var claims_submitted := [false, false]
var challenges_submitted := [false, false]
var failed := false
var failure_message := ""
var finishing := false


func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	host.connection_code_ready.connect(func(code, kind):
		if kind == "offer" and joiner.join_direct(code) != OK:
			_fail("Joiner could not accept the direct offer")
	)
	joiner.connection_code_ready.connect(func(code, kind):
		if kind == "answer" and host.accept_direct_answer(code) != OK:
			_fail("Host could not accept the direct answer")
	)
	host.match_failed.connect(func(message): _fail("Host: %s" % message))
	joiner.match_failed.connect(func(message): _fail("Joiner: %s" % message))
	if host.host_direct() != OK:
		_fail("Host could not create a direct offer")


func _process(_delta: float) -> bool:
	if finishing:
		return false
	host.poll()
	joiner.poll()
	if failed:
		_finish()
		return false
	if host.connected and joiner.connected:
		_drive_match()
	if _both_resolved():
		_check(StateHash.hash_state(host.state) == StateHash.hash_state(joiner.state), "Peers ended with different states")
		_check(int(host.state["last_resolution"].get("exchange_number", 0)) == 1, "The online attack did not resolve exchange 1")
		_check(host.state["last_resolution"].has("attack"), "The online resolution has no combat result")
		if not failed:
			print("PASS: manual connection codes, WebRTC, and online match smoke test")
		_finish()
	elif Time.get_ticks_msec() - started_at > 20000:
		_fail("Online peers did not finish one attack within 20 seconds")
		_finish()
	return false


func _drive_match() -> void:
	if not action_submitted:
		var active: RefCounted = host if int(host.state["active_player"]) == 0 else joiner
		if active.current_stage() == "SELECT":
			var player: int = active.local_player
			var actors: Array = active.available_actors(player)
			var targets: Array = active.valid_targets(player, str(actors[0]["id"]), "light_attack")
			var result: Dictionary = active.select_action(str(actors[0]["id"]), "light_attack", str(targets[0]["id"]))
			_check(result["ok"], "Active peer could not submit an attack")
			action_submitted = result["ok"]
	for peer_index in [0, 1]:
		var peer: RefCounted = host if peer_index == 0 else joiner
		if peer.current_stage() == "CLAIM" and not claims_submitted[peer_index]:
			var result: Dictionary = peer.submit_claim(peer.local_player, int(peer.true_rolls[peer.local_player]))
			_check(result["ok"], "Peer %d could not submit a claim" % peer_index)
			claims_submitted[peer_index] = result["ok"]
		if peer.current_stage() == "CHALLENGE" and not challenges_submitted[peer_index]:
			var result: Dictionary = peer.submit_challenge(peer.local_player, false)
			_check(result["ok"], "Peer %d could not submit a challenge" % peer_index)
			challenges_submitted[peer_index] = result["ok"]


func _both_resolved() -> bool:
	return (
		not host.state.is_empty()
		and not joiner.state.is_empty()
		and not host.state["last_resolution"].is_empty()
		and not joiner.state["last_resolution"].is_empty()
		and host.current_stage() == "RESOLUTION"
		and joiner.current_stage() == "RESOLUTION"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	if not failed:
		failed = true
		failure_message = message
		printerr("FAIL: %s" % message)


func _finish() -> void:
	if finishing:
		return
	finishing = true
	host.shutdown()
	joiner.shutdown()
	host = null
	joiner = null
	for _frame in 5:
		await process_frame
	var result_file := FileAccess.open("res://tests/network-match-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string("1" if failed else "0")
	quit(1 if failed else 0)
