extends SceneTree

## Drives two NetworkMatch peers over the address-based transport on loopback,
## with no signalling codes, and plays one full attack exchange.

const NetworkMatch = preload("res://src/network/network_match.gd")
const StateHash = preload("res://src/core/state_hash.gd")

const PORT := 8941

var host: Variant = NetworkMatch.new()
var joiner: Variant = NetworkMatch.new()
var started_at := 0
var join_attempted := false
var action_submitted := false
var claims_submitted := [false, false]
var challenges_submitted := [false, false]
var failed := false
var finishing := false


func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	host.match_failed.connect(func(message): _fail("Host: %s" % message))
	joiner.match_failed.connect(func(message): _fail("Joiner: %s" % message))
	if host.host_address(PORT) != OK:
		_fail("Host could not start listening")


func _process(_delta: float) -> bool:
	if finishing:
		return false
	host.poll()
	joiner.poll()

	# The joiner dials in once the host is listening.
	if not join_attempted and not failed:
		join_attempted = true
		if joiner.join_address("127.0.0.1:%d" % PORT) != OK:
			_fail("Joiner could not connect to the host")

	if failed:
		_finish()
		return false
	if host.connected and joiner.connected and not host.state.is_empty() and not joiner.state.is_empty():
		_drive_match()
	if _both_resolved():
		_check(StateHash.hash_state(host.state) == StateHash.hash_state(joiner.state), "Peers ended with different states")
		_check(int(host.state["last_resolution"].get("exchange_number", 0)) == 1, "The direct attack did not resolve exchange 1")
		_check(host.state["last_resolution"].has("attack"), "The direct resolution has no combat result")
		if not failed:
			print("PASS: direct address connection and online match smoke test")
		_finish()
	elif Time.get_ticks_msec() - started_at > 20000:
		_fail("Direct peers did not finish one attack within 20 seconds")
		_finish()
	return false


func _drive_match() -> void:
	if not action_submitted:
		var active: RefCounted = host if int(host.state["active_player"]) == host.local_player else joiner
		if active.current_stage() == "SELECT":
			var player: int = active.local_player
			var actor: Dictionary = active.available_actors(player)[0]
			var target: Dictionary = active.valid_targets(player, str(actor["id"]), "light_attack")[0]
			var result: Dictionary = active.select_action(str(actor["id"]), "light_attack", str(target["id"]))
			if result["ok"]:
				action_submitted = true
			return
		return

	for index in 2:
		var peer: RefCounted = host if index == 0 else joiner
		if not claims_submitted[index] and peer.current_stage() == "CLAIM":
			var roll: int = int(peer.true_rolls[peer.local_player])
			if peer.submit_claim(peer.local_player, roll)["ok"]:
				claims_submitted[index] = true
		if not challenges_submitted[index] and peer.current_stage() == "CHALLENGE":
			if peer.submit_challenge(peer.local_player, false)["ok"]:
				challenges_submitted[index] = true


func _both_resolved() -> bool:
	return (
		not host.state.is_empty()
		and not joiner.state.is_empty()
		and not host.state.get("last_resolution", {}).is_empty()
		and not joiner.state.get("last_resolution", {}).is_empty()
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("FAIL: %s" % message)


func _fail(message: String) -> void:
	if not failed:
		failed = true
		printerr("FAIL: %s" % message)


func _finish() -> void:
	if finishing:
		return
	finishing = true
	host.shutdown()
	joiner.shutdown()
	var result_file := FileAccess.open("res://tests/direct-match-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(str(1 if failed else 0))
	quit(1 if failed else 0)
