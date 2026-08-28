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

	await _check_rules_tooltips(main)

	if not _failed:
		print("PASS: playable interface smoke test")
	_finish(1 if _failed else 0)


## Godot asks the hovered control itself for its tooltip node, so a builder that
## lives anywhere else is silently ignored and the player sees a plain default
## tooltip. That failure is invisible without an explicit check, so it gets one:
## the kit pills and character cards must carry the builder, and the tooltip it
## produces must actually define the rules vocabulary its text uses.
func _check_rules_tooltips(main) -> void:
	main.ui_stage = "SELECT"
	main._render()
	await process_frame

	var pill: Control = _find_tooltipped(main, "Bookkeeping")
	_check(pill != null, "No kit pill carrying kit text was found on the board")
	var card: Control = _find_tooltipped(main, "The Ledger")
	_check(card != null, "No character card carrying a stat tooltip was found on the board")
	if pill == null or card == null:
		return

	for control: Control in [pill, card]:
		_check(
			control.has_method("_make_custom_tooltip"),
			"A tooltipped control cannot build its own tooltip, so Godot falls back to the plain default",
		)
		if not control.has_method("_make_custom_tooltip"):
			continue
		var tooltip: Variant = control.call("_make_custom_tooltip", control.tooltip_text)
		_check(tooltip is Control, "The custom tooltip builder returned no node")
		if tooltip is Control:
			_check(
				"Locked in:" in _collect_text(tooltip),
				"The tooltip did not define the rules vocabulary its text uses",
			)
			(tooltip as Control).queue_free()


func _find_tooltipped(node: Node, prefix: String) -> Control:
	if node is Control and (node as Control).tooltip_text.begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _find_tooltipped(child, prefix)
		if found != null:
			return found
	return null


func _collect_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _collect_text(child)
	return text


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: %s" % message)


func _finish(exit_code: int) -> void:
	var result_file := FileAccess.open("res://tests/ui-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string(str(exit_code))
	quit(exit_code)
