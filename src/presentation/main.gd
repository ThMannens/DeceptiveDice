extends Control

const HotseatMatch = preload("res://src/local/hotseat_match.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Moves = preload("res://src/core/moves.gd")
const Roster = preload("res://src/core/roster.gd")
const CombatResolver = preload("res://src/core/combat_resolver.gd")
const Kits = preload("res://src/core/kits.gd")
const RulesTooltip = preload("res://src/presentation/rules_tooltip.gd")
const DirectTransport = preload("res://src/network/direct_transport.gd")
const NetworkMatch = preload("res://src/network/network_match.gd")

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const CharacterCard = preload("res://src/presentation/ui/character_card.gd")
const TeamRoster = preload("res://src/presentation/ui/team_roster.gd")
const PhaseRibbon = preload("res://src/presentation/ui/phase_ribbon.gd")
const ClaimSheet = preload("res://src/presentation/ui/claim_sheet.gd")
const Portrait = preload("res://src/presentation/ui/portrait.gd")
const ResolutionSequence = preload("res://src/presentation/animation/resolution_sequence.gd")

## Move order shown in the action buttons.
const MOVE_IDS: Array[String] = ["light_attack", "heavy_attack", "defensive_stance", "swap"]

## The prop each move is made with, in the same hand-drawn stroke as the rest of
## the icons. Decoration only: every move is named in full beside its glyph, so
## none of these has to be understood to read a rule.
const MOVE_PROPS := {
	"light_attack": "⚔",
	"heavy_attack": "⚒",
	"defensive_stance": "⛨",
	"swap": "⇄",
}

## Kit effects that change what a challenge is worth, listed on the challenge
## screen. Front Fighter and Drag are left out: they alter a hit that has already
## landed, not the challenge decision itself.
const CHALLENGE_RELEVANT_EFFECTS: Array[String] = [
	Kits.EFFECT_THICK_SKULL,
	Kits.EFFECT_ALL_IN,
	Kits.EFFECT_COLD_STREAK,
	Kits.EFFECT_REFLECT,
	Kits.EFFECT_READ_THE_ROOM,
	Kits.EFFECT_BOOKKEEPING,
	Kits.EFFECT_AUDIT,
	Kits.EFFECT_SLIPPERY,
]

var game: Variant = HotseatMatch.new()
var ui_stage := "START"
var decision_player := -1
var outcome_history: Array[String] = []
var online_mode := false
## The live phase countdown, and the label showing it. Held rather than rebuilt
## so the timer can tick without re-rendering the prompt around it.
var countdown_seconds := -1
var countdown_label: Label
## The draft in progress: the ids this player has picked, and the order they are
## arranging them in. Both are cleared once submitted to the reducer.
var draft_picks: Array = []
var formation_order: Array = []
## The reconnection window countdown, updated in place for the same reason the
## phase countdown is.
var reconnect_seconds := -1
var reconnect_label: Label
var connection_status := ""

var round_label: Label
var active_label: Label
var board_container: HBoxContainer
var board_scroll: ScrollContainer
var lower_row: HBoxContainer
var prompt_box: VBoxContainer
var history_label: RichTextLabel
var error_label: Label
var subtitle_label: Label

## The three-column exchange theatre. The two roster columns and the centre
## stage are held rather than rebuilt from scratch, so the layout at 1280x720
## and 1024x640 is decided once and only the contents change.
var phase_ribbon: PhaseRibbon
var rosters: Array = [null, null]
var claim_sheets: Array = [null, null]
var roster_columns: Array = [null, null]
## Every claim that has become public, newest first, one list per player. Built
## as resolutions land rather than read back out of state, because the reducer
## keeps only the last resolution.
var claim_records: Array = [[], []]

## The claim histories and the exchange log both live in the lower row; the log
## is a compact ticker rather than a fixed column, so it costs nothing while
## empty.
var log_panel: PanelContainer
## The pinned row beneath the prompt scroll. Anything a stage must keep on
## screen — challenge actions, the confirm on a long form — goes here.
var prompt_footer: HBoxContainer
## The wooden frame and the column inside it. Both give up margin at the
## smallest supported window, where the border costs the decision row real rows.
var table_frame: PanelContainer
var page_box: VBoxContainer

# Direct board selection. The OptionButtons below are kept as the underlying
# model so existing callers and tests still drive the same code path, but the
# board is now the primary way to choose an actor, a move, and a target.
var selected_actor_id := ""
var selected_move_id := ""

var actor_select: OptionButton
var move_select: OptionButton
var target_select: OptionButton
var move_help: Label
var submit_action_button: Button


func _ready() -> void:
	get_window().min_size = Vector2i(1024, 640)
	theme = UiTheme.build_theme()
	_build_shell()
	# The layout picks its column widths and decision-row height from the window
	# size, so a resize has to re-run it rather than stretching what is there.
	resized.connect(_on_resized)
	_render()


## Re-lays out when the window crosses a size tier. Only a tier change rebuilds:
## a render on every pixel of a drag would tear whatever input the player holds.
var _last_layout_tier := ""


func _on_resized() -> void:
	var tier := "roomy" if _is_roomy() else ("compact" if _is_compact() else "normal")
	if tier == _last_layout_tier:
		return
	_last_layout_tier = tier
	_render()


func _process(_delta: float) -> void:
	if online_mode and game != null:
		game.poll()


func _build_shell() -> void:
	# The outer frame is the folding table: dark wood under a worn canvas tent
	# floor, so every paper surface above it reads as something set down rather
	# than as a floating panel.
	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.COLOR_WOOD_DARK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var table := PanelContainer.new()
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table_frame = table
	table.offset_left = 12
	table.offset_top = 12
	table.offset_right = -12
	table.offset_bottom = -12
	var table_style := UiTheme.paper_style("wood")
	table_style.content_margin_left = 12
	table_style.content_margin_right = 12
	table_style.content_margin_top = 10
	table_style.content_margin_bottom = 10
	table.add_theme_stylebox_override("panel", table_style)
	add_child(table)

	page_box = VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 8)
	page_box.clip_contents = true
	table.add_child(page_box)
	var page := page_box

	page.add_child(_build_header())

	# The tournament score strip. Persistent, so the current step of the
	# exchange is readable without reading anything else on screen.
	phase_ribbon = PhaseRibbon.new()
	page.add_child(phase_ribbon)

	# The three-column exchange theatre: roster, centre stage, roster. The
	# rosters keep a bounded width so the stage never falls below the minimum
	# the decision controls need.
	# The board is a plain row: each column bounds its own contents, so nothing
	# inside it can dictate the page height.
	board_container = HBoxContainer.new()
	board_container.add_theme_constant_override("separation", 8)
	board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_container.clip_contents = true
	# The board is the region that yields. A zero minimum lets the decision row
	# below it keep its full height at the smallest supported window size.
	board_container.custom_minimum_size.y = 0
	page.add_child(board_container)
	board_scroll = null

	# The bottom row: the current decision and its primary controls, flanked by
	# each player's own claim record. Bounded height, because a primary control
	# below a scroll boundary is the failure this layout exists to prevent.
	lower_row = HBoxContainer.new()
	lower_row.add_theme_constant_override("separation", 8)
	lower_row.custom_minimum_size.y = 150
	lower_row.size_flags_vertical = Control.SIZE_SHRINK_END
	page.add_child(lower_row)

	# The error line takes no row until there is something to print on it.
	error_label = Widgets.wrapped_label("", 13, UiTheme.COLOR_DANGER)
	error_label.visible = false
	page.add_child(error_label)


## The tournament banner: a painted title board with the round and the current
## matchup lettered beside it.
func _build_header() -> PanelContainer:
	var header_panel := PanelContainer.new()
	var header_style := UiTheme.paper_style("secondary")
	header_style.content_margin_top = 6
	header_style.content_margin_bottom = 6
	# A tape stripe along the bottom edge ties the banner to the score strip
	# hanging directly beneath it.
	header_style.border_width_bottom = 5
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_panel.add_child(header)

	# A painted wooden die standing in for the tournament badge.
	header.add_child(Widgets.label("⚅", 26, UiTheme.COLOR_ACCENT_DARK))

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	header.add_child(title_box)
	title_box.add_child(Widgets.label("DECEPTIVE DICE", 21, UiTheme.COLOR_INK))
	subtitle_label = Widgets.label("Playable prototype", 11, UiTheme.COLOR_INK_MUTED)
	title_box.add_child(subtitle_label)

	header.add_child(Widgets.filler())

	round_label = Widgets.label("", 14, UiTheme.COLOR_INK_MUTED)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(round_label)

	active_label = Widgets.label("", 15, UiTheme.COLOR_INK)
	header.add_child(active_label)

	# Reduced motion is on the banner because that is the one surface present on
	# every screen, and a player who needs it needs it before the first reveal.
	var motion := CheckButton.new()
	motion.text = "Reduced motion"
	motion.add_theme_font_size_override("font_size", 11)
	motion.button_pressed = UiTheme.reduced_motion
	motion.tooltip_text = "Reduced motion
Replaces the reveal animation with immediate numbers. The result and the arithmetic are identical either way."
	motion.toggled.connect(func(on: bool):
		UiTheme.reduced_motion = on
		_render()
	)
	header.add_child(motion)
	return header_panel


## The exchange log: a compact chronological ticker rather than a fixed column.
## It sits in the centre stage's footer during play, so it costs no width at all
## before a match and none while empty.
func _build_log_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.paper_style("secondary"))
	panel.custom_minimum_size.y = 54
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	box.add_child(Widgets.label("EXCHANGE LOG", 10, UiTheme.COLOR_INK_MUTED))
	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = false
	history_label.scroll_active = true
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 12)
	history_label.add_theme_color_override("default_color", UiTheme.COLOR_INK_MUTED)
	box.add_child(history_label)
	return panel


## Rebuilds both claim sheets from the public record this session has collected.
func _render_claim_record() -> void:
	for player in 2:
		var sheet: ClaimSheet = claim_sheets[player]
		if sheet == null or not is_instance_valid(sheet):
			continue
		var recorded: Array = []
		if not state_is_empty():
			recorded = game.state["teams"][player].get("recorded_paddings", [])
		sheet.render(claim_records[player], recorded, _player_color(player))


## Files both sides of a resolved exchange onto their own claim sheets. Called
## once a resolution is public, so nothing reaches a sheet before the reveal.
func _record_claims(resolution: Dictionary) -> void:
	if resolution.get("non_attack", false):
		return
	var attacker_player := int(resolution["attacker_player"])
	var defender_player := int(resolution["defender_player"])
	for entry in [
		{"player": attacker_player, "side": resolution["attack"], "id": str(resolution["actor_id"])},
		{"player": defender_player, "side": resolution["defence"], "id": str(resolution["target_id"])},
	]:
		var side: Dictionary = entry["side"]
		var claim := int(side["claim"])
		var true_roll := int(side["true_roll"])
		var record: Array = claim_records[int(entry["player"])]
		record.push_front({
			"character": _character_name(int(entry["player"]), str(entry["id"])),
			"claim": claim,
			"true_roll": true_roll,
			"padding": maxi(0, claim - true_roll),
			"outcome": str(side["outcome"]),
		})
		# A sheet that grows without bound turns into a scroll nobody reads; the
		# last dozen claims are as far back as a read is ever made.
		if record.size() > 12:
			record.resize(12)


func _render() -> void:
	# The board selection only means something during SELECT; clearing it
	# elsewhere stops a stale actor carrying into the next turn.
	if ui_stage != "SELECT":
		selected_actor_id = ""
		selected_move_id = ""
	else:
		_validate_selection()
	_apply_layout_balance()
	if subtitle_label != null:
		subtitle_label.text = "Online peer-to-peer" if online_mode else "Local hot-seat"
	_render_header()
	_render_ribbon()
	_render_board()
	_render_history()
	_render_claim_record()
	_render_prompt()


## Repaints the tournament score strip.
##
## The ribbon reads the reducer's own phase rather than the UI stage, so the
## step it paints can never drift from public state. The waiting cue and the
## clock are UI facts the phase alone cannot carry, so those come from here.
func _render_ribbon() -> void:
	if phase_ribbon == null or state_is_empty():
		return
	var phase := str(game.state["phase"])
	# The reducer advances past RESOLVE the moment an exchange settles, so the
	# ribbon would jump to the next turn while the player is still reading the
	# result. The UI stage is the authority for this one step.
	if ui_stage == "RESOLUTION":
		phase = MatchState.PHASE_RESOLVE
	var waiting := ui_stage.begins_with("WAIT_") or ui_stage.begins_with("HANDOFF_")
	# Only online play has a clock: hot-seat passes the device by hand, so a
	# timer there would punish a player for reading their own kit rather than
	# for stalling an opponent.
	var seconds := countdown_seconds if online_mode else -1
	phase_ribbon.render(phase, waiting, seconds, _phase_timer_total())


## The full length of the current phase's clock, so the stitched underline has
## something to shrink against. Zero outside a timed phase.
func _phase_timer_total() -> int:
	if not online_mode:
		return 0
	var timeouts: Dictionary = NetworkMatch.PHASE_TIMEOUT_SECONDS
	return int(timeouts.get(ui_stage, 0.0))


## Drops a selection that the current state no longer allows, so the board and
## the prompt never disagree about what is selected. Runs before the board is
## drawn because the highlighting reads these directly.
func _validate_selection() -> void:
	if state_is_empty():
		selected_actor_id = ""
		selected_move_id = ""
		return
	var player := int(game.state["active_player"])
	if not selected_actor_id.is_empty() and not _is_pickable_actor(player, selected_actor_id):
		selected_actor_id = ""
		selected_move_id = ""
	if selected_actor_id.is_empty():
		selected_move_id = ""


## Reshapes the shell for the current stage.
##
## Out of a match there is no board and no claim record worth showing, so the
## whole page goes to the menu rather than reserving an empty combat area above
## it. In a match the bottom row takes a fixed share of the height and the board
## gives up what is left, so a decision control can never end up below the fold.
func _apply_layout_balance() -> void:
	if board_container == null or lower_row == null:
		return
	var in_match := _board_is_meaningful()
	board_container.visible = in_match
	# The ribbon still names draft and placement, so it stays up through them;
	# only a completely empty session hides it.
	if phase_ribbon != null:
		phase_ribbon.visible = not state_is_empty()

	if not in_match:
		lower_row.custom_minimum_size.y = 0
		lower_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return

	# The challenge screen carries both risk branches and both actions, which is
	# the longest decision in the game. It gets the extra height from the board
	# rather than from a scroll, so LET IT STAND and CHALLENGE stay on screen.
	var compact := _is_compact()
	var roomy := _is_roomy()
	# Enough for both risk branches and the pinned actions on the challenge
	# screen, and enough for the reveal and its next control everywhere else.
	# The board takes what is left, so the four cards per side stay whole at the
	# sizes that can hold them.
	var decision_height := 340
	if compact:
		# The branches stack at this size, so the row needs less width-driven
		# height and the board keeps enough to show a readable card.
		decision_height = 285
	elif roomy:
		decision_height = 400
	if ui_stage != "CHALLENGE":
		decision_height = 190 if compact else 215
		if roomy:
			decision_height = 240

	# The bottom row keeps its height and the board takes whatever is left, which
	# is the whole point of every column bounding its own contents.
	lower_row.custom_minimum_size.y = decision_height
	lower_row.size_flags_vertical = Control.SIZE_SHRINK_END
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Trims the wooden frame and the page gaps at the smallest supported window.
## The border is decoration; at 1024x640 it was costing the decision row the
## rows of pixels its pinned footer needs.
func _apply_frame_margins(compact: bool) -> void:
	if table_frame == null or page_box == null:
		return
	var inset := 4.0 if compact else 12.0
	table_frame.offset_left = inset
	table_frame.offset_top = inset
	table_frame.offset_right = -inset
	table_frame.offset_bottom = -inset
	var style := UiTheme.paper_style("wood")
	var pad := 6 if compact else 12
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad - 2
	style.content_margin_bottom = pad - 2
	table_frame.add_theme_stylebox_override("panel", style)
	page_box.add_theme_constant_override("separation", 5 if compact else 8)


## True once there are crews on the field to draw.
##
## Draft and placement happen before that: the characters are still on the sheet,
## so those screens get the whole page instead of a board that would show two
## empty canvases and an exchange log with nothing in it.
func _board_is_meaningful() -> bool:
	if state_is_empty():
		return false
	return str(game.state["phase"]) not in [MatchState.PHASE_DRAFT, MatchState.PHASE_PLACEMENT]


## True at the smaller supported window size, where the roster columns narrow
## and the portraits shrink before any body text does.
func _is_compact() -> bool:
	return size.x < 1180.0


## True on a full-height display, where the layout stops rationing space: the
## rosters get wider cards and the decision row gets the room to keep both
## challenge actions and both risk branches visible at once.
func _is_roomy() -> bool:
	return size.x >= 1600.0 and size.y >= 900.0


## The roster column width for the current window size.
func _roster_width() -> int:
	if _is_roomy():
		return 380
	return 250 if _is_compact() else 305


func _render_header() -> void:
	if game.state.is_empty():
		round_label.text = ""
		active_label.text = ""
		return
	round_label.text = "ROUND %d  ·  EXCHANGE %d" % [game.state["round_number"], game.state["exchange_number"]]
	if game.state["status"] == MatchState.STATUS_FINISHED:
		active_label.text = "MATCH OVER"
		active_label.add_theme_color_override("font_color", UiTheme.COLOR_INK)
	else:
		var active := int(game.state["active_player"])
		# Once an action is chosen the header names the matchup rather than the
		# acting side. A defender otherwise only ever learns that they have to
		# defend, with no way to see who is swinging at whom.
		var matchup := _current_matchup_text()
		if matchup.is_empty():
			active_label.text = "%s IS UP" % _player_name(active).to_upper()
		else:
			active_label.text = matchup
		# Ink rather than the player colour: the header is a paper banner, and
		# player colour on this surface would read as an outcome.
		active_label.add_theme_color_override("font_color", UiTheme.COLOR_INK)


## "ATTACKER", "DEFENDER", or "" for a card, based on the locked-in action of the
## exchange in progress. Only attacks have two sides, so a stance or a swap leaves
## every card unmarked.
func _exchange_role(player: int, character_id: String) -> String:
	if state_is_empty():
		return ""
	var action: Dictionary = game.state["exchange"].get("action", {})
	if action.is_empty() or str(action.get("actor_id", "")).is_empty():
		return ""
	if not Moves.is_attack(str(action["move_id"])):
		return ""
	var actor_player := int(action["player"])
	if player == actor_player and character_id == str(action["actor_id"]):
		return "ATTACKER"
	if player != actor_player and character_id == str(action["target_id"]):
		return "DEFENDER"
	return ""


## "BRUISER ⚔ GAMBLER" for the exchange in progress, empty before an action is
## selected or for a move with no opposing target.
func _current_matchup_text() -> String:
	if state_is_empty():
		return ""
	var action: Dictionary = game.state["exchange"].get("action", {})
	if action.is_empty() or str(action.get("actor_id", "")).is_empty():
		return ""
	var actor_player := int(action["player"])
	var actor := _character_name(actor_player, str(action["actor_id"])).to_upper()
	if not Moves.is_attack(str(action["move_id"])):
		return "%s: %s" % [actor, Moves.get_move(str(action["move_id"]))["display_name"].to_upper()]
	var target := _character_name(1 - actor_player, str(action["target_id"])).to_upper()
	return "%s ⚔ %s" % [actor, target]


## Builds the exchange theatre: roster, centre stage, roster, with each player's
## claim sheet pinned under their own side.
func _render_board() -> void:
	_clear_children(board_container)
	_clear_children(lower_row)
	rosters = [null, null]
	claim_sheets = [null, null]
	roster_columns = [null, null]
	history_label = null
	log_panel = null

	prompt_footer = null
	if not _board_is_meaningful():
		# Before the crews are on the field there is nothing to lay out. The
		# prompt takes the full page rather than sitting beside an empty board
		# and an empty log.
		prompt_box = _build_stage_column(lower_row, false)
		return

	var compact := _is_compact()
	var width := _roster_width()

	for player in 2:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		column.custom_minimum_size = Vector2(width, 0)
		column.size_flags_horizontal = Control.SIZE_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.clip_contents = true
		roster_columns[player] = column

		# The roster scrolls inside its own column. Without this the four cards
		# set the board's minimum height, which beats every ceiling the layout
		# puts on it and pushes the decision row off the bottom of the page.
		var roster_scroll := ScrollContainer.new()
		roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(roster_scroll)

		var roster := TeamRoster.new()
		roster.card_clicked.connect(_on_card_clicked)
		roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rosters[player] = roster
		roster_scroll.add_child(roster)
		_render_team(player, roster, compact)

	# The claim sheets sit under their own rosters, so reading what an opponent
	# has been claiming never means scanning past your own. At the smallest
	# supported size they fold into the roster columns instead of taking a third
	# of a bottom row that barely fits the decision.
	for player in 2:
		var sheet := ClaimSheet.new()
		sheet.custom_minimum_size.x = width
		claim_sheets[player] = sheet
	if compact:
		for player in 2:
			claim_sheets[player].custom_minimum_size.y = 90
			roster_columns[player].add_child(claim_sheets[player])
	else:
		lower_row.add_child(claim_sheets[0])
	# Built before the stage: a decision that plays on the stage parents its
	# commit control into this column's pinned footer.
	prompt_box = _build_stage_column(lower_row, true)
	if not compact:
		lower_row.add_child(claim_sheets[1])

	# Rosters flank the board; the centre stage takes the slack width.
	board_container.add_child(roster_columns[0])
	board_container.add_child(_build_stage_frame(compact))
	board_container.add_child(roster_columns[1])


## The centre column of the board: the exchange itself, plus the log ticker.
func _build_stage_frame(compact: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.clip_contents = true
	# The stage never narrows past what the decision controls need, even when
	# the window is at the smaller supported size, but it may give up any height.
	column.custom_minimum_size = Vector2(380 if compact else (560 if _is_roomy() else 440), 0)

	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", UiTheme.paper_style("well"))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	# The stage is allowed to be squeezed to nothing. Its contents are echoed in
	# the roster cards and the decision panel, so losing height here costs no
	# information; letting it set a floor would cost the decision its footer.
	stage.custom_minimum_size.y = 0
	column.add_child(stage)

	var stage_box := VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 6)
	stage_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	stage.add_child(stage_box)
	_render_stage(stage_box)

	# The log ticker is the first thing to go when the board is squeezed: it is a
	# scrollback of what already happened, not part of the current decision.
	log_panel = _build_log_panel()
	log_panel.visible = not _is_compact()
	column.add_child(log_panel)
	return column


## The prompt column: the current decision and its primary controls.
##
## `bounded` gives it a scroll for the busy stages; the pre-match menu instead
## takes the whole page, since there is no board competing for the height.
func _build_stage_column(parent: Control, bounded: bool) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.paper_style("raised"))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if not bounded:
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if bounded:
		# The prompt scrolls, but the footer beneath it does not: a primary
		# action parented there can never end up below a scroll boundary.
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 6)
		panel.add_child(stack)

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(scroll)
		scroll.add_child(box)

		prompt_footer = HBoxContainer.new()
		prompt_footer.add_theme_constant_override("separation", 10)
		prompt_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(prompt_footer)
	else:
		panel.add_child(box)
		prompt_footer = null
	return box


## What the centre of the board shows: who is fighting whom this exchange, the
## props available to the chosen fighter, or the phase prompt before anything is
## locked in.
func _render_stage(box: VBoxContainer) -> void:
	var action: Dictionary = game.state["exchange"].get("action", {})
	var labels: Dictionary = PhaseRibbon.phase_label(str(game.state["phase"]))

	if action.is_empty() or str(action.get("actor_id", "")).is_empty():
		# On the resolution screen the reducer has already cleared the action and
		# moved on, so the phase labels would announce the next turn while the
		# player is still reading the last one. The stage names the beat the
		# player is actually on instead.
		if ui_stage == "RESOLUTION":
			labels = PhaseRibbon.phase_label(MatchState.PHASE_RESOLVE)
		box.add_child(Widgets.centered_label(str(labels["main"]), 20, UiTheme.COLOR_PAPER))
		box.add_child(Widgets.centered_label(str(labels["support"]), 13, UiTheme.COLOR_CARDBOARD))
		# During SELECT the stage is where the fighter and their props go, so it
		# is not a large empty well while the decision sits in a side panel.
		if ui_stage == "SELECT" and not selected_actor_id.is_empty():
			_render_select_stage(box)
		return

	# The private boast is the exchange's own beat, so it plays on the stage
	# under the matchup rather than in the bottom row, which cannot hold the
	# roll, the input, and both branches at once.
	var claim_on_stage := ui_stage == "CLAIM"

	var actor_player := int(action["player"])
	var move := Moves.get_move(str(action["move_id"]))
	box.add_child(Widgets.centered_label(str(labels["main"]), 15, UiTheme.COLOR_CARDBOARD))

	var matchup := HBoxContainer.new()
	matchup.add_theme_constant_override("separation", 10)
	matchup.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(matchup)
	matchup.add_child(_stage_fighter(actor_player, str(action["actor_id"]), "ATTACKER"))
	if Moves.is_attack(str(action["move_id"])):
		matchup.add_child(Widgets.label("⚔", 26, UiTheme.COLOR_ACCENT))
		matchup.add_child(_stage_fighter(1 - actor_player, str(action["target_id"]), "DEFENDER"))

	var move_row := HBoxContainer.new()
	move_row.alignment = BoxContainer.ALIGNMENT_CENTER
	move_row.add_theme_constant_override("separation", 6)
	box.add_child(move_row)
	move_row.add_child(Widgets.stamp(str(move["display_name"]).to_upper(), UiTheme.COLOR_ACCENT, 12))

	# The multiplier the target's rank applies, named at the point the target is
	# chosen rather than left for the player to remember.
	if Moves.is_attack(str(action["move_id"])):
		var target: Dictionary = game.find_character(1 - actor_player, str(action["target_id"]))
		var target_position := int(target.get("position", 3))
		move_row.add_child(Widgets.patch(
			"POSITION %d · %s DAMAGE" % [target_position, str(CharacterCard.POSITION_LABELS.get(target_position, "100%"))],
			UiTheme.COLOR_WARNING, 10,
		))

	if claim_on_stage:
		_render_claim_stage(box)


## The chosen fighter on the stage with their four props, and once a move is
## picked, where it can land.
func _render_select_stage(box: VBoxContainer) -> void:
	var player := int(game.state["active_player"])
	var actor: Dictionary = game.find_character(player, selected_actor_id)
	if actor.is_empty():
		return

	var token := HBoxContainer.new()
	token.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(token)
	token.add_child(_stage_fighter(player, selected_actor_id, "PICKED"))

	# The props sit on the table under the fighter who would use them, at a width
	# that keeps all four in one glance.
	var props := PanelContainer.new()
	props.add_theme_stylebox_override("panel", UiTheme.paper_style("raised"))
	props.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	props.custom_minimum_size.x = 380
	box.add_child(props)
	var props_box := VBoxContainer.new()
	props_box.add_theme_constant_override("separation", 5)
	props.add_child(props_box)
	props_box.add_child(Widgets.label("PICK A MOVE", 11, UiTheme.COLOR_INK_MUTED))
	props_box.add_child(_build_move_buttons(player, actor))

	if selected_move_id.is_empty():
		return
	props_box.add_child(Widgets.wrapped_label(_move_description(selected_move_id), 12, UiTheme.COLOR_INK_MUTED))
	props_box.add_child(_build_target_hint(player))


## One side of the centre matchup: a paper-token echo of the roster card.
func _stage_fighter(player: int, character_id: String, role: String) -> Control:
	var character: Dictionary = game.find_character(player, character_id)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.paper_style("raised"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	box.add_child(Portrait.build(
		character_id, str(character.get("display_name", character_id)), _player_color(player), 44,
	))
	box.add_child(Widgets.centered_label(str(character.get("display_name", character_id)), 13, UiTheme.COLOR_INK))
	var tag := HBoxContainer.new()
	tag.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(tag)
	tag.add_child(Widgets.patch(
		role, UiTheme.COLOR_ACCENT if role == "ATTACKER" else UiTheme.COLOR_INFO, 9,
	))
	return panel


## Fills one roster column with the current team.
func _render_team(player: int, roster: TeamRoster, compact: bool) -> void:
	var is_active := player == int(game.state["active_player"])
	var characters: Array = game.state["teams"][player]["characters"]
	var used: Array = game.state["teams"][player]["used_character_ids"]

	var states := {}
	var clickable: Array = []
	for character in characters:
		var character_id := str(character["id"])
		states[character_id] = _card_state(player, character, is_active, character_id in used)
		if _is_pickable_actor(player, character_id) or _is_valid_target(player, character_id):
			clickable.append(character_id)

	roster.render(player, characters, {
		"name": _player_name(player),
		"tint": _player_color(player),
		"acting": is_active and game.state["status"] != MatchState.STATUS_FINISHED,
		"compact": compact,
		"card_states": states,
		"clickable_ids": clickable,
	})


## The one interaction state a card is in. Resolved in priority order, so a card
## is never both a target and a defender: the most decision-relevant state wins.
func _card_state(player: int, character: Dictionary, team_is_active: bool, used: bool) -> String:
	if not bool(character["is_alive"]):
		return CharacterCard.STATE_DEFEATED
	var character_id := str(character["id"])
	if character_id == selected_actor_id and player == int(game.state["active_player"]):
		return CharacterCard.STATE_SELECTED
	if _is_valid_target(player, character_id):
		return CharacterCard.STATE_LEGAL_TARGET
	match _exchange_role(player, character_id):
		"ATTACKER":
			return CharacterCard.STATE_ATTACKER
		"DEFENDER":
			return CharacterCard.STATE_DEFENDER
	if used:
		return CharacterCard.STATE_ACTED
	if team_is_active:
		return CharacterCard.STATE_READY
	return CharacterCard.STATE_NORMAL


## Damage taken by formation slot, as a display string. The authority is
## CombatResolver.POSITION_DAMAGE_PERCENT; this only formats it.
func _position_multiplier_text(position: int) -> String:
	return "%.2f" % (float(CombatResolver.POSITION_DAMAGE_PERCENT.get(position, 100)) / 100.0)


## A stitched patch used for statuses and small tags in the prompt column.
func _pill(text: String, color: Color, font_size: int = 10) -> PanelContainer:
	return Widgets.patch(text, color, font_size)


func _is_pickable_actor(player: int, character_id: String) -> bool:
	if ui_stage != "SELECT" or state_is_empty():
		return false
	if player != int(game.state["active_player"]):
		return false
	for character in game.available_actors(player):
		if str(character["id"]) == character_id:
			return true
	return false


## True when a move is chosen and this card is one of its legal targets.
func _is_valid_target(player: int, character_id: String) -> bool:
	if ui_stage != "SELECT" or state_is_empty():
		return false
	if selected_actor_id.is_empty() or selected_move_id.is_empty():
		return false
	var active := int(game.state["active_player"])
	# Targets are looked up against the acting side; enemy moves return the
	# opposing team, so compare the owning side of this card too.
	var move := Moves.get_move(selected_move_id)
	var expected_player := active
	if move.get("target_mode", "") == Moves.TARGET_ENEMY:
		expected_player = 1 - active
	if player != expected_player:
		return false
	for character in game.valid_targets(active, selected_actor_id, selected_move_id):
		if str(character["id"]) == character_id:
			return true
	return false


## A click on the board either picks the acting character or, once a move is
## chosen, commits the action against the clicked target.
func _on_card_clicked(player: int, character_id: String) -> void:
	if _is_valid_target(player, character_id):
		_commit_board_action(character_id)
		return
	if _is_pickable_actor(player, character_id):
		if selected_actor_id != character_id:
			selected_actor_id = character_id
			# A new actor invalidates the previous move choice, since move
			# legality depends on the actor position.
			selected_move_id = ""
		_render()


## Pushes the board selection through the same OptionButton-backed path the
## rest of the interface and the smoke tests already use.
func _commit_board_action(target_id: String) -> void:
	if actor_select == null or move_select == null or target_select == null:
		return
	if not _select_by_metadata(actor_select, selected_actor_id):
		return
	if not _select_by_metadata(move_select, selected_move_id):
		return
	_refresh_action_controls()
	if not _select_by_metadata(target_select, target_id):
		return
	_submit_selected_action()


## The hidden controls live in the prompt column, so a prompt rebuild already
## queues them for deletion; this just drops the dangling references.
func _forget_action_model() -> void:
	actor_select = null
	move_select = null
	target_select = null
	submit_action_button = null
	move_help = null


## Frees any hidden controls that were built but not parented yet.
func _free_action_model() -> void:
	for control in [actor_select, move_select, target_select, submit_action_button, move_help]:
		if control != null and not control.is_inside_tree():
			control.free()
	_forget_action_model()


func _select_by_metadata(option: OptionButton, value: String) -> bool:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.selected = index
			return true
	return false


func _render_prompt() -> void:
	_clear_children(prompt_box)
	_forget_action_model()
	error_label.text = game.last_error
	error_label.visible = not error_label.text.is_empty()
	match ui_stage:
		"START":
			_render_start_prompt()
		"DIRECT_HOST_WAITING":
			_render_host_waiting_prompt()
		"DIRECT_HOST_PREPARING", "DIRECT_JOIN_PREPARING", "DIRECT_HOST_OFFER", "DIRECT_JOIN_ANSWER", "DIRECT_CONNECTING":
			_render_direct_connection_prompt()
		"DRAFT":
			_render_draft_prompt()
		"HANDOFF_DRAFT":
			_render_handoff_prompt("draft", "DRAFT")
		"PLACEMENT":
			_render_placement_prompt()
		"HANDOFF_PLACEMENT":
			_render_handoff_prompt("formation", "PLACEMENT")
		"SELECT":
			_render_select_prompt()
		"WAIT_ACTION":
			_render_wait_prompt("Waiting for the other player to choose an action")
		"WAIT_ROLL":
			_render_wait_prompt("Securing both hidden rolls")
		"HANDOFF_CLAIM":
			_render_handoff_prompt("private roll and claim", "CLAIM")
		"CLAIM":
			_render_claim_prompt()
		"WAIT_CLAIM":
			_render_wait_prompt("Claim locked. Waiting for the other player")
		"HANDOFF_CHALLENGE":
			_render_handoff_prompt("opponent claim and challenge choice", "CHALLENGE")
		"CHALLENGE":
			_render_challenge_prompt()
		"WAIT_CHALLENGE":
			_render_wait_prompt("Choice locked. Waiting for the other player")
		"WAIT_REVEAL":
			_render_wait_prompt("Verifying both committed rolls")
		"RECONNECTING":
			_render_reconnecting_prompt()
		"RESOLUTION":
			_render_resolution_prompt()
		"FINISHED":
			_render_finished_prompt()
		"FAILED":
			_render_failed_prompt()
		_:
			prompt_box.add_child(_label("Unknown interface state", 20, UiTheme.COLOR_DANGER))


## The start screen: a painted tournament banner over three paper notices, one
## per way to get into a match. There is no board and no claim record yet, so the
## whole page belongs to these.
func _render_start_prompt() -> void:
	var banner := PanelContainer.new()
	var banner_style := UiTheme.paper_style("secondary")
	banner_style.bg_color = UiTheme.COLOR_ACCENT
	banner_style.content_margin_top = 8
	banner_style.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", banner_style)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 12)
	banner.add_child(banner_row)
	banner_row.add_child(Widgets.label("⚅", 34, UiTheme.COLOR_INK))
	var banner_text := VBoxContainer.new()
	banner_text.add_theme_constant_override("separation", 0)
	banner_row.add_child(banner_text)
	banner_text.add_child(Widgets.label("READ THE ROLL. SELL THE LIE.", 22, UiTheme.COLOR_INK))
	banner_text.add_child(Widgets.label(
		"A weekend tournament settled with foam weapons and hidden dice.", 12, UiTheme.COLOR_INK,
	))
	prompt_box.add_child(banner)

	prompt_box.add_child(Widgets.wrapped_label(
		"Play on one device or connect two copies of the game. Online matches send gameplay directly between players and use commitments so neither player can change a roll, claim, or challenge after seeing the opponent's choice.",
		13, UiTheme.COLOR_INK,
	))

	# Three notices side by side, so every route into a match is visible at
	# 1280x720 without scrolling for it.
	var notices := HBoxContainer.new()
	notices.add_theme_constant_override("separation", 8)
	notices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_box.add_child(notices)
	notices.add_child(_hotseat_notice())
	notices.add_child(_lan_notice())
	notices.add_child(_internet_notice())


## One notice on the board: a heading, a short explanation, and its controls.
func _notice(title: String, explanation: String) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.paper_style("secondary")
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(Widgets.heading(title))
	var note := Widgets.wrapped_label(explanation, 11, UiTheme.COLOR_INK_MUTED)
	box.add_child(note)
	return [panel, box]


func _hotseat_notice() -> PanelContainer:
	var parts := _notice("Hot-seat", "One device, passed back and forth. Draft four from the roster of five, set the line, then play.")
	var box: VBoxContainer = parts[1]
	box.add_child(Widgets.filler())
	var start_button := _button("Start hot-seat match", true)
	start_button.pressed.connect(_start_match)
	box.add_child(start_button)
	var quick_button := _button("Quick match, preset crews", false)
	quick_button.tooltip_text = "Skips draft and placement and goes straight to an exchange."
	quick_button.pressed.connect(_start_quick_match)
	box.add_child(quick_button)
	return parts[0]


func _lan_notice() -> PanelContainer:
	var parts := _notice("Same network", "One machine or one LAN. Needs port forwarding to work over the internet.")
	var box: VBoxContainer = parts[1]
	box.add_child(Widgets.filler())
	var host_button := _button("Host a match", false)
	host_button.pressed.connect(_host_address)
	box.add_child(host_button)

	var address_input := LineEdit.new()
	address_input.placeholder_text = "127.0.0.1:8910"
	address_input.custom_minimum_size.y = 40
	address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(address_input)
	var join_button := _button("Join", false)
	join_button.pressed.connect(func(): _join_address(address_input.text))
	box.add_child(join_button)
	# Enter in the address field joins, which is the common case.
	address_input.text_submitted.connect(func(text: String): _join_address(text))
	return parts[0]


## The peer-to-peer path. It needs no port forwarding because the two clients
## discover a route themselves, at the cost of the players passing two codes
## back and forth by hand. That is the trade for having no server at all.
func _internet_notice() -> PanelContainer:
	var parts := _notice("Internet codes", "No port forwarding and no server. Send the codes to each other over chat.")
	var box: VBoxContainer = parts[1]
	box.add_child(Widgets.filler())
	var offer_button := _button("Create host offer", false)
	offer_button.pressed.connect(_host_online)
	box.add_child(offer_button)

	var offer_input := _code_input("Paste the host's offer code", 44)
	box.add_child(offer_input)
	var join_offer_button := _button("Join with offer", false)
	join_offer_button.pressed.connect(func(): _join_online(offer_input.text))
	box.add_child(join_offer_button)
	return parts[0]


## Shown to the hosting player while they wait for an opponent. It lists the
## addresses this machine can be reached on so they can pass one along.
func _render_host_waiting_prompt() -> void:
	prompt_box.add_child(_section_heading("Waiting for the other player"))
	prompt_box.add_child(_pill_row("LISTENING", UiTheme.COLOR_ACCENT))

	var addresses := DirectTransport.local_addresses()
	prompt_box.add_child(_label("Give the other player one of these:", 13, UiTheme.COLOR_INK))
	prompt_box.add_child(_address_row("Same machine", str(addresses["local"])))
	if not str(addresses["lan"]).is_empty():
		prompt_box.add_child(_address_row("Same network", str(addresses["lan"])))
	else:
		prompt_box.add_child(_label("No network address found; only same-machine play is available.", 11, UiTheme.COLOR_INK_MUTED))

	prompt_box.add_child(_label("To play over the internet, forward port %d on the router and share your public address." % int(addresses["port"]), 11, UiTheme.COLOR_INK_MUTED))

	var cancel := _button("Cancel", false)
	cancel.pressed.connect(_return_to_menu)
	prompt_box.add_child(cancel)


## One labelled address with a copy button beside it.
func _address_row(caption: String, address: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption_label := _label(caption, 11, UiTheme.COLOR_INK_MUTED)
	caption_label.custom_minimum_size.x = 110
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption_label)
	var value := _label(address, 17, UiTheme.COLOR_ACCENT_DARK)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_copy_button("Copy", address))
	return row


func _render_direct_connection_prompt() -> void:
	prompt_box.add_child(_section_heading("Direct peer connection"))
	prompt_box.add_child(_label(connection_status, 15, UiTheme.COLOR_INK))
	match ui_stage:
		"DIRECT_HOST_PREPARING", "DIRECT_JOIN_PREPARING":
			prompt_box.add_child(_label("Collecting connection details. This usually takes a few seconds.", 14, UiTheme.COLOR_INK_MUTED))
		"DIRECT_HOST_OFFER":
			prompt_box.add_child(_label("1. Send this offer only to the player joining you.", 14, UiTheme.COLOR_INK_MUTED))
			var offer_output := _code_output(game.manual_code)
			prompt_box.add_child(offer_output)
			prompt_box.add_child(_copy_button("Copy offer", game.manual_code))
			prompt_box.add_child(_label("2. Paste the answer they send back.", 14, UiTheme.COLOR_INK_MUTED))
			var answer_input := _code_input("Paste joiner's answer code")
			prompt_box.add_child(answer_input)
			var connect_button := _button("Connect with answer", true)
			connect_button.pressed.connect(func(): _accept_direct_answer(answer_input.text))
			prompt_box.add_child(connect_button)
		"DIRECT_JOIN_ANSWER":
			prompt_box.add_child(_label("Send this answer back to the host. Keep this window open while they paste it.", 14, UiTheme.COLOR_INK_MUTED))
			var answer_output := _code_output(game.manual_code)
			prompt_box.add_child(answer_output)
			prompt_box.add_child(_copy_button("Copy answer", game.manual_code))
		"DIRECT_CONNECTING":
			prompt_box.add_child(_label("The codes were accepted. Waiting for the peer channel to open.", 14, UiTheme.COLOR_INK_MUTED))
	prompt_box.add_child(_label("Connection codes include network address information. Share them only with your opponent.", 12, UiTheme.COLOR_INK_MUTED))
	var cancel := _button("Back to menu", false)
	cancel.pressed.connect(_return_to_menu)
	prompt_box.add_child(cancel)


## A small uppercase caption used to label a form field.
func _field_caption(text: String) -> Label:
	var label := _label(text.to_upper(), 11, UiTheme.COLOR_INK_MUTED)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## The private roll as a painted wooden d20 token, tabbed in the acting
## player's colour so a hot-seat player can see at a glance whose it is.
func _roll_face(roll: int, tint: Color) -> CenterContainer:
	var centre := CenterContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	centre.add_child(column)

	# The colour tab is a strip of cloth tape along the top of the token: it
	# marks whose roll this is without tinting the number itself.
	var tab := PanelContainer.new()
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = tint
	tab_style.corner_radius_top_left = UiTheme.RADIUS_CARD
	tab_style.corner_radius_top_right = UiTheme.RADIUS_CARD
	tab_style.set_border_width_all(2)
	tab_style.border_color = UiTheme.COLOR_INK
	tab_style.content_margin_left = 14
	tab_style.content_margin_right = 14
	tab_style.content_margin_top = 1
	tab_style.content_margin_bottom = 1
	tab.add_theme_stylebox_override("panel", tab_style)
	var tab_label := Widgets.label("YOUR ROLL", 10, UiTheme.ink_on(tint))
	tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(tab_label)
	column.add_child(tab)

	var face := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.COLOR_PAPER
	style.corner_radius_bottom_left = UiTheme.RADIUS_CARD
	style.corner_radius_bottom_right = UiTheme.RADIUS_CARD
	style.set_border_width_all(3)
	style.border_color = UiTheme.COLOR_INK
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 2
	style.content_margin_bottom = 6
	style.shadow_color = Color(UiTheme.COLOR_WOOD_DARK, UiTheme.SHADOW_OPACITY)
	style.shadow_size = 0
	style.shadow_offset = UiTheme.SHADOW_OFFSET
	face.add_theme_stylebox_override("panel", style)
	var value := Widgets.label(str(roll), 40, UiTheme.COLOR_INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.add_child(value)
	column.add_child(face)
	return centre


## One public claim card in the challenge comparison. The two sit side by side
## so the numbers can be read against each other without arithmetic.
func _claim_tile(caption: String, value: int, tint: Color) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.paper_style("raised")
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	# Ownership as a tape edge along the top, so neither card is tinted in a
	# colour that would read as an outcome.
	style.border_width_top = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	tile.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)
	var owner_row := HBoxContainer.new()
	owner_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(owner_row)
	owner_row.add_child(Widgets.patch(caption, tint, 9))
	var value_label := Widgets.label(str(value), 34, UiTheme.COLOR_INK)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value_label)
	return tile


## The full-width result sign painted for the end of a match.
func _banner(text: String, tint: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	var style := UiTheme.paper_style("raised")
	style.bg_color = tint
	style.set_border_width_all(3)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", style)
	var label := Widgets.label(text, 22, UiTheme.ink_on(tint))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(label)
	return banner


func _code_input(placeholder: String, height: int = 72) -> TextEdit:
	var input := TextEdit.new()
	input.placeholder_text = placeholder
	input.custom_minimum_size.y = height
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return input


func _code_output(code: String) -> TextEdit:
	var output := _code_input("")
	output.text = code
	output.editable = false
	return output


func _copy_button(label: String, value: String) -> Button:
	var button := _button(label, false)
	button.pressed.connect(func(): DisplayServer.clipboard_set(value))
	return button


func _render_wait_prompt(message: String) -> void:
	var waiting := _label(message, 21, UiTheme.COLOR_ACCENT)
	waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(waiting)
	prompt_box.add_child(_pill_row("WAITING", UiTheme.COLOR_ACCENT))
	if not state_is_empty():
		var active := int(game.state.get("active_player", -1))
		if active in [0, 1]:
			prompt_box.add_child(_label("%s is active." % _player_name(active), 14, UiTheme.COLOR_INK))
	prompt_box.add_child(_label(connection_status, 12, UiTheme.COLOR_INK_MUTED))


## Wraps a pill so it sits left-aligned on its own row instead of stretching.
func _pill_row(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_pill(text, color))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	return row


## Draft: pick four of the five, with every stat and both kit effects on screen.
##
## The spec makes this public information the whole game depends on, so the cards
## carry the full stat line rather than a name the player has to look up. E8.
func _render_draft_prompt() -> void:
	prompt_box.add_child(_section_heading("%s: pick the crew" % _player_name(decision_player)))
	prompt_box.add_child(Widgets.wrapped_label(
		"Four of the five come to the field. Both players see every stat and every kit effect, all match.",
		12, UiTheme.COLOR_INK_MUTED,
	))

	# A responsive grid rather than a list: five full cards stacked vertically
	# push the confirm button below the fold at 1280x720.
	var grid := GridContainer.new()
	grid.columns = 2 if _is_compact() else 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_box.add_child(grid)
	for character_id in Roster.character_ids():
		grid.add_child(_draft_card(str(character_id)))

	# The counter and the confirm sit on the pinned row beneath the grid, so both
	# stay visible however many cards the roster grows to.
	var footer: Control = prompt_footer if prompt_footer != null else HBoxContainer.new()
	if prompt_footer == null:
		(footer as HBoxContainer).add_theme_constant_override("separation", 10)
		prompt_box.add_child(footer)
	var chosen := draft_picks.size()
	footer.add_child(Widgets.patch(
		"%d OF 4 CHOSEN" % chosen,
		UiTheme.COLOR_SUCCESS if chosen == 4 else UiTheme.COLOR_INK_MUTED,
		12,
	))
	footer.add_child(Widgets.filler())
	var confirm := _button("Confirm the crew", true)
	confirm.disabled = chosen != 4
	confirm.pressed.connect(_submit_draft)
	footer.add_child(confirm)


## One roster entry as a togglable card: the face, the stat line, both kit
## effects, and whether this player has picked it.
func _draft_card(character_id: String) -> PanelContainer:
	var definition := Roster.definition(character_id)
	var picked := character_id in draft_picks

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.paper_style("raised" if picked else "secondary")
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if picked:
		# A picked card lifts and gains a stronger hard shadow, the way a card
		# pulled out of a pile sits proud of the ones still in it.
		style.set_border_width_all(3)
		style.border_color = UiTheme.COLOR_ACCENT_DARK
		style.shadow_offset = UiTheme.SHADOW_OFFSET * 1.6
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	header.add_child(Portrait.build(
		character_id, str(definition["display_name"]), _player_color(decision_player), 46,
	))
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	title.add_child(Widgets.label(str(definition["display_name"]), 16, UiTheme.COLOR_INK))
	title.add_child(Widgets.label("HP %d   ATK %+d   DEF %+d" % [
		int(definition["max_hp"]), int(definition["attack"]), int(definition["defence"]),
	], 11, UiTheme.COLOR_INK_MUTED))
	title.add_child(Widgets.label("DMG %d   INIT %d" % [
		int(definition["damage"]), int(definition["initiative"]),
	], 11, UiTheme.COLOR_INK_MUTED))
	if picked:
		# The clothespin marker: how a picked card is tagged on a real table.
		header.add_child(Widgets.stamp("🖈 PICKED", UiTheme.COLOR_ACCENT, 10))

	for description in Kits.effect_descriptions(character_id):
		var effect := Widgets.wrapped_label(
			"%s — %s" % [str(description["name"]), str(description["text"])],
			11, UiTheme.COLOR_INK_MUTED,
		)
		box.add_child(effect)

	var toggle := _button("Put back" if picked else "Pick", picked)
	# A fifth pick is refused rather than silently swapping one out, so the player
	# always knows which four they hold.
	toggle.disabled = not picked and draft_picks.size() >= 4
	if toggle.disabled:
		toggle.tooltip_text = "Four are already chosen. Put one back first."
	toggle.pressed.connect(func(): _toggle_draft_pick(character_id))
	box.add_child(toggle)
	return card


func _toggle_draft_pick(character_id: String) -> void:
	if character_id in draft_picks:
		draft_picks.erase(character_id)
	elif draft_picks.size() < 4:
		draft_picks.append(character_id)
	_render()


func _submit_draft() -> void:
	var result: Dictionary = game.submit_draft(decision_player, draft_picks)
	if not result["ok"]:
		error_label.text = result["error"]
		return
	draft_picks = []
	if decision_player == 0:
		decision_player = 1
		ui_stage = "HANDOFF_DRAFT"
	else:
		# Both drafts are in, so the reducer has moved the match to placement.
		decision_player = 0
		formation_order = game.state["teams"][0]["drafted_character_ids"].duplicate()
		ui_stage = "HANDOFF_PLACEMENT"
	_render()


## Placement: four physical slots on the line, back to front.
##
## The slots print what standing there costs, because the multiplier is the only
## reason the rank matters and asking a player to remember four percentages is
## the kind of bookkeeping this interface exists to remove.
func _render_placement_prompt() -> void:
	prompt_box.add_child(_section_heading("%s: set the line" % _player_name(decision_player)))
	prompt_box.add_child(Widgets.wrapped_label(
		"Back 1 → 4 front. The back rank takes the least damage; the front takes the most, and only positions 3 and 4 can throw a heavy attack.",
		12, UiTheme.COLOR_INK_MUTED,
	))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	prompt_box.add_child(list)
	for index in formation_order.size():
		list.add_child(_placement_row(index))

	var confirm := _button("Confirm the line", true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_submit_formation)
	if prompt_footer != null:
		prompt_footer.add_child(confirm)
	else:
		prompt_box.add_child(confirm)


## One slot on the line: its label, what it costs, who is standing in it, and
## the controls that swap them with a neighbour.
func _placement_row(index: int) -> PanelContainer:
	var character_id := str(formation_order[index])
	var definition := Roster.definition(character_id)
	var position := index + 1
	var is_front := position == 4
	var heavy_capable := position >= 3

	var row_panel := PanelContainer.new()
	var style := UiTheme.paper_style("secondary")
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	row_panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	var slot_name := "FRONT 4" if is_front else ("BACK 1" if position == 1 else str(position))
	row.add_child(Widgets.patch(slot_name, UiTheme.COLOR_ACCENT, 11))
	# The damage multiplier is printed on the slot itself, not looked up.
	row.add_child(Widgets.patch(
		"%d%% DAMAGE TAKEN" % CombatResolver.POSITION_DAMAGE_PERCENT[position],
		UiTheme.COLOR_WARNING if position >= 3 else UiTheme.COLOR_INFO,
		10,
	))

	row.add_child(Portrait.build(
		character_id, str(definition["display_name"]), _player_color(decision_player), 34,
	))
	var name_label := Widgets.label(str(definition["display_name"]), 14, UiTheme.COLOR_INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Heavy attack is the one move the line actually gates, so the slots that
	# allow it say so rather than leaving it to the move tooltip.
	if heavy_capable:
		var heavy := Widgets.patch("⚒ HEAVY OK", UiTheme.COLOR_SUCCESS, 9)
		heavy.tooltip_text = "Heavy attack\nOnly a character standing in position 3 or 4 can throw one."
		row.add_child(heavy)

	# Click-to-swap through the arrows, which keeps every move keyboard
	# reachable. Drag would be a nicer prop and is not a replacement for this.
	var up := _button("↑", false)
	up.custom_minimum_size = Vector2(40, 40)
	up.disabled = index == 0
	up.tooltip_text = "Swap with the rank behind."
	up.pressed.connect(func(): _move_in_formation(index, -1))
	row.add_child(up)
	var down := _button("↓", false)
	down.custom_minimum_size = Vector2(40, 40)
	down.disabled = index == formation_order.size() - 1
	down.tooltip_text = "Swap with the rank in front."
	down.pressed.connect(func(): _move_in_formation(index, 1))
	row.add_child(down)
	return row_panel


func _move_in_formation(index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= formation_order.size():
		return
	var moved = formation_order[index]
	formation_order[index] = formation_order[target]
	formation_order[target] = moved
	_render()


func _submit_formation() -> void:
	var result: Dictionary = game.submit_formation(decision_player, formation_order)
	if not result["ok"]:
		error_label.text = result["error"]
		return
	if decision_player == 0:
		decision_player = 1
		formation_order = game.state["teams"][1]["drafted_character_ids"].duplicate()
		ui_stage = "HANDOFF_PLACEMENT"
	else:
		# Both formations are in, so the match is live and the reducer has already
		# decided who acts first on initiative.
		formation_order = []
		decision_player = -1
		ui_stage = "SELECT"
	_render()


## The select decision. The props themselves live on the centre stage under the
## fighter who would use them, so this side of the screen carries the wording
## and the escape hatch rather than a second copy of the buttons.
func _render_select_prompt() -> void:
	var player := int(game.state["active_player"])

	# The OptionButtons remain the model the submit path reads from, but they
	# are no longer shown: the board and the move props drive them instead.
	_build_hidden_action_model(player)

	if selected_actor_id.is_empty():
		prompt_box.add_child(_timed_section_heading("%s: pick a fighter" % _player_name(player)))
		prompt_box.add_child(Widgets.wrapped_label(
			"Click one of your ready characters on the board. Their props appear on the table between the two crews.",
			13, UiTheme.COLOR_INK_MUTED,
		))
		return

	var actor: Dictionary = game.find_character(player, selected_actor_id)
	prompt_box.add_child(_timed_section_heading("%s is up" % str(actor.get("display_name", "Character"))))
	if selected_move_id.is_empty():
		prompt_box.add_child(Widgets.wrapped_label(
			"Pick one of the four props on the table, then click where it lands.",
			13, UiTheme.COLOR_INK_MUTED,
		))
	else:
		move_help = Widgets.wrapped_label(_move_description(selected_move_id), 13, UiTheme.COLOR_INK_MUTED)
		prompt_box.add_child(move_help)

	var change := _button("Pick someone else", false)
	change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	change.pressed.connect(func():
		selected_actor_id = ""
		selected_move_id = ""
		_render()
	)
	if prompt_footer != null:
		prompt_footer.add_child(change)
	else:
		prompt_box.add_child(change)


## Rebuilds the hidden OptionButtons that _submit_selected_action reads. Keeping
## them means the submit path, the online flow, and the smoke tests all continue
## to work unchanged while the board provides the input.
func _build_hidden_action_model(player: int) -> void:
	# These controls are never shown, but they are still Nodes: parent them to
	# the prompt column and hide them so they are freed with the rest of the
	# prompt instead of leaking on exit.
	_free_action_model()

	actor_select = OptionButton.new()
	for character in game.available_actors(player):
		actor_select.add_item(str(character["display_name"]))
		actor_select.set_item_metadata(actor_select.item_count - 1, character["id"])

	move_select = OptionButton.new()
	for move_id: String in MOVE_IDS:
		move_select.add_item(str(Moves.get_move(move_id)["display_name"]))
		move_select.set_item_metadata(move_select.item_count - 1, move_id)

	target_select = OptionButton.new()
	submit_action_button = Button.new()
	move_help = Label.new()
	for control in [actor_select, move_select, target_select, submit_action_button, move_help]:
		control.visible = false
		prompt_box.add_child(control)

	_select_by_metadata(actor_select, selected_actor_id)
	if not selected_move_id.is_empty():
		_select_by_metadata(move_select, selected_move_id)
	_refresh_action_controls()


## The four props on the table: light weapon, heavy weapon, shield, footwork.
##
## An illegal move stays on the table crossed with tape and printing its exact
## reason, rather than disappearing: a move that vanishes teaches the player
## nothing about why their character cannot make it.
func _build_move_buttons(player: int, actor: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for move_id: String in MOVE_IDS:
		grid.add_child(_move_prop(player, actor, move_id))
	return grid


## One prop card. Its blocked reason and its selected state are both printed,
## so neither depends on colour or on a hover.
func _move_prop(player: int, actor: Dictionary, move_id: String) -> Control:
	var move := Moves.get_move(move_id)
	var chosen: bool = move_id == selected_move_id
	var blocked := _move_block_reason(player, actor, move_id)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var button := Widgets.button("%s  %s" % [
		str(MOVE_PROPS.get(move_id, "")), str(move["display_name"]),
	], "primary" if chosen else "secondary")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = _move_description(move_id) if blocked.is_empty() else blocked
	column.add_child(button)

	if blocked.is_empty():
		var captured := move_id
		button.pressed.connect(func():
			selected_move_id = captured
			_render()
		)
	else:
		button.disabled = true
		# The tape across a blocked prop, and the reason spelled out under it.
		var tape := Widgets.rule(UiTheme.COLOR_DANGER, 3)
		tape.rotation = -0.02
		column.add_child(tape)
		column.add_child(Widgets.wrapped_label(blocked, 10, UiTheme.COLOR_DANGER))
	return column


## Why this actor cannot use this move right now, or "" when it is legal.
func _move_block_reason(player: int, actor: Dictionary, move_id: String) -> String:
	var move := Moves.get_move(move_id)
	var allowed: Array = move.get("allowed_positions", [])
	if not allowed.is_empty() and int(actor.get("position", 0)) not in allowed:
		return "Requires position %s. This character is too far back." % ", ".join(allowed.map(func(v): return str(v)))
	if game.valid_targets(player, str(actor["id"]), move_id).is_empty():
		return "No legal target for this move."
	return ""


## Tells the player where the chosen move can land.
func _build_target_hint(player: int) -> Control:
	var targets: Array = game.valid_targets(player, selected_actor_id, selected_move_id)
	if targets.is_empty():
		return _label("No legal target for this move.", 13, UiTheme.COLOR_DANGER)

	var move := Moves.get_move(selected_move_id)
	# A self-targeted move has nothing to click, so it is committed directly.
	if move.get("target_mode", "") == Moves.TARGET_SELF:
		var confirm := _button("Confirm %s" % str(move["display_name"]).to_lower(), true)
		confirm.pressed.connect(func(): _commit_board_action(str(targets[0]["id"])))
		return confirm

	var side := "an enemy" if move.get("target_mode", "") == Moves.TARGET_ENEMY else "an adjacent ally"
	return _pill_row("CLICK %s ON THE BOARD" % side.to_upper(), UiTheme.COLOR_ACCENT)


func _move_description(move_id: String) -> String:
	match move_id:
		"light_attack":
			return "Light attack: normal attack and damage values."
		"heavy_attack":
			return "Heavy attack: -4 attack roll, +8 damage. Requires position 3 or 4."
		"defensive_stance":
			return "Defensive stance: no attack. Gain +5 defence until this character's next turn."
		"swap":
			return "Swap: no attack. Exchange positions with an adjacent living ally."
	return ""


func _refresh_action_controls() -> void:
	if actor_select == null or move_select == null or target_select == null:
		return
	target_select.clear()
	if actor_select.item_count == 0 or move_select.item_count == 0:
		return
	var player := int(game.state["active_player"])
	var actor_id := str(actor_select.get_item_metadata(actor_select.selected))
	var move_id := str(move_select.get_item_metadata(move_select.selected))
	for character in game.valid_targets(player, actor_id, move_id):
		target_select.add_item("%s, position %d" % [character["display_name"], character["position"]])
		target_select.set_item_metadata(target_select.item_count - 1, character["id"])


func _submit_selected_action() -> void:
	if actor_select == null or actor_select.item_count == 0 or move_select.item_count == 0:
		return
	# Fall back to the first legal actor and move when nothing has been picked
	# on the board, so a direct submit still performs a legal action.
	if actor_select.selected < 0:
		actor_select.selected = 0
	if move_select.selected < 0:
		move_select.selected = 0
	if target_select.item_count == 0:
		_refresh_action_controls()
	if target_select.item_count == 0:
		return
	if target_select.selected < 0:
		target_select.selected = 0
	var actor_id := str(actor_select.get_item_metadata(actor_select.selected))
	var move_id := str(move_select.get_item_metadata(move_select.selected))
	var target_id := str(target_select.get_item_metadata(target_select.selected))
	var result: Dictionary = game.select_action(actor_id, move_id, target_id)
	if not result["ok"]:
		error_label.text = result["error"]
		return
	if online_mode:
		_render()
		return
	if game.state["phase"] == MatchState.PHASE_COMMIT:
		result = game.prepare_attack_exchange()
		if not result["ok"]:
			error_label.text = result["error"]
			return
		decision_player = 0
		ui_stage = "HANDOFF_CLAIM"
	else:
		result = game.resolve_non_attack_exchange()
		if not result["ok"]:
			error_label.text = result["error"]
			return
		_record_resolution()
		ui_stage = "RESOLUTION"
	_render()


func _render_handoff_prompt(subject: String, next_stage: String) -> void:
	prompt_box.add_child(_centered_label("\u2687", 30, UiTheme.COLOR_ACCENT_DARK))
	prompt_box.add_child(_centered_label("PASS THE DEVICE", 19, UiTheme.COLOR_ACCENT))
	var instruction := _centered_label("Give the screen to %s. The next view contains their %s." % [_player_name(decision_player), subject], 14, UiTheme.COLOR_INK)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(instruction)
	var ready := _button("I am %s" % _player_name(decision_player), true)
	ready.pressed.connect(func():
		ui_stage = next_stage
		_render()
	)
	prompt_box.add_child(ready)


## The attack or defence total a claimed value would produce, broken into the
## terms that make it up.
##
## Mirrors the reducer's own sum (CombatResolver.resolve_exchange plus the stance
## and exposure adjustments in MatchReducer) so the number a player reads here is
## the number the resolution will use. Everything it reads is public except the
## claimed value itself, which is either the player's own or already on the table.
func _side_total(player: int, claimed_value: int) -> Dictionary:
	var action: Dictionary = game.state["exchange"]["action"]
	var attacker_player := int(action["player"])
	var is_attacker := player == attacker_player
	var move := Moves.get_move(str(action["move_id"]))
	var character_id := str(action["actor_id"]) if is_attacker else str(action["target_id"])
	var character: Dictionary = game.find_character(player, character_id)
	if character.is_empty() or move.is_empty():
		return {}

	var terms := [["claim %d" % claimed_value, claimed_value]]
	var total := claimed_value
	var move_name := str(move["display_name"]).to_lower()
	if is_attacker:
		var attack_stat := int(character["attack"])
		terms.append(["Attack stat", attack_stat])
		total += attack_stat
		var attack_modifier := int(move["attack_modifier"])
		terms.append([move_name, attack_modifier])
		total += attack_modifier
	else:
		var defence_stat := int(character["defence"])
		terms.append(["Defence stat", defence_stat])
		total += defence_stat
		var defence_modifier := int(move["defence_modifier"])
		terms.append([move_name, defence_modifier])
		total += defence_modifier
		var counters: Dictionary = character["effect_counters"]
		if counters.get("defensive_stance_active", false):
			terms.append(["stance", 5])
			total += 5
		if counters.get("exposed_after_wrong_call", false):
			terms.append(["exposed", -5])
			total -= 5
	return {
		"is_attacker": is_attacker,
		"name": str(character["display_name"]),
		"total": total,
		"terms": _terms(terms),
	}


## One line of the total readout: "Attack: claim 14 + 6 Attack stat = 20".
func _total_line(summary: Dictionary) -> String:
	if summary.is_empty():
		return ""
	var role := "Attack" if bool(summary["is_attacker"]) else "Defence"
	return "%s: %s = %d" % [role, summary["terms"], summary["total"]]


## The private boast, played out on the centre stage: the acting player's own
## roll and the claim they build from it.
##
## Everything here is either public or this player's own, which is exactly what
## the commit-reveal protocol already lets them hold. Nothing about the
## opponent's roll or claim appears.
func _render_claim_stage(box: VBoxContainer) -> void:
	var action_player := int(game.state["exchange"]["action"]["player"])
	var role := "attack" if decision_player == action_player else "defence"
	var roll := int(game.true_rolls[decision_player])

	box.add_child(Widgets.centered_label(
		"%s: your private %s roll. Nobody else has seen it." % [_player_name(decision_player), role],
		12, UiTheme.COLOR_CARDBOARD,
	))
	box.add_child(_roll_face(roll, _player_color(decision_player)))

	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UiTheme.paper_style("raised"))
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sheet.custom_minimum_size.x = 460
	box.add_child(sheet)
	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 5)
	sheet.add_child(sheet_box)

	var claim_row := HBoxContainer.new()
	claim_row.add_theme_constant_override("separation", 8)
	claim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sheet_box.add_child(claim_row)
	claim_row.add_child(_field_caption("CLAIM"))
	# A SpinBox rather than a bespoke stack of number cards: rotating cards would
	# look the part but would cost the keyboard access the arrows already give.
	var claim_input := SpinBox.new()
	claim_input.min_value = roll
	claim_input.max_value = 20
	claim_input.step = 1
	claim_input.value = roll
	claim_input.custom_minimum_size = Vector2(110, 40)
	claim_input.add_theme_font_size_override("font_size", 20)
	claim_row.add_child(claim_input)
	# The padding is the whole decision, so it is printed as its own figure
	# rather than left for the player to subtract.
	var padding_patch := Widgets.patch("HONEST", UiTheme.COLOR_SUCCESS, 12)
	claim_row.add_child(padding_patch)

	# The crooked orange underline that marks a padded claim. It is drawn only on
	# this private view: a public tell would hand the bluff to the opponent.
	var tell := Widgets.rule(UiTheme.COLOR_ACCENT, 3)
	tell.custom_minimum_size.x = 200
	tell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tell.rotation = 0.012
	tell.visible = false
	sheet_box.add_child(tell)

	sheet_box.add_child(Widgets.label("IF THIS CLAIM STANDS", 11, UiTheme.COLOR_INK_MUTED))
	var total_label := Widgets.wrapped_label("", 12, UiTheme.COLOR_INK)
	sheet_box.add_child(total_label)
	sheet_box.add_child(Widgets.rule(UiTheme.COLOR_CARDBOARD, 1))
	sheet_box.add_child(Widgets.label("IF CHALLENGED AND CAUGHT", 11, UiTheme.COLOR_DANGER))
	var caught_label := Widgets.wrapped_label("", 12, UiTheme.COLOR_INK)
	sheet_box.add_child(caught_label)
	var kit_note := Widgets.wrapped_label("", 11, UiTheme.COLOR_INK_MUTED)
	sheet_box.add_child(kit_note)

	var claiming_id := str(game.state["exchange"]["action"]["actor_id"]) 		if decision_player == action_player else str(game.state["exchange"]["action"]["target_id"])
	var kit_line := _padding_kit_note(decision_player, claiming_id)

	var refresh := func(claim: int) -> void:
		var padding := claim - roll
		total_label.text = _total_line(_side_total(decision_player, claim))
		if padding > 0:
			padding_patch.get_child(0).text = "PADDED +%d" % padding
			padding_patch.add_theme_stylebox_override("panel", UiTheme.patch_style(UiTheme.COLOR_ACCENT))
			tell.visible = true
			# The caught branch is the same sum with the true roll in place of
			# the claim, so a player can price the bluff before making it.
			caught_label.text = "%s, and %d padding damage before kits." % [
				_total_line(_side_total(decision_player, roll)), padding,
			]
			kit_note.text = kit_line
		else:
			padding_patch.get_child(0).text = "HONEST"
			padding_patch.add_theme_stylebox_override("panel", UiTheme.patch_style(UiTheme.COLOR_SUCCESS))
			tell.visible = false
			caught_label.text = "An honest claim cannot be caught. A challenge against it is a wrong call."
			kit_note.text = ""
	refresh.call(roll)
	claim_input.value_changed.connect(func(value: float): refresh.call(int(value)))

	# The stage holds the decision; the pinned footer holds the commit, so the
	# control that ends the phase can never scroll away.
	var submit := _button("Lock in the boast", true)
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(func(): _submit_claim(int(claim_input.value)))
	if prompt_footer != null:
		prompt_footer.add_child(submit)
	else:
		box.add_child(submit)


## The wording beside the boast. The roll, the input, and both branches live on
## the stage, so this side carries only the framing.
func _render_claim_prompt() -> void:
	prompt_box.add_child(_timed_section_heading("%s: make your boast" % _player_name(decision_player)))
	prompt_box.add_child(Widgets.wrapped_label(
		"Claim your true roll, or pad it up to 20. A padded claim that goes unchallenged locks in and counts in full; one that is caught costs you the padding as damage.",
		13, UiTheme.COLOR_INK_MUTED,
	))


## The kit text that bears on what a caught bluff would cost this character.
## Read from Kits rather than restated, so a rewritten effect cannot leave a
## stale promise on the claim screen.
func _padding_kit_note(player: int, character_id: String) -> String:
	var character: Dictionary = game.find_character(player, character_id)
	if character.is_empty():
		return ""
	var notes := PackedStringArray()
	for description in Kits.effect_descriptions(character_id):
		if str(description["effect"]) in CHALLENGE_RELEVANT_EFFECTS:
			notes.append("%s — %s" % [str(description["name"]), str(description["text"])])
	return "\n".join(notes)


func _submit_claim(value: int) -> void:
	var result: Dictionary = game.submit_claim(decision_player, value)
	if not result["ok"]:
		error_label.text = result["error"]
		return
	if online_mode:
		_render()
		return
	if decision_player == 0:
		decision_player = 1
		ui_stage = "HANDOFF_CLAIM"
	else:
		decision_player = 0
		ui_stage = "HANDOFF_CHALLENGE"
	_render()


## The call: both claims flipped face up, both risk branches side by side, and
## the two actions pinned to the bottom so neither can leave the screen.
func _render_challenge_prompt() -> void:
	var opponent := 1 - decision_player
	var opponent_claim := int(game.state["exchange"]["claims"][opponent]["value"])
	var own_claim := int(game.state["exchange"]["claims"][decision_player]["value"])
	prompt_box.add_child(_timed_section_heading("%s: call their bluff" % _player_name(decision_player)))

	# Both public claim cards flip into the centre together, so neither player
	# reads the other's number first.
	var claims := HBoxContainer.new()
	claims.add_theme_constant_override("separation", 8)
	prompt_box.add_child(claims)
	claims.add_child(_claim_tile("%s BOASTED" % _player_name(opponent).to_upper(), opponent_claim, _player_color(opponent)))
	claims.add_child(_claim_tile("YOU BOASTED", own_claim, _player_color(decision_player)))

	# Claims are not comparable on their own: the stats and move modifiers decide
	# the exchange, so the totals both claims would produce are spelled out here.
	prompt_box.add_child(_standing_totals(decision_player, own_claim, opponent, opponent_claim))

	prompt_box.add_child(Widgets.wrapped_label(
		"Challenge if you think their claim is higher than their true roll. Their roll stays hidden until the reveal, so both branches are priced below.",
		12, UiTheme.COLOR_INK_MUTED,
	))
	prompt_box.add_child(_challenge_preview(decision_player))

	# LET IT STAND and CHALLENGE stay on screen at all times: they go in the
	# pinned footer beneath the prompt scroll, never inside it.
	var buttons := prompt_footer if prompt_footer != null else HBoxContainer.new()
	if prompt_footer == null:
		prompt_box.add_child(buttons)

	var pass_button := _button("LET IT STAND", false)
	pass_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_button.tooltip_text = "Pass\nThe claim goes unchallenged. A padded claim then locks in and counts in full."
	pass_button.pressed.connect(func(): _submit_challenge(false))
	buttons.add_child(pass_button)

	# The red rubber stamp. It is the loudest control on the screen because it is
	# the one that can cost the player the exchange outright.
	var challenge_button := Widgets.button("CHALLENGE", "stamp")
	challenge_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	challenge_button.tooltip_text = "Challenge\nCall the claim a bluff. Correct, and their padding becomes damage. Wrong, and their claim stands with a penalty against you."
	challenge_button.pressed.connect(func(): _submit_challenge(true))
	buttons.add_child(challenge_button)


## The totals both claims resolve to if neither is challenged, and the margin
## that follows from them.
func _standing_totals(player: int, own_claim: int, opponent: int, opponent_claim: int) -> PanelContainer:
	var panel := _surface(UiTheme.COLOR_PAPER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	box.add_child(Widgets.label("IF BOTH CLAIMS STAND", 11, UiTheme.COLOR_INK_MUTED))

	var own_summary := _side_total(player, own_claim)
	var opponent_summary := _side_total(opponent, opponent_claim)
	for entry in [
		{"summary": opponent_summary, "who": _player_name(opponent)},
		{"summary": own_summary, "who": "You"},
	]:
		var summary: Dictionary = entry["summary"]
		if summary.is_empty():
			continue
		box.add_child(Widgets.wrapped_label(
			"%s — %s" % [str(entry["who"]), _total_line(summary)], 12, UiTheme.COLOR_INK,
		))
	if not own_summary.is_empty() and not opponent_summary.is_empty():
		var attack_summary: Dictionary = own_summary if bool(own_summary["is_attacker"]) else opponent_summary
		var defence_summary: Dictionary = opponent_summary if bool(own_summary["is_attacker"]) else own_summary
		var margin := int(attack_summary["total"]) - int(defence_summary["total"])
		var verdict := "the attack hits for +%d margin" % margin if margin > 0 else "the attack is defended"
		box.add_child(Widgets.wrapped_label("Margin: %d - %d = %d, so %s." % [
			int(attack_summary["total"]), int(defence_summary["total"]), margin, verdict,
		], 12, UiTheme.COLOR_ACCENT_DARK))
	return panel


## What a challenge would actually do, spelled out before the decision.
##
## The opponent's true roll is not known yet and must not be, so the panel cannot
## print one number. It prints the two branches instead, as a pair of cards a
## player can read against each other: what happens if they were bluffing, and
## what happens if they were honest. Everything in it comes from public state
## plus this player's own roll, which is the same information the commit-reveal
## protocol already allows them to hold.
func _challenge_preview(player: int) -> PanelContainer:
	var opponent := 1 - player
	var action: Dictionary = game.state["exchange"]["action"]
	var attacker_player := int(action["player"])
	var challenging_the_attack := opponent == attacker_player

	var panel := _surface(UiTheme.COLOR_PAPER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var branches: BoxContainer = VBoxContainer.new() if _is_compact() else HBoxContainer.new()
	branches.add_theme_constant_override("separation", 6)
	box.add_child(branches)
	branches.add_child(_branch_card(
		"IF THEY LIED", "CORRECT CALL", UiTheme.COLOR_SUCCESS,
		_challenge_branch_lines(player, true, challenging_the_attack),
	))
	branches.add_child(_branch_card(
		"IF THEY WERE HONEST", "WRONG CALL", UiTheme.COLOR_DANGER,
		_challenge_branch_lines(player, false, challenging_the_attack),
	))

	# Anything already on the board that changes these numbers is named here, so a
	# player never has to remember which effects are live.
	var modifiers := _challenge_modifier_lines(player)
	if not modifiers.is_empty():
		box.add_child(Widgets.rule(UiTheme.COLOR_CARDBOARD, 1))
		box.add_child(Widgets.label("IN PLAY THIS EXCHANGE", 11, UiTheme.COLOR_INK_MUTED))
		for line in modifiers:
			box.add_child(Widgets.wrapped_label(line, 11, UiTheme.COLOR_INK_MUTED))
	return panel


## One consequence card: the branch heading, its stamped verdict, and the lines
## that say what actually happens to whom.
func _branch_card(heading: String, verdict: String, tint: Color, lines: PackedStringArray) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.paper_style("secondary")
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	style.set_border_width_all(2)
	style.border_color = tint
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	head.add_child(Widgets.label(heading, 10, UiTheme.COLOR_INK_MUTED))
	head.add_child(Widgets.filler())
	head.add_child(Widgets.stamp(verdict, tint, 10))

	for line in lines:
		box.add_child(Widgets.wrapped_label(line, 12, UiTheme.COLOR_INK))
	return card


## The outcome lines for one branch of the challenge decision.
func _challenge_branch_lines(player: int, they_bluffed: bool, challenging_the_attack: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var opponent := 1 - player
	var opponent_name := _player_name(opponent)
	var opponent_claim := int(game.state["exchange"]["claims"][opponent]["value"])

	if they_bluffed:
		if challenging_the_attack:
			lines.append("• The attack is cancelled and deals no damage.")
			lines.append("• %s takes their padding as damage, ignoring position." % opponent_name)
		else:
			lines.append("• Their defence drops from %d to their true roll." % opponent_claim)
			# The true roll is hidden, so the useful number is the roll at which
			# their defence still holds: everything below it lets the attack through.
			var attack_summary := _side_total(player, int(game.state["exchange"]["claims"][player]["value"]))
			var defence_summary := _side_total(opponent, opponent_claim)
			if not attack_summary.is_empty() and not defence_summary.is_empty():
				# Their defence holds when true roll r satisfies
				# attack_total - (defence_total - claim + r) <= 0.
				var needed := opponent_claim + int(attack_summary["total"]) - int(defence_summary["total"])
				if needed > 20:
					lines.append("• Your attack of %d gets through on any roll they could have." % int(attack_summary["total"]))
				elif needed <= 1:
					lines.append("• Their defence holds on any roll, even a 1.")
				else:
					lines.append("• Your attack of %d still gets through unless they rolled %d or better." % [
						int(attack_summary["total"]), needed,
					])
			lines.append("• %s takes their padding as damage, ignoring position." % opponent_name)
			lines.append("• If your attack still deals nothing, they are left EXPOSED (-5 defence next time).")
		lines.append("• Their kit may reduce or move that padding damage.")
	else:
		if challenging_the_attack:
			lines.append("• Their claim of %d stands in full." % opponent_claim)
			lines.append("• The damage they deal you is doubled.")
		else:
			lines.append("• Their claim of %d stands in full." % opponent_claim)
			lines.append("• The damage you deal them is halved.")
		lines.append("• If the attack deals nothing either way, you are left EXPOSED (-5 defence next time).")
	return lines


## Live effects that bear on this challenge: stance, exposure, claim caps, and the
## kit effects that change what a caught bluff costs.
func _challenge_modifier_lines(player: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var action: Dictionary = game.state["exchange"]["action"]
	var attacker_player := int(action["player"])
	var attacker: Dictionary = game.find_character(attacker_player, str(action["actor_id"]))
	var defender: Dictionary = game.find_character(1 - attacker_player, str(action["target_id"]))

	var sides := [
		{"character": attacker, "owner": attacker_player},
		{"character": defender, "owner": 1 - attacker_player},
	]
	for side in sides:
		var character: Dictionary = side["character"]
		if character.is_empty():
			continue
		var owner := int(side["owner"])
		var who := "You" if owner == player else _player_name(owner)
		var name := str(character["display_name"])
		var counters: Dictionary = character["effect_counters"]
		if counters.get("defensive_stance_active", false):
			lines.append("%s: %s is in a defensive stance, +5 defence." % [who, name])
		if counters.get("exposed_after_wrong_call", false):
			lines.append("%s: %s is EXPOSED, -5 defence this exchange." % [who, name])
		if int(counters.get(Kits.COUNTER_AUDIT_CAP, 20)) < 20:
			lines.append("%s: %s is capped at a claim of %d." % [who, name, int(counters[Kits.COUNTER_AUDIT_CAP])])
		# Only the kit effects that change what this challenge is worth. Matched on
		# the effect constant rather than the display name so renaming the public
		# text cannot silently drop an effect from the panel.
		for description in Kits.effect_descriptions(str(character["id"])):
			if str(description["effect"]) in CHALLENGE_RELEVANT_EFFECTS:
				lines.append("%s: %s — %s" % [who, str(description["name"]), str(description["text"])])
	return lines


func _submit_challenge(challenge: bool) -> void:
	var result: Dictionary = game.submit_challenge(decision_player, challenge)
	if not result["ok"]:
		error_label.text = result["error"]
		return
	if online_mode:
		_render()
		return
	if decision_player == 0:
		decision_player = 1
		ui_stage = "HANDOFF_CHALLENGE"
	else:
		result = game.resolve_attack_exchange()
		if not result["ok"]:
			error_label.text = result["error"]
			return
		_record_resolution()
		ui_stage = "RESOLUTION"
	_render()


## The reconnection window, with the time the dropped player has left (D6).
func _render_reconnecting_prompt() -> void:
	prompt_box.add_child(_section_heading("Waiting for the other player"))
	var explanation := _label(
		"They lost the connection. The match is held exactly where it stopped until they return. If they do not come back in time, the match is yours.",
		14, UiTheme.COLOR_INK,
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(explanation)
	var remaining := "" if reconnect_seconds < 0 else "%ds left to reconnect" % reconnect_seconds
	reconnect_label = _label(remaining, 16, UiTheme.COLOR_ACCENT)
	prompt_box.add_child(reconnect_label)
	var leave := _button("Leave the match", false)
	leave.pressed.connect(_return_to_menu)
	prompt_box.add_child(leave)


## The reveal and the settled result.
##
## The sequence plays over the same numbers the text breakdown prints, so the
## full arithmetic is on screen the moment it settles and nothing is only ever
## visible mid-animation.
func _render_resolution_prompt() -> void:
	var resolution: Dictionary = game.state["last_resolution"]
	prompt_box.add_child(_section_heading("Settle the hit"))
	# Nothing has resolved yet: an online state can reach this stage before the
	# resolution does, and the reveal has nothing to play.
	if resolution.is_empty():
		prompt_box.add_child(Widgets.wrapped_label(
			"Waiting for the exchange to settle.", 13, UiTheme.COLOR_INK_MUTED,
		))
		return

	var sequence := ResolutionSequence.new()
	prompt_box.add_child(sequence)

	# The next action is built now but stays disabled until the sequence settles,
	# so a click meant to skip the reveal cannot fall through onto it.
	var next_button := _resolution_next_button()
	var skip_button := _button("Skip animation", false)

	sequence.settled.connect(func():
		next_button.disabled = false
		skip_button.visible = false
		# The full breakdown lands with the settled view, so the player reads the
		# result rather than remembering the animation.
		var details := Widgets.wrapped_label(_format_resolution(resolution), 13, UiTheme.COLOR_INK)
		sequence.add_child(details)
		_render_resolution_footer(resolution)
	)
	# Both controls go in the pinned footer, so a long breakdown can never scroll
	# the next action away, and they are parented before the sequence runs so
	# nothing is left unattached if it settles at once under reduced motion.
	var footer: Control = prompt_footer if prompt_footer != null else prompt_box
	skip_button.pressed.connect(sequence.skip)
	skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(skip_button)
	footer.add_child(next_button)
	next_button.disabled = true
	sequence.play(_resolution_beats(sequence, resolution))


## The beats of one reveal, built entirely from public `last_resolution` fields.
func _resolution_beats(sequence: ResolutionSequence, resolution: Dictionary) -> Array:
	var beats: Array = []
	if resolution.get("non_attack", false):
		# A move with no exchange has nothing to reveal, so it settles in one
		# beat rather than pretending to hold suspense.
		beats.append(sequence.beat(ResolutionSequence.BEAT_DAMAGE, func():
			sequence.add_line(_format_resolution(resolution), 14)
		))
		return beats

	var attacker_player := int(resolution["attacker_player"])
	var defender_player := int(resolution["defender_player"])

	# 1-3: the true rolls come out from behind each claim, and each side is
	# stamped with how its claim settled.
	beats.append(sequence.beat(ResolutionSequence.BEAT_ROLLS, func():
		sequence.add_stamp_row(
			_character_name(attacker_player, str(resolution["actor_id"])),
			int(resolution["attack"]["claim"]),
			int(resolution["attack"]["true_roll"]),
			str(resolution["attack"]["outcome"]),
		)
	))
	beats.append(sequence.beat(ResolutionSequence.BEAT_STAMP, func():
		sequence.add_stamp_row(
			_character_name(defender_player, str(resolution["target_id"])),
			int(resolution["defence"]["claim"]),
			int(resolution["defence"]["true_roll"]),
			str(resolution["defence"]["outcome"]),
		)
	))

	# 4-7: the totals assemble, then the margin, then the branch the exchange
	# actually took.
	if resolution["miss_reason"] == "ATTACK_CAUGHT":
		beats.append(sequence.beat(ResolutionSequence.BEAT_TOTALS, func():
			sequence.add_line("The attack rope snaps: a caught bluff cancels it outright.", 13, UiTheme.COLOR_DANGER)
		))
	else:
		beats.append(sequence.beat(ResolutionSequence.BEAT_TOTALS, func():
			sequence.add_line("Attack %d  vs  Defence %d" % [
				int(resolution["effective_attack"]), int(resolution["effective_defence"]),
			], 15)
		))
		beats.append(sequence.beat(ResolutionSequence.BEAT_TOTALS, func():
			var margin := int(resolution["margin"])
			if bool(resolution["hit"]):
				sequence.add_line("Margin %+d — it lands." % margin, 14, UiTheme.COLOR_DANGER)
			else:
				sequence.add_line("Margin %+d — the shield holds." % margin, 14, UiTheme.COLOR_INFO)
		))

	# 8-9: every HP change, attributed separately to its own cause so a player
	# can tell hit damage from padding damage from a reflection.
	var damages := [
		["hit_damage", "hit on %s" % _character_name(defender_player, str(resolution["target_id"])), UiTheme.COLOR_DANGER],
		["attacker_self_damage", "padding damage to the attacker", UiTheme.COLOR_WARNING],
		["defender_self_damage", "padding damage to the defender", UiTheme.COLOR_WARNING],
		["attacker_reflected_damage", "reflected back at the attacker", UiTheme.COLOR_INFO],
		["defender_reflected_damage", "reflected back at the defender", UiTheme.COLOR_INFO],
	]
	for entry in damages:
		var amount := int(resolution.get(str(entry[0]), 0))
		if amount <= 0:
			continue
		var caption := str(entry[1])
		var color: Color = entry[2]
		beats.append(sequence.beat(ResolutionSequence.BEAT_DAMAGE, func():
			sequence.add_damage_row(caption, amount, color)
		))

	# 10: each kit patch is named as its numeric change appears, and pulsed on
	# the card it belongs to, so a modified figure is never unexplained.
	for note in resolution.get("kit_effects", []):
		var effect := str(note["effect"])
		var text := "%s: %s" % [_effect_name(effect), _effect_detail_text(note)]
		beats.append(sequence.beat(ResolutionSequence.BEAT_DAMAGE, func():
			sequence.add_line(text, 12, UiTheme.COLOR_ACCENT_DARK)
			_pulse_kit_patch(effect)
		))
	return beats


## Draws attention to a kit patch on whichever card carries it. Best effort: a
## card that has since been rebuilt simply does not pulse, which costs nothing
## because the effect is also named in the sequence text.
func _pulse_kit_patch(effect: String) -> void:
	for player in 2:
		var roster: TeamRoster = rosters[player]
		if roster == null or not is_instance_valid(roster):
			continue
		for character in game.state["teams"][player]["characters"]:
			var card: CharacterCard = roster.card_for(str(character["id"]))
			if card != null and is_instance_valid(card):
				card.pulse_effect(effect)


## The winner banner or the continue control, added once the reveal settles.
func _render_resolution_footer(resolution: Dictionary) -> void:
	if game.state["status"] != MatchState.STATUS_FINISHED:
		return
	var winner := int(game.state["winner_player"])
	prompt_box.add_child(_banner(
		"DRAW" if winner < 0 else "%s WINS" % _player_name(winner).to_upper(),
		UiTheme.COLOR_ACCENT if winner < 0 else _player_color(winner),
	))


## The control that leaves the resolution. Held disabled until the reveal
## settles, so an input meant to fast-forward cannot advance the match.
func _resolution_next_button() -> Button:
	if game.state["status"] == MatchState.STATUS_FINISHED:
		var restart := _button("Back to menu" if online_mode else "Start a new match", true)
		restart.pressed.connect(_return_to_menu if online_mode else _start_match)
		return restart
	var continue_button := _button("Next fighter", true)
	if online_mode:
		continue_button.pressed.connect(func(): game.continue_after_resolution())
	else:
		continue_button.pressed.connect(func():
			ui_stage = "SELECT"
			_render()
		)
	return continue_button


func _render_finished_prompt() -> void:
	prompt_box.add_child(_section_heading("Match complete"))
	var winner := int(game.state.get("winner_player", -1))
	prompt_box.add_child(_banner(
		"DRAW" if winner < 0 else "%s WINS" % _player_name(winner).to_upper(),
		UiTheme.COLOR_ACCENT if winner < 0 else _player_color(winner)
	))
	if not connection_status.is_empty():
		prompt_box.add_child(_label(connection_status, 12, UiTheme.COLOR_INK_MUTED))
	var back := _button("Back to menu", true)
	back.pressed.connect(_return_to_menu)
	prompt_box.add_child(back)


func _render_failed_prompt() -> void:
	prompt_box.add_child(_section_heading("Online match stopped"))
	prompt_box.add_child(_pill_row("DISCONNECTED", UiTheme.COLOR_DANGER))
	var message: String = game.last_error if game != null else connection_status
	var details := _label(message, 14, UiTheme.COLOR_INK)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(details)
	var back := _button("Back to menu", true)
	back.pressed.connect(_return_to_menu)
	prompt_box.add_child(back)


func _format_resolution(resolution: Dictionary) -> String:
	if resolution.get("non_attack", false):
		if resolution["summary"] == "DEFENSIVE_STANCE_APPLIED":
			return "%s entered defensive stance and gains +5 defence until their next turn." % _character_name(int(resolution["attacker_player"]), str(resolution["actor_id"]))
		return "%s swapped positions with %s." % [
			_character_name(int(resolution["attacker_player"]), str(resolution["actor_id"])),
			_character_name(int(resolution["attacker_player"]), str(resolution["target_id"])),
		]

	var attacker_player := int(resolution["attacker_player"])
	var defender_player := int(resolution["defender_player"])
	var lines := PackedStringArray()
	lines.append("%s rolled %d, claimed %d: %s." % [
		_player_name(attacker_player), resolution["attack"]["true_roll"], resolution["attack"]["claim"], _outcome_name(resolution["attack"]["outcome"]),
	])
	lines.append("%s rolled %d, claimed %d: %s." % [
		_player_name(defender_player), resolution["defence"]["true_roll"], resolution["defence"]["claim"], _outcome_name(resolution["defence"]["outcome"]),
	])
	if resolution["miss_reason"] == "ATTACK_CAUGHT":
		lines.append("The attack was cancelled.")
	else:
		lines.append("")
		lines.append_array(_damage_breakdown(resolution))
	if int(resolution["attacker_self_damage"]) > 0:
		lines.append("The attacker took %d padding damage." % resolution["attacker_self_damage"])
	if int(resolution["defender_self_damage"]) > 0:
		lines.append("The defender took %d padding damage." % resolution["defender_self_damage"])
	if int(resolution.get("attacker_reflected_damage", 0)) > 0:
		lines.append("The attacker took %d reflected damage." % resolution["attacker_reflected_damage"])
	if int(resolution.get("defender_reflected_damage", 0)) > 0:
		lines.append("The defender took %d reflected damage." % resolution["defender_reflected_damage"])

	# Name every kit effect that fired, so a changed number is never unexplained.
	for note in resolution.get("kit_effects", []):
		lines.append("%s: %s" % [_effect_name(str(note["effect"])), _effect_detail_text(note)])
	return "\n".join(lines)


## The damage calculation written out step by step, each line showing the numbers
## that went in as well as the result. A player who disagrees with a damage figure
## should be able to find the exact step they disagree with.
func _damage_breakdown(resolution: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var attack: Dictionary = resolution["attack"]
	var defence: Dictionary = resolution["defence"]
	var defender := _character_name(int(resolution["defender_player"]), str(resolution["target_id"]))

	# Step 1: the two effective values, each shown as its own sum.
	var attack_terms := _terms([
		["roll %d" % attack["resolved_value"], int(attack["resolved_value"])],
		["Attack stat", int(resolution["effective_attack"]) - int(attack["resolved_value"]) - int(resolution.get("move_attack_modifier", 0))],
		["move", int(resolution.get("move_attack_modifier", 0))],
	])
	lines.append("Attack:  %s = %d" % [attack_terms, resolution["effective_attack"]])

	var stance := int(resolution.get("stance_defence_bonus", 0))
	var exposure := int(resolution.get("exposure_penalty", 0))
	var defence_terms := _terms([
		["roll %d" % defence["resolved_value"], int(defence["resolved_value"])],
		["Defence stat", int(resolution["effective_defence"]) - int(defence["resolved_value"]) - stance + exposure],
		["stance", stance],
		["exposed", -exposure],
	])
	lines.append("Defence: %s = %d" % [defence_terms, resolution["effective_defence"]])
	lines.append("Margin:  %d - %d = %d" % [
		resolution["effective_attack"], resolution["effective_defence"], resolution["margin"],
	])

	if not bool(resolution["hit"]):
		lines.append("Margin is not above zero, so the attack missed.")
		return lines

	# Step 2: base damage, naming why the margin bonus is present or missing.
	var damage_stat := int(resolution["unscaled_damage"]) - int(resolution["margin_bonus"])
	if int(resolution["margin_bonus"]) > 0:
		lines.append("Damage:  %d base + %d margin = %d" % [
			damage_stat, resolution["margin_bonus"], resolution["unscaled_damage"],
		])
	else:
		lines.append("Damage:  %d base, no margin bonus = %d" % [damage_stat, resolution["unscaled_damage"]])

	# Step 3: position scaling, which is where the rounding happens.
	lines.append("Position %d: %d x %d%% = %d" % [
		_target_position(resolution),
		resolution["unscaled_damage"],
		resolution["position_damage_percent"],
		resolution["scaled_damage"],
	])

	# Step 4 onward: every multiplier that moved the number after scaling.
	var running := int(resolution["scaled_damage"])
	if int(resolution.get("attack_damage_multiplier", 1)) != 1:
		var doubled := running * int(resolution["attack_damage_multiplier"])
		lines.append("Wrong call against an honest attack: %d x2 = %d" % [running, doubled])
		running = doubled
	if int(resolution.get("defence_damage_divisor", 1)) != 1:
		var halved := floori(float(running) / float(int(resolution["defence_damage_divisor"])))
		lines.append("Wrong call against an honest defence: %d / 2 = %d" % [running, halved])
		running = halved
	if int(resolution.get("kit_damage_multiplier", 1)) != 1:
		var boosted := running * int(resolution["kit_damage_multiplier"])
		lines.append("All In: %d x%d = %d" % [running, resolution["kit_damage_multiplier"], boosted])
		running = boosted
	if int(resolution.get("drag_extra_damage", 0)) > 0:
		var dragged := running + int(resolution["drag_extra_damage"])
		lines.append("Drag against a front target: %d + %d = %d" % [running, resolution["drag_extra_damage"], dragged])
		running = dragged

	lines.append("%s took %d damage." % [defender, resolution["hit_damage"]])
	return lines


## Joins named terms into "a + b - c", dropping the zeroes so a line only shows
## the parts that actually contributed.
func _terms(entries: Array) -> String:
	var parts := PackedStringArray()
	for entry in entries:
		var caption := str(entry[0])
		var value := int(entry[1])
		if parts.is_empty():
			parts.append(caption)
			continue
		if value == 0:
			continue
		parts.append("%s %d %s" % ["+" if value > 0 else "-", absi(value), caption])
	return " ".join(parts)


func _target_position(resolution: Dictionary) -> int:
	var target: Dictionary = game.find_character(int(resolution["defender_player"]), str(resolution["target_id"]))
	return int(target.get("position", 0))


## The player-facing name of a kit effect, from the one source of kit text.
func _effect_name(effect: String) -> String:
	var entry: Dictionary = Kits.EFFECT_TEXT.get(effect, {})
	return str(entry.get("name", effect.capitalize()))


## A short sentence saying what one fired effect actually did this exchange.
func _effect_detail_text(note: Dictionary) -> String:
	match str(note["detail"]):
		"PADDING_HALVED", "PADDING_REDUCED":
			return "padding damage cut from %d to %d" % [note.get("amount_before", 0), note.get("amount_after", 0)]
		"PADDING_DOUBLED":
			return "padding damage raised from %d to %d" % [note.get("amount_before", 0), note.get("amount_after", 0)]
		"POSITION_4_BONUS":
			return "+%d damage from the front" % note.get("damage_modifier", 0)
		"BACK_POSITION_PENALTY":
			return "no margin damage bonus from the back"
		"PADDING_REFLECTED":
			return "%d damage dealt to the bluffer instead of self-damage" % note.get("amount", 0)
		"WRONG_CALL_ABSORBED":
			return "the wrong call cost nothing"
		"ARMED":
			return "armed for the next challenge this round"
		"SPENT":
			return "spent on this challenge"
		"CLAIM_LOCKED_IN":
			return "padding of %d was already on record, so the claim locked in unchallengeable" % note.get("padding", 0)
		"PADDING_RECORDED":
			return "padding of %d is now on record" % note.get("padding", 0)
		"PADDING_CONSUMED":
			return "padding of %d was spent and is off the record again" % note.get("padding", 0)
		"CAP_IMPOSED":
			return "the caught character's next claim is capped at %d" % note.get("cap", 20)
		"CAP_EXPIRED":
			return "the claim cap has expired"
		"CLAIM_CAPPED":
			return "this claim was capped at %d" % note.get("cap", 20)
		"DAMAGE_DOUBLED":
			return "a locked-in claim of %d doubled the damage" % note.get("claim", 0)
		"EXTENDED":
			return "%d consecutive honest claims" % note.get("honest_turns", 0)
		"RESET":
			return "the honest streak was broken"
		"TARGET_PULLED":
			return "the target was pulled forward from position %d" % note.get("from_position", 0)
		"FRONT_TARGET_BONUS":
			return "+%d damage against an already-front target" % note.get("extra_damage", 0)
		"SWAPPED_INSTEAD_OF_DAMAGE":
			return "swapped position instead of taking padding damage"
		_:
			return str(note["detail"]).replace("_", " ").to_lower()


func _record_resolution() -> void:
	var resolution: Dictionary = game.state["last_resolution"]
	# Both claims become public with the resolution, so this is the first point
	# at which either may be filed onto a sheet.
	_record_claims(resolution)
	var accent := UiTheme.COLOR_ACCENT.to_html(false)
	var muted := UiTheme.COLOR_INK_MUTED.to_html(false)
	var danger := UiTheme.COLOR_DANGER.to_html(false)
	var success := UiTheme.COLOR_SUCCESS.to_html(false)

	var entry := "[color=#%s]\u25b8 EXCHANGE %d[/color]  " % [accent, resolution["exchange_number"]]
	if resolution.get("non_attack", false):
		entry += "[color=#%s]%s[/color]" % [muted, str(resolution["move_id"]).replace("_", " ").capitalize()]
	elif resolution["miss_reason"] == "ATTACK_CAUGHT":
		entry += "[color=#%s]Bluff caught \u2014 attack cancelled[/color]" % danger
	elif resolution["hit"]:
		entry += "[color=#%s]%d damage[/color] to %s" % [
			success,
			resolution["hit_damage"],
			_character_name(int(resolution["defender_player"]), str(resolution["target_id"])),
		]
	else:
		entry += "[color=#%s]Attack missed[/color]" % muted

	# Kit effects are named in the log too, so the reads survive scrolling back.
	var fired: Array[String] = []
	for note in resolution.get("kit_effects", []):
		var effect_name := _effect_name(str(note["effect"]))
		if effect_name not in fired:
			fired.append(effect_name)
	if not fired.is_empty():
		entry += "\n[color=#%s]%s[/color]" % [accent, " · ".join(fired)]
	outcome_history.push_front(entry)
	if outcome_history.size() > 12:
		outcome_history.resize(12)


func _render_history() -> void:
	# The log ticker only exists during a match; before one there is no board to
	# hang it under.
	if history_label == null or not is_instance_valid(history_label):
		return
	if outcome_history.is_empty():
		history_label.text = "[color=#%s]No exchanges resolved yet.[/color]" % UiTheme.COLOR_INK_MUTED.to_html(false)
	else:
		history_label.text = "\n\n".join(outcome_history)


func _start_match() -> void:
	if online_mode and game != null:
		game.shutdown()
	online_mode = false
	connection_status = ""
	game = HotseatMatch.new()
	var result: Dictionary = game.start_new_match()
	if not result["ok"]:
		error_label.text = result["error"]
		return
	outcome_history.clear()
	claim_records = [[], []]
	draft_picks = []
	formation_order = []
	decision_player = 0
	ui_stage = "DRAFT"
	_render()


## Skips draft and placement with the preset teams, for players who want to get
## straight to an exchange.
func _start_quick_match() -> void:
	if online_mode and game != null:
		game.shutdown()
	online_mode = false
	connection_status = ""
	game = HotseatMatch.new()
	var result: Dictionary = game.start_preset_match()
	if not result["ok"]:
		error_label.text = result["error"]
		return
	outcome_history.clear()
	claim_records = [[], []]
	draft_picks = []
	formation_order = []
	decision_player = -1
	ui_stage = "SELECT"
	_render()


func _host_address() -> void:
	_start_online_session()
	var error: Error = game.host_address()
	if error != OK:
		if game.last_error.is_empty():
			game.last_error = "Could not start hosting"
		ui_stage = "FAILED"
	_render()


func _join_address(address_text: String) -> void:
	_start_online_session()
	var error: Error = game.join_address(address_text)
	if error != OK:
		if game.last_error.is_empty():
			game.last_error = "Could not connect to that address"
		ui_stage = "FAILED"
	_render()


func _host_online() -> void:
	_start_online_session()
	var error: Error = game.host_direct()
	if error != OK:
		game.last_error = "Could not create a direct connection offer"
		ui_stage = "FAILED"
	_render()


func _join_online(offer_code: String) -> void:
	_start_online_session()
	var error: Error = game.join_direct(offer_code)
	if error != OK:
		if game.last_error.is_empty():
			game.last_error = "Could not read the host offer"
		ui_stage = "FAILED"
	_render()


func _accept_direct_answer(answer_code: String) -> void:
	var error: Error = game.accept_direct_answer(answer_code)
	if error != OK:
		if game.last_error.is_empty():
			game.last_error = "Could not read the joiner's answer"
		error_label.text = game.last_error
	_render()


func _start_online_session() -> void:
	online_mode = true
	connection_status = "Connecting"
	game = NetworkMatch.new()
	game.status_changed.connect(_on_online_status)
	game.stage_changed.connect(_on_online_stage)
	game.state_changed.connect(_on_online_state_changed)
	game.connection_code_ready.connect(func(_code, _kind): _render())
	game.match_failed.connect(func(_message): _render())
	game.phase_countdown.connect(_on_phase_countdown)
	game.phase_timed_out.connect(_on_phase_timed_out)
	game.reconnect_pending.connect(_on_reconnect_pending)
	game.reconnected.connect(func(): _render())
	outcome_history.clear()
	claim_records = [[], []]
	decision_player = -1
	ui_stage = "DIRECT_CONNECTING"


## The countdown updates its own label rather than re-rendering the prompt, which
## would reset the claim input under the player's hands once a second.
func _on_phase_countdown(seconds_left: int) -> void:
	countdown_seconds = seconds_left
	# The ribbon clock updates in place rather than through a render, because a
	# rebuild once a second would reset whatever input the player is holding.
	if phase_ribbon != null and is_instance_valid(phase_ribbon):
		phase_ribbon.update_timer(seconds_left, _phase_timer_total())
	if countdown_label == null or not is_instance_valid(countdown_label):
		return
	countdown_label.text = "%ds left" % seconds_left
	# The last few seconds are the ones worth noticing.
	countdown_label.add_theme_color_override(
		"font_color", UiTheme.COLOR_DANGER if seconds_left <= 5 else UiTheme.COLOR_INK_MUTED
	)


func _on_reconnect_pending(seconds_left: int) -> void:
	reconnect_seconds = seconds_left
	if reconnect_label == null or not is_instance_valid(reconnect_label):
		return
	reconnect_label.text = "%ds left to reconnect" % seconds_left


func _on_phase_timed_out(phase: String) -> void:
	var explanations := {
		"SELECT": "Time ran out, so a light attack was taken for you.",
		"CLAIM": "Time ran out, so your true roll was claimed honestly.",
		"CHALLENGE": "Time ran out, so the claim was passed.",
	}
	error_label.text = str(explanations.get(phase, "Time ran out."))
	_render()


func _on_online_status(message: String) -> void:
	connection_status = message
	if ui_stage in ["DIRECT_HOST_WAITING", "DIRECT_HOST_PREPARING", "DIRECT_JOIN_PREPARING", "DIRECT_HOST_OFFER", "DIRECT_JOIN_ANSWER", "DIRECT_CONNECTING", "WAIT_ACTION", "WAIT_ROLL", "WAIT_CLAIM", "WAIT_CHALLENGE", "WAIT_REVEAL"]:
		_render()


func _on_online_stage(stage: String) -> void:
	ui_stage = stage
	if game.local_player in [0, 1]:
		decision_player = game.local_player
	if stage == "RESOLUTION":
		_record_resolution()
	_render()


func _on_online_state_changed() -> void:
	# The board rebuild now owns the prompt column as well, so a partial render
	# here would tear the current decision out from under the player.
	_render()


func _return_to_menu() -> void:
	if online_mode and game != null:
		game.shutdown()
	online_mode = false
	connection_status = ""
	game = HotseatMatch.new()
	decision_player = -1
	outcome_history.clear()
	claim_records = [[], []]
	ui_stage = "START"
	_render()


func state_is_empty() -> bool:
	return game == null or game.state.is_empty()


func _player_name(player: int) -> String:
	return HotseatMatch.PLAYER_NAMES[player]


func _player_color(player: int) -> Color:
	return UiTheme.COLOR_PLAYER_ONE if player == 0 else UiTheme.COLOR_PLAYER_TWO


func _character_name(player: int, character_id: String) -> String:
	var character: Dictionary = game.find_character(player, character_id)
	return str(character.get("display_name", character_id))


func _outcome_name(outcome: String) -> String:
	match outcome:
		"HONEST_PASS":
			return "honest, unchallenged"
		"PADDED_PASS":
			return "bluff unchallenged, so it locked in and counts in full"
		"CAUGHT":
			return "bluff challenged and caught"
		"WRONG_CALL":
			return "honest, but challenged anyway"
	return outcome


func _panel(color: Color, radius: int = UiTheme.RADIUS_PANEL) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(color, radius))
	return panel


## A paper surface. The colour argument survives from the felt-table layout and
## is mapped to a paper stock, so callers do not each pick their own card stock.
func _surface(color: Color, radius: int = UiTheme.RADIUS_PANEL) -> PanelContainer:
	var kind := "secondary"
	if color == UiTheme.COLOR_PAPER:
		kind = "raised"
	elif color == UiTheme.COLOR_CARDBOARD:
		kind = "inactive"
	var panel := PanelContainer.new()
	var style := UiTheme.paper_style(kind)
	style.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _timed_section_heading(text: String) -> Control:
	if not online_mode:
		return _section_heading(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var heading := _section_heading(text)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var countdown_text := ""
	if countdown_seconds >= 0:
		countdown_text = "%ds left" % countdown_seconds
	countdown_label = _label(countdown_text, 12, UiTheme.COLOR_INK_MUTED)
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(countdown_label)
	return row


func _section_heading(text: String) -> VBoxContainer:
	return Widgets.heading(text)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _centered_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label


## Prop buttons. A primary action is a painted orange sign; everything else is
## plain cardboard, which is the theme default the shared Theme already applies.
func _button(text: String, primary: bool) -> Button:
	return Widgets.button(text, "primary" if primary else "secondary")


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
