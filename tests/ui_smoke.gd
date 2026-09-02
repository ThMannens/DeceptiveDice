extends SceneTree

const MatchState = preload("res://src/core/match_state.gd")
const Roster = preload("res://src/core/roster.gd")
const Kits = preload("res://src/core/kits.gd")
const UiTheme = preload("res://src/presentation/theme.gd")
const PlateButton = preload("res://src/presentation/ui/plate_button.gd")
const PhaseRibbon = preload("res://src/presentation/ui/phase_ribbon.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene: PackedScene = load("res://src/presentation/main.tscn")
	var main = packed_scene.instantiate()
	root.add_child(main)
	await process_frame

	# The draft screens first (E8), then a preset match for the rest of the run.
	main._start_match()
	await process_frame
	_check(main.ui_stage == "DRAFT", "Start button did not open the draft")
	_check(main.game.state["phase"] == MatchState.PHASE_DRAFT, "A new match did not begin at DRAFT")

	for player in [0, 1]:
		var roster_ids: Array = Roster.character_ids()
		for pick_index in 4:
			main._toggle_draft_pick(str(roster_ids[pick_index]))
		await process_frame
		_check(main.draft_picks.size() == 4, "The draft did not hold four picks")
		# A fifth pick must be refused rather than silently replacing one.
		main._toggle_draft_pick(str(roster_ids[4]))
		_check(main.draft_picks.size() == 4, "The draft accepted a fifth character")
		main._submit_draft()
		await process_frame
		if player == 0:
			_check(main.ui_stage == "HANDOFF_DRAFT", "The first draft did not hand off")
			main.ui_stage = "DRAFT"

	_check(main.ui_stage == "HANDOFF_PLACEMENT", "Both drafts did not open placement")
	_check(main.game.state["phase"] == MatchState.PHASE_PLACEMENT, "Both drafts did not reach PLACEMENT")

	for player in [0, 1]:
		main.ui_stage = "PLACEMENT"
		main._render()
		await process_frame
		_check(main.formation_order.size() == 4, "Placement did not load the drafted four")
		var front_before := str(main.formation_order[3])
		main._move_in_formation(3, -1)
		_check(str(main.formation_order[2]) == front_before, "Reordering the formation did not move the character")
		main._submit_formation()
		await process_frame

	_check(main.ui_stage == "SELECT", "Both formations did not start the match")
	_check(main.game.state["status"] == MatchState.STATUS_ACTIVE, "The match did not become active")
	var placed := int(main.game.state["teams"][0]["characters"][0]["position"])
	_check(placed >= 1 and placed <= 4, "A drafted character was left without a position")

	main._start_quick_match()
	await process_frame
	_check(main.ui_stage == "SELECT", "Quick match did not open action selection")
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

	# The challenge screen itself, not just the submission behind it: it is the one
	# view that has to explain the decision, and it reads live kit and status state
	# to do so.
	main.ui_stage = "CHALLENGE"
	main._render()
	await process_frame
	_check(main._exchange_role(player, actor_id) == "ATTACKER", "The acting character was not marked as the attacker")
	_check(main._exchange_role(1 - player, target_id) == "DEFENDER", "The targeted character was not marked as the defender")
	_check(not main._current_matchup_text().is_empty(), "The header did not name the attacker and defender")

	main._submit_challenge(false)
	await process_frame
	_check(main.decision_player == 1, "First challenge did not hand off to Player 2")
	main._submit_challenge(false)
	await process_frame
	_check(main.ui_stage == "RESOLUTION", "Second challenge did not open resolution")
	_check(not main.game.state["last_resolution"].is_empty(), "The UI flow produced no resolution")
	_check(main.outcome_history.size() == 1, "The UI flow did not add an exchange log entry")

	await _check_rules_tooltips(main)
	await _check_visual_contract(main)

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
	var card: Control = _find_tooltipped(main, "The Scribe")
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


## The visual contract of the LARP overhaul: the parts of the interface a player
## reads before they read anything else, and the hidden-information boundaries
## the presentation layer must not cross.
##
## These are checked here rather than by eye because every one of them is a
## silent failure: a ribbon that disagrees with state, a card missing a kit name,
## or a decision control below a scroll boundary all still render happily.
func _check_visual_contract(main) -> void:
	main.ui_stage = "SELECT"
	main._render()
	await process_frame
	await process_frame

	# The ribbon step has to agree with the reducer's own phase, or the strip is
	# telling the player about a different turn than the board is.
	var phase := str(main.game.state["phase"])
	_check(
		main.phase_ribbon != null and main.phase_ribbon.current_step() == PhaseRibbon.step_for_phase(phase),
		"The phase ribbon does not match the public phase",
	)

	# Every character in play stands on the field with a nameplate, and every
	# plate names both of its kit effects: kits are public information the whole
	# game reads from, so they cannot be hidden behind a hover.
	var plates: Array = []
	_collect_plates(main, plates)
	_check(plates.size() == 8, "The board did not build all eight fighter plates, found %d" % plates.size())
	for plate in plates:
		var text := _collect_text(plate)
		var character_id := _plate_character_id(main, plate)
		for description in Kits.effect_descriptions(character_id):
			_check(
				str(description["name"]).to_upper() in text.to_upper(),
				"A fighter plate does not name its kit effect %s" % str(description["name"]),
			)

	# The opponent's roll must not be anywhere on screen during a blind phase.
	await _check_hidden_before_reveal(main)
	await _check_challenge_actions_visible(main)
	await _check_reduced_motion(main)


## No part of the interface may print the opponent's true roll while the claim
## is still blind. Checked against the actual rendered text rather than against
## the code path that would have drawn it.
func _check_hidden_before_reveal(main) -> void:
	main._start_quick_match()
	await process_frame
	var player := int(main.game.state["active_player"])
	var actor_id := str(main.game.available_actors(player)[0]["id"])
	main._on_card_clicked(player, actor_id)
	main.selected_move_id = "light_attack"
	main._render()
	var target_id := str(main.game.valid_targets(player, actor_id, "light_attack")[0]["id"])
	main._on_card_clicked(1 - player, target_id)
	await process_frame

	# Player 0 is about to make a private claim; player 1's roll is not theirs
	# to see. A single digit could collide by chance, so the check is on the
	# phrasing the interface uses to present a roll it owns.
	main.decision_player = 0
	main.ui_stage = "CLAIM"
	main._render()
	for i in 3:
		await process_frame
	var screen := _collect_text(main)
	_check(screen.count("YOUR ROLL") <= 1, "More than one private roll was shown at once")
	_check(
		not ("%d/20" % int(main.game.true_rolls[1])) in screen,
		"The opponent's true roll appeared before the reveal",
	)

	# Both claims in, so the checks that follow have a live challenge to read.
	main._submit_claim(int(main.game.true_rolls[0]))
	await process_frame
	main._submit_claim(int(main.game.true_rolls[1]))
	await process_frame


## Both challenge actions must be reachable at the smallest supported size. They
## live in the pinned footer rather than inside the prompt scroll, so this
## checks they are actually on screen and not merely constructed.
func _check_challenge_actions_visible(main) -> void:
	main.get_window().size = Vector2i(1024, 640)
	await process_frame
	main.decision_player = 0
	main.ui_stage = "CHALLENGE"
	main._render()
	for i in 4:
		await process_frame

	for label in ["LET IT STAND", "CHALLENGE"]:
		var button := _find_button(main, label)
		_check(button != null, "The %s action was not built at 1024x640" % label)
		if button == null:
			continue
		var bottom := button.get_global_rect().end.y
		_check(
			bottom <= main.size.y + 1.0,
			"The %s action sits below the visible area at 1024x640 (%.0f > %.0f)" % [label, bottom, main.size.y],
		)


## Reduced motion must reach the same settled values with nothing left running,
## because a queued tween there is a number the player never sees change.
func _check_reduced_motion(main) -> void:
	UiTheme.reduced_motion = true
	# A real resolution, so the sequence has beats to settle rather than an
	# empty stage that would settle trivially.
	main._submit_challenge(false)
	await process_frame
	main._submit_challenge(false)
	await process_frame
	_check(main.ui_stage == "RESOLUTION", "The challenge pair did not resolve the exchange")
	main._render()
	for i in 3:
		await process_frame
	var sequence := _find_sequence(main)
	_check(sequence != null, "The resolution built no reveal sequence")
	if sequence != null:
		_check(sequence.is_settled(), "Reduced motion left the reveal unsettled")
	var next_button := _find_button(main, "Next fighter")
	if next_button != null:
		_check(not next_button.disabled, "Reduced motion left the next action disabled")
	UiTheme.reduced_motion = false


func _collect_plates(node: Node, into: Array) -> void:
	if node is PlateButton:
		into.append(node)
	for child in node.get_children():
		_collect_plates(child, into)


## Which character a plate belongs to. The plate is a plain Control, so the
## mapping comes from the battlefield that placed it rather than from the node.
func _plate_character_id(main, plate: Control) -> String:
	if main.battlefield == null:
		return ""
	for player in 2:
		for character in main.game.state["teams"][player]["characters"]:
			var fighter = main.battlefield.fighter_for(player, str(character["id"]))
			if fighter != null and fighter.plate == plate:
				return str(character["id"])
	return ""


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_sequence(node: Node) -> Node:
	if node.get_script() != null and node.has_method("is_settled"):
		return node
	for child in node.get_children():
		var found := _find_sequence(child)
		if found != null:
			return found
	return null


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
