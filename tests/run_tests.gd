extends SceneTree

const MatchReducer = preload("res://src/core/match_reducer.gd")
const MatchState = preload("res://src/core/match_state.gd")
const HotseatMatch = preload("res://src/local/hotseat_match.gd")
const CommitReveal = preload("res://src/protocol/commit_reveal.gd")
const ExchangeProtocol = preload("res://src/protocol/exchange_protocol.gd")
const StateHash = preload("res://src/core/state_hash.gd")
const ManualSignalCode = preload("res://src/network/manual_signal_code.gd")

var _failures := 0
var _tests_run := 0


func _initialize() -> void:
	var transcript_paths := _find_transcripts()
	if transcript_paths.is_empty():
		_fail("No transcript files found")

	for path in transcript_paths:
		_run_transcript(path)
	_run_commit_reveal_properties()
	_run_exchange_protocol()
	_run_protocol_rejection()
	_run_manual_signal_code()
	_run_state_hash()
	_run_hotseat_smoke()
	_run_victory_smoke()

	if _failures == 0:
		print("PASS: %d tests" % _tests_run)
		_finish(0)
	else:
		printerr("FAIL: %d failure(s) across %d transcript tests" % [_failures, _tests_run])
		_finish(1)


func _find_transcripts() -> Array:
	var paths: Array = []
	var directory := DirAccess.open("res://tests/transcripts")
	if directory == null:
		return paths
	for filename in directory.get_files():
		if filename.ends_with(".json"):
			paths.append("res://tests/transcripts/%s" % filename)
	paths.sort()
	return paths


func _run_transcript(path: String) -> void:
	var transcript = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(transcript) != TYPE_DICTIONARY:
		_fail("%s is not valid transcript JSON" % path)
		return

	var name := str(transcript.get("name", path))
	var initial: Dictionary = transcript.get("initial_state", {})
	var initial_state := MatchState.create(str(initial.get("match_id", "")), initial.get("player_ids", []))
	var setup_state := _run_steps(initial_state, transcript.get("setup_steps", []), "%s setup" % name)
	var cases: Array = transcript.get("cases", [])
	if cases.is_empty():
		_run_case(name, setup_state, transcript)
	else:
		for case in cases:
			_run_case("%s: %s" % [name, str(case.get("name", "unnamed case"))], setup_state, case)


func _run_case(name: String, setup_state: Dictionary, test_case: Dictionary) -> void:
	_tests_run += 1
	var failures_before := _failures
	var state := _run_steps(setup_state.duplicate(true), test_case.get("steps", []), name)
	_run_assertions(state, test_case.get("assertions", []), name)
	if _failures == failures_before:
		print("PASS: %s" % name)


func _run_steps(initial_state: Dictionary, steps: Array, context: String) -> Dictionary:
	var state := initial_state

	for step_index in steps.size():
		var step: Dictionary = steps[step_index]
		var before: Dictionary = state.duplicate(true)
		var result := MatchReducer.apply(state, step.get("event", {}))
		var expect_ok := bool(step.get("expect_ok", true))
		if bool(result["ok"]) != expect_ok:
			_fail("%s step %d expected ok=%s, got ok=%s: %s" % [context, step_index + 1, expect_ok, result["ok"], result["error"]])
			continue
		if not expect_ok:
			if result["state"] != before:
				_fail("%s step %d mutated state after rejection" % [context, step_index + 1])
			var error_contains := str(step.get("error_contains", ""))
			if not error_contains.is_empty() and error_contains not in str(result["error"]):
				_fail("%s step %d error did not contain '%s': %s" % [context, step_index + 1, error_contains, result["error"]])
		else:
			state = result["state"]
		_run_assertions(state, step.get("assertions", []), "%s step %d" % [context, step_index + 1])
	return state


func _run_assertions(state: Dictionary, assertions: Array, context: String) -> void:
	for assertion in assertions:
		var path_expression := str(assertion.get("path", ""))
		var lookup := _read_path(state, path_expression)
		if not lookup["found"]:
			_fail("%s assertion path was not found: %s" % [context, path_expression])
		elif lookup["value"] != assertion.get("equals"):
			_fail("%s expected %s = %s, got %s" % [context, path_expression, assertion.get("equals"), lookup["value"]])


func _run_hotseat_smoke() -> void:
	_tests_run += 1
	var failures_before := _failures
	var local_match := HotseatMatch.new()
	var result := local_match.start_new_match()
	if not result["ok"]:
		_fail("Hot-seat smoke setup failed: %s" % result["error"])
		return
	if local_match.state["active_player"] != 1:
		_fail("Hot-seat smoke expected Player 2 to start")

	result = local_match.select_action("mirror", "light_attack", "bruiser")
	if result["ok"]:
		result = local_match.prepare_attack_exchange()
	if result["ok"]:
		result = local_match.submit_claim(0, int(local_match.true_rolls[0]))
	if result["ok"]:
		result = local_match.submit_claim(1, int(local_match.true_rolls[1]))
	if result["ok"]:
		result = local_match.submit_challenge(0, false)
	if result["ok"]:
		result = local_match.submit_challenge(1, false)
	if result["ok"]:
		result = local_match.resolve_attack_exchange()
	if not result["ok"]:
		_fail("Hot-seat attack exchange failed: %s" % result["error"])
		return
	if local_match.state["phase"] != MatchState.PHASE_SELECT or local_match.state["active_player"] != 0:
		_fail("Hot-seat attack did not advance to Player 1 selection")
		return

	result = local_match.select_action("ledger", "defensive_stance", "ledger")
	if result["ok"]:
		result = local_match.resolve_non_attack_exchange()
	if not result["ok"]:
		_fail("Hot-seat non-attack exchange failed: %s" % result["error"])
		return
	if not local_match.find_character(0, "ledger")["effect_counters"].get("defensive_stance_active", false):
		_fail("Hot-seat defensive stance was not applied")
	if _failures == failures_before:
		print("PASS: local hot-seat controller smoke test")


func _run_commit_reveal_properties() -> void:
	_tests_run += 1
	var failures_before := _failures
	var secret := CommitReveal.generate_secret()
	var commit := CommitReveal.secret_commit(secret)
	if not CommitReveal.verify_secret(secret, commit):
		_fail("A valid secret did not match its commitment")
	if CommitReveal.verify_secret(secret + "tampered", commit):
		_fail("A tampered secret matched its commitment")

	var counts: Array[int] = []
	counts.resize(20)
	counts.fill(0)
	for index in 2000:
		var roll := CommitReveal.derive_roll("roller-%d" % index, "observer-%d" % (index * 17))
		if roll < 1 or roll > 20:
			_fail("A derived roll was outside 1 through 20")
			break
		counts[roll - 1] += 1
	for count in counts:
		if count < 65 or count > 135:
			_fail("Two thousand deterministic rolls were materially non-uniform: %s" % counts)
			break
	if _failures == failures_before:
		print("PASS: commit-reveal properties")


func _run_exchange_protocol() -> void:
	_tests_run += 1
	var failures_before := _failures
	var peer_zero := ExchangeProtocol.new()
	var peer_one := ExchangeProtocol.new()
	var queue: Array = []
	var local_rolls := [0, 0]
	var final_rolls := [null, null]
	var revealed_claims := [null, null]
	var revealed_challenges := [null, null]
	peer_zero.outbound_message.connect(func(message): queue.append([1, message]))
	peer_one.outbound_message.connect(func(message): queue.append([0, message]))
	peer_zero.roll_ready.connect(func(roll): local_rolls[0] = roll)
	peer_one.roll_ready.connect(func(roll): local_rolls[1] = roll)
	peer_zero.claims_ready.connect(func(claims): revealed_claims[0] = claims)
	peer_one.claims_ready.connect(func(claims): revealed_claims[1] = claims)
	peer_zero.challenges_ready.connect(func(challenges): revealed_challenges[0] = challenges)
	peer_one.challenges_ready.connect(func(challenges): revealed_challenges[1] = challenges)
	peer_zero.reveals_ready.connect(func(rolls, _reveals): final_rolls[0] = rolls)
	peer_one.reveals_ready.connect(func(rolls, _reveals): final_rolls[1] = rolls)

	peer_zero.begin("protocol-test", 4, 0)
	peer_one.begin("protocol-test", 4, 1)
	_pump_protocol_queue(queue, peer_zero, peer_one)
	if local_rolls[0] == 0 or local_rolls[1] == 0:
		_fail("Peers did not derive their private rolls after both commits")
	if peer_zero.roll_reveals[1] != null or peer_one.roll_reveals[0] != null:
		_fail("A peer learned the opponent's roll before challenge decisions")

	peer_zero.submit_claim(local_rolls[0])
	peer_one.submit_claim(mini(20, local_rolls[1] + 1))
	_pump_protocol_queue(queue, peer_zero, peer_one)
	if revealed_claims[0] == null or revealed_claims[0] != revealed_claims[1]:
		_fail("Peers did not reveal the same committed claims")

	peer_zero.submit_challenge(true)
	peer_one.submit_challenge(false)
	_pump_protocol_queue(queue, peer_zero, peer_one)
	if revealed_challenges[0] == null or revealed_challenges[0] != revealed_challenges[1]:
		_fail("Peers did not reveal the same committed challenge choices")
	if final_rolls[0] == null or final_rolls[0] != final_rolls[1]:
		_fail("Peers did not derive the same final roll pair")
	elif int(final_rolls[0][0]) != local_rolls[0] or int(final_rolls[0][1]) != local_rolls[1]:
		_fail("Final rolls did not match each roller's private value")
	if peer_zero.failed or peer_one.failed:
		_fail("An honest in-process exchange entered a failed state")
	if _failures == failures_before:
		print("PASS: two-peer blind exchange protocol")


func _pump_protocol_queue(queue: Array, peer_zero, peer_one) -> void:
	var delivered := 0
	while not queue.is_empty() and delivered < 100:
		var item: Array = queue.pop_front()
		if int(item[0]) == 0:
			peer_zero.receive(item[1])
		else:
			peer_one.receive(item[1])
		delivered += 1
	if delivered >= 100:
		_fail("Exchange protocol produced an unbounded message loop")


func _run_protocol_rejection() -> void:
	_tests_run += 1
	var failures_before := _failures
	var protocol := ExchangeProtocol.new()
	var error_holder := {"message": ""}
	protocol.protocol_failed.connect(func(message): error_holder["message"] = message)
	protocol.begin("rejection-test", 1, 0)
	protocol.receive({
		"type": "exchange",
		"match_id": "rejection-test",
		"exchange_number": 1,
		"phase": "CLAIM",
		"sender": 1,
		"kind": "claim_commit",
		"payload": {"commit": "too-early"},
	})
	if not protocol.failed or "before both roll commits" not in str(error_holder["message"]):
		_fail("An out-of-phase claim commitment was not rejected")
	if _failures == failures_before:
		print("PASS: adversarial protocol phase rejection")


func _run_state_hash() -> void:
	_tests_run += 1
	var failures_before := _failures
	var first := {"b": [2, {"z": true, "a": "value"}], "a": 1}
	var second := {"a": 1, "b": [2, {"a": "value", "z": true}]}
	if StateHash.hash_state(first) != StateHash.hash_state(second):
		_fail("State hash depends on dictionary insertion order")
	second["a"] = 2
	if StateHash.hash_state(first) == StateHash.hash_state(second):
		_fail("State hash did not change after state mutation")
	if _failures == failures_before:
		print("PASS: deterministic state hashing")


func _run_manual_signal_code() -> void:
	_tests_run += 1
	var failures_before := _failures
	var description := {"description_type": "offer", "sdp": "test-sdp"}
	var candidates := [{"media": "0", "index": 0, "name": "candidate:test"}]
	var match_id := "direct-0123456789abcdef0123456789abcdef"
	var code := ManualSignalCode.encode("offer", match_id, description, candidates)
	var decoded := ManualSignalCode.decode(code, "offer")
	if not decoded["ok"]:
		_fail("A valid manual connection code was rejected")
	else:
		if decoded["payload"]["match_id"] != match_id or decoded["payload"]["sdp"] != "test-sdp":
			_fail("Manual connection code changed its payload")
		var decoded_candidate: Dictionary = decoded["payload"]["candidates"][0]
		if str(decoded_candidate["media"]) != "0" or int(decoded_candidate["index"]) != 0 or str(decoded_candidate["name"]) != "candidate:test":
			_fail("Manual connection code changed its ICE candidates")
	if ManualSignalCode.decode(code, "answer")["ok"]:
		_fail("An offer connection code was accepted as an answer")
	if ManualSignalCode.decode("DD1.e30=", "offer")["ok"]:
		_fail("A damaged manual connection code was accepted")
	if _failures == failures_before:
		print("PASS: manual connection code validation")


func _run_victory_smoke() -> void:
	_tests_run += 1
	var failures_before := _failures
	var local_match := HotseatMatch.new()
	var result := local_match.start_new_match()
	if not result["ok"]:
		_fail("Victory smoke setup failed: %s" % result["error"])
		return

	for index in local_match.state["teams"][0]["characters"].size():
		var character: Dictionary = local_match.state["teams"][0]["characters"][index]
		if character["id"] == "bruiser":
			character["hp"] = 1
		else:
			character["hp"] = 0
			character["is_alive"] = false
		local_match.state["teams"][0]["characters"][index] = character

	result = local_match.select_action("mirror", "light_attack", "bruiser")
	if result["ok"]:
		result = local_match.prepare_attack_exchange()
	local_match.true_rolls = [1, 20]
	if result["ok"]:
		result = local_match.submit_claim(0, 1)
	if result["ok"]:
		result = local_match.submit_claim(1, 20)
	if result["ok"]:
		result = local_match.submit_challenge(0, false)
	if result["ok"]:
		result = local_match.submit_challenge(1, false)
	if result["ok"]:
		result = local_match.resolve_attack_exchange()
	if not result["ok"]:
		_fail("Victory smoke exchange failed: %s" % result["error"])
		return
	if local_match.state["status"] != MatchState.STATUS_FINISHED or local_match.state["winner_player"] != 1:
		_fail("Defeating the fourth character did not award the match")
	if _failures == failures_before:
		print("PASS: death and victory smoke test")


func _read_path(root: Variant, path: String) -> Dictionary:
	var current: Variant = root
	for segment in path.split("."):
		if typeof(current) == TYPE_DICTIONARY:
			if not current.has(segment):
				return {"found": false}
			current = current[segment]
		elif typeof(current) == TYPE_ARRAY and segment.is_valid_int():
			var index := segment.to_int()
			if index < 0 or index >= current.size():
				return {"found": false}
			current = current[index]
		else:
			return {"found": false}
	return {"found": true, "value": current}


func _fail(message: String) -> void:
	_failures += 1
	printerr("FAIL: %s" % message)


func _finish(exit_code: int) -> void:
	var result_file := FileAccess.open("res://tests/headless-test-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(str(exit_code))
	quit(exit_code)
