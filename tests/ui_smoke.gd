extends SceneTree

const MatchState = preload("res://src/core/match_state.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene: PackedScene = load("res://src/presentation/main.tscn")
	var main = packed_scene.instantiate()
	root.add_child(main)
	await process_frame

	main._start_match()
	await process_frame
	_check(main.ui_stage == "SELECT", "Start button did not open action selection")
	_check(main.actor_select != null and main.actor_select.item_count > 0, "Action selection has no available characters")

	# Direct board selection: click an actor, choose a move, click a target.
	var player := int(main.game.state["active_player"])
	var actor_id := str(main.game.available_actors(player)[0]["id"])
	_check(main._is_pickable_actor(player, actor_id), "An available character was not clickable on the board")
	main._on_card_clicked(player, actor_id)
	await process_frame
	_check(main.selected_actor_id == actor_id, "Clicking a character did not select it")

	main.selected_move_id = "light_attack"
	main._render()
	await process_frame
	var target_id := str(main.game.valid_targets(player, actor_id, "light_attack")[0]["id"])
	_check(main._is_valid_target(1 - player, target_id), "An enemy was not clickable as an attack target")
	_check(not main._is_valid_target(player, actor_id), "The attacker was wrongly clickable as its own target")

	main._on_card_clicked(1 - player, target_id)
	await process_frame
	_check(main.ui_stage == "HANDOFF_CLAIM", "Attack selection did not open the first private claim handoff")
	_check(main.game.state["phase"] == MatchState.PHASE_CLAIM, "Attack setup did not reach CLAIM")

	main._submit_claim(int(main.game.true_rolls[0]))
	await process_frame
	_check(main.decision_player == 1, "First claim did not hand off to Player 2")
	main._submit_claim(int(main.game.true_rolls[1]))
	await process_frame
	_check(main.ui_stage == "HANDOFF_CHALLENGE", "Second claim did not open challenge handoff")

	main._submit_challenge(false)
	await process_frame
	_check(main.decision_player == 1, "First challenge did not hand off to Player 2")
	main._submit_challenge(false)
	await process_frame
	_check(main.ui_stage == "RESOLUTION", "Second challenge did not open resolution")
	_check(not main.game.state["last_resolution"].is_empty(), "The UI flow produced no resolution")
	_check(main.outcome_history.size() == 1, "The UI flow did not add an exchange log entry")

	if not _failed:
		print("PASS: playable interface smoke test")
	_finish(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: %s" % message)


func _finish(exit_code: int) -> void:
	var result_file := FileAccess.open("res://tests/ui-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(str(exit_code))
	quit(exit_code)
