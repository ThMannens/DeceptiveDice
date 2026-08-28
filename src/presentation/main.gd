extends Control

const HotseatMatch = preload("res://src/local/hotseat_match.gd")
const MatchState = preload("res://src/core/match_state.gd")
const Moves = preload("res://src/core/moves.gd")
const Kits = preload("res://src/core/kits.gd")
const RulesTooltip = preload("res://src/presentation/rules_tooltip.gd")
const DirectTransport = preload("res://src/network/direct_transport.gd")
const NetworkMatch = preload("res://src/network/network_match.gd")

const UiTheme = preload("res://src/presentation/theme.gd")

## Move order shown in the action buttons.
const MOVE_IDS: Array[String] = ["light_attack", "heavy_attack", "defensive_stance", "swap"]

var game: Variant = HotseatMatch.new()
var ui_stage := "START"
var decision_player := -1
var outcome_history: Array[String] = []
var online_mode := false
var connection_status := ""

var round_label: Label
var active_label: Label
var board_container: HBoxContainer
var board_scroll: ScrollContainer
var lower_row: HBoxContainer
var prompt_box: VBoxContainer
var history_label: RichTextLabel
var claims_label: RichTextLabel
var error_label: Label
var subtitle_label: Label

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
	_render()


func _process(_delta: float) -> void:
	if online_mode and game != null:
		game.poll()


func _build_shell() -> void:
	# Two stacked fills: a near-black base with a softer felt panel floated on
	# top, which gives the table a vignetted edge instead of one flat colour.
	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.COLOR_BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var felt := PanelContainer.new()
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	felt.offset_left = 10
	felt.offset_top = 10
	felt.offset_right = -10
	felt.offset_bottom = -10
	var felt_style := UiTheme.panel_style(UiTheme.COLOR_FELT, 18, UiTheme.COLOR_FELT_EDGE, 1)
	felt_style.content_margin_left = 16
	felt_style.content_margin_right = 16
	felt_style.content_margin_top = 12
	felt_style.content_margin_bottom = 12
	felt.add_theme_stylebox_override("panel", felt_style)
	add_child(felt)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	felt.add_child(page)

	page.add_child(_build_header())

	# The board takes the slack space but is allowed to shrink, and scrolls
	# internally when four full character cards per side do not fit. Without
	# this the board pushes the action panel off the bottom of the screen.
	board_scroll = ScrollContainer.new()
	board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_scroll.custom_minimum_size.y = 232
	page.add_child(board_scroll)

	board_container = HBoxContainer.new()
	board_container.add_theme_constant_override("separation", 12)
	board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_scroll.add_child(board_container)

	# The action row keeps a fixed share of the height so every stage of the
	# match stays reachable without scrolling the page.
	lower_row = HBoxContainer.new()
	lower_row.add_theme_constant_override("separation", 12)
	lower_row.custom_minimum_size.y = 200
	lower_row.size_flags_vertical = Control.SIZE_SHRINK_END
	page.add_child(lower_row)
	var lower := lower_row

	var prompt_panel := PanelContainer.new()
	var prompt_style := UiTheme.surface_style(UiTheme.COLOR_PANEL)
	prompt_style.content_margin_top = 10
	prompt_style.content_margin_bottom = 10
	prompt_panel.add_theme_stylebox_override("panel", prompt_style)
	prompt_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(prompt_panel)
	# The prompt can outgrow its panel on the busier stages, so it scrolls
	# rather than forcing the whole page taller.
	var prompt_scroll := ScrollContainer.new()
	prompt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	prompt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prompt_panel.add_child(prompt_scroll)
	prompt_box = VBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 8)
	prompt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_scroll.add_child(prompt_box)

	lower.add_child(_build_history_panel())

	error_label = _label("", 14, UiTheme.COLOR_DANGER)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(error_label)

	# The prototype scope note lives on the start screen rather than costing a
	# permanent row of the play area.


func _build_header() -> PanelContainer:
	var header_panel := PanelContainer.new()
	var header_style := UiTheme.surface_style(UiTheme.COLOR_PANEL)
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	# A brass underline ties the title bar to the accent colour used for every
	# call to action below it.
	header_style.border_width_bottom = 2
	header_style.border_color = UiTheme.COLOR_ACCENT_DARK
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header_panel.add_child(header)

	# A die pip mark standing in for a logo.
	var mark := _label("⚅", 26, UiTheme.COLOR_ACCENT)
	header.add_child(mark)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	header.add_child(title_box)
	var title := _label("DECEPTIVE DICE", 21, UiTheme.COLOR_TEXT)
	title.add_theme_constant_override("outline_size", 0)
	title_box.add_child(title)
	subtitle_label = _label("Playable prototype", 11, UiTheme.COLOR_MUTED)
	title_box.add_child(subtitle_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	round_label = _label("", 15, UiTheme.COLOR_MUTED)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(round_label)

	active_label = _label("", 15, UiTheme.COLOR_ACCENT)
	header.add_child(active_label)
	return header_panel


func _build_history_panel() -> PanelContainer:
	var history_panel := _surface(UiTheme.COLOR_PANEL)
	history_panel.custom_minimum_size.x = 340
	var history_box := VBoxContainer.new()
	history_box.add_theme_constant_override("separation", 8)
	history_panel.add_child(history_box)
	history_box.add_child(_section_heading("Exchange log"))
	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = false
	history_label.scroll_active = true
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.add_theme_font_size_override("normal_font_size", 13)
	history_label.add_theme_color_override("default_color", UiTheme.COLOR_MUTED)
	history_box.add_child(history_label)

	# The claim record is public information both players read each other from,
	# and the Bookkeeping ledger is unplayable if you cannot see what is on it.
	history_box.add_child(_section_heading("Claim record"))
	claims_label = RichTextLabel.new()
	claims_label.bbcode_enabled = true
	claims_label.fit_content = false
	claims_label.scroll_active = true
	claims_label.custom_minimum_size.y = 120
	claims_label.add_theme_font_size_override("normal_font_size", 12)
	claims_label.add_theme_color_override("default_color", UiTheme.COLOR_MUTED)
	history_box.add_child(claims_label)
	return history_panel


## The public claim record: what each player has claimed, and which paddings the
## Ledger currently has banked for Bookkeeping.
func _render_claim_record() -> void:
	if claims_label == null:
		return
	if state_is_empty():
		claims_label.text = "[color=#%s]No claims yet.[/color]" % UiTheme.COLOR_FAINT.to_html(false)
		return

	var accent := UiTheme.COLOR_ACCENT.to_html(false)
	var faint := UiTheme.COLOR_FAINT.to_html(false)
	var blocks := PackedStringArray()

	for player in 2:
		var team: Dictionary = game.state["teams"][player]
		var tint := _player_color(player).to_html(false)
		var block := "[color=#%s]%s[/color]" % [tint, _player_name(player).to_upper()]

		var recorded: Array = team.get("recorded_paddings", [])
		if not recorded.is_empty():
			var padding_text := PackedStringArray()
			for padding in recorded:
				padding_text.append("+%d" % int(padding))
			block += "\n[color=#%s]On record: %s[/color]" % [accent, " ".join(padding_text)]

		var history: Array = team["claim_history"]
		if history.is_empty():
			block += "\n[color=#%s]No claims yet.[/color]" % faint
		else:
			# Newest first, and capped: the panel is a read aid, not an archive.
			var shown := 0
			for index in range(history.size() - 1, -1, -1):
				if shown >= 6:
					break
				var entry: Dictionary = history[index]
				var padding := int(entry["padding"])
				var padding_text := "honest" if padding == 0 else "+%d" % padding
				block += "\n[color=#%s]%s claimed %d (rolled %d, %s)[/color]" % [
					faint,
					_character_name(player, str(entry["character_id"])),
					int(entry["claim"]),
					int(entry["true_roll"]),
					padding_text,
				]
				shown += 1
		blocks.append(block)

	claims_label.text = "\n\n".join(blocks)


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
	_render_board()
	_render_history()
	_render_claim_record()
	_render_prompt()


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


## The board is a placeholder until a match starts, so out of a match the menu
## takes the height instead of leaving a large empty panel above it.
func _apply_layout_balance() -> void:
	if board_scroll == null or lower_row == null:
		return
	var in_match := not state_is_empty()
	# Out of a match the board holds nothing worth showing, so it is hidden
	# outright and the menu gets the whole play area.
	board_scroll.visible = in_match
	board_scroll.custom_minimum_size.y = 232 if in_match else 0
	lower_row.size_flags_vertical = Control.SIZE_SHRINK_END if in_match else Control.SIZE_EXPAND_FILL


func _render_header() -> void:
	if game.state.is_empty():
		round_label.text = ""
		active_label.text = ""
		return
	round_label.text = "ROUND %d  \u00b7  EXCHANGE %d" % [game.state["round_number"], game.state["exchange_number"]]
	if game.state["status"] == MatchState.STATUS_FINISHED:
		active_label.text = "MATCH COMPLETE"
		active_label.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	else:
		var active := int(game.state["active_player"])
		active_label.text = "%s ACTS" % _player_name(active).to_upper()
		# Tinting the turn indicator to the acting side makes whose turn it is
		# readable from the header alone.
		active_label.add_theme_color_override("font_color", _player_color(active))


func _render_board() -> void:
	_clear_children(board_container)
	if game.state.is_empty():
		var empty := _surface(UiTheme.COLOR_PANEL)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty_box := VBoxContainer.new()
		empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_child(empty_box)
		empty_box.add_child(_centered_label("\u2685 \u2684 \u2683", 44, UiTheme.COLOR_FELT_EDGE))
		empty_box.add_child(_centered_label("Start a match to reveal the board.", 18, UiTheme.COLOR_MUTED))
		board_container.add_child(empty)
		return

	board_container.add_child(_build_team_panel(0))
	board_container.add_child(_build_versus_divider())
	board_container.add_child(_build_team_panel(1))


## The centre column: a brass "VS" seal between two vertical rules, which gives
## the two team panels a clear axis to face off across.
func _build_versus_divider() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 54
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)

	column.add_child(_vertical_rule())

	var seal := PanelContainer.new()
	var seal_style := UiTheme.panel_style(UiTheme.COLOR_ACCENT_DEEP, 20, UiTheme.COLOR_ACCENT_DARK, 2)
	seal_style.content_margin_left = 10
	seal_style.content_margin_right = 10
	seal_style.content_margin_top = 6
	seal_style.content_margin_bottom = 6
	seal.add_theme_stylebox_override("panel", seal_style)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seal.add_child(_label("VS", 17, UiTheme.COLOR_ACCENT))
	column.add_child(seal)

	column.add_child(_vertical_rule())
	return column


func _vertical_rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.x = 2
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.COLOR_FELT_EDGE
	style.set_corner_radius_all(1)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	rule.add_theme_stylebox_override("panel", style)
	return rule


func _build_team_panel(player: int) -> PanelContainer:
	var tint := _player_color(player)
	var is_active := player == int(game.state["active_player"])
	var panel := PanelContainer.new()
	var panel_style := UiTheme.accented_surface_style(UiTheme.COLOR_PANEL, tint)
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	# Team header: name on the left, an "acting now" pill on the right.
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	box.add_child(heading_row)
	heading_row.add_child(_label(_player_name(player).to_upper(), 15, tint))
	heading_row.add_child(_label("1 back \u2192 4 front", 10, UiTheme.COLOR_FAINT))
	var heading_spacer := Control.new()
	heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading_spacer)
	if is_active and game.state["status"] != MatchState.STATUS_FINISHED:
		heading_row.add_child(_pill("ACTING", tint))

	var characters: Array = game.state["teams"][player]["characters"].duplicate()
	characters.sort_custom(func(left, right): return int(left["position"]) < int(right["position"]))
	for character in characters:
		box.add_child(_build_character_card(player, character, is_active))
	return panel


func _build_character_card(player: int, character: Dictionary, team_is_active: bool) -> PanelContainer:
	var tint := _player_color(player)
	var alive: bool = character["is_alive"]
	var character_id := str(character["id"])
	var used: bool = character_id in game.state["teams"][player]["used_character_ids"]
	var ready := alive and team_is_active and not used

	# How this card participates in the current selection.
	var is_actor := character_id == selected_actor_id and player == int(game.state["active_player"])
	var is_target := _is_valid_target(player, character_id)
	var pickable := _is_pickable_actor(player, character_id) or is_target

	var card_color := UiTheme.COLOR_PANEL_ALT
	if not alive:
		card_color = UiTheme.COLOR_DEFEATED
	elif is_actor:
		card_color = UiTheme.COLOR_PANEL_RAISED
	elif ready:
		card_color = UiTheme.COLOR_PANEL_RAISED

	var card := RulesTooltip.new()
	var spine := tint
	var lit := ready
	if is_actor:
		spine = UiTheme.COLOR_ACCENT
		lit = true
	elif is_target:
		spine = UiTheme.COLOR_DANGER if player != int(game.state["active_player"]) else UiTheme.COLOR_SUCCESS
		lit = true
	card.add_theme_stylebox_override("panel", UiTheme.card_style(card_color, spine, lit))

	if pickable:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_card_clicked(player, character_id)
		)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 3)
	card.add_child(card_box)

	# Name row: position badge, name, and a state tag.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	card_box.add_child(name_row)
	name_row.add_child(_position_badge(int(character["position"]), tint, alive))
	name_row.add_child(_label(str(character["display_name"]), 15, UiTheme.COLOR_TEXT if alive else UiTheme.COLOR_FAINT))
	var name_spacer := Control.new()
	name_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_spacer)
	if not alive:
		name_row.add_child(_pill("DEFEATED", UiTheme.COLOR_DANGER))
	elif is_actor:
		name_row.add_child(_pill("SELECTED", UiTheme.COLOR_ACCENT))
	elif is_target:
		name_row.add_child(_pill("TARGET", UiTheme.COLOR_DANGER if player != int(game.state["active_player"]) else UiTheme.COLOR_SUCCESS))
	elif used:
		name_row.add_child(_pill("ACTED", UiTheme.COLOR_FAINT))
	elif team_is_active:
		name_row.add_child(_pill("READY", UiTheme.COLOR_SUCCESS))

	# Stat strip.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	card_box.add_child(stats)
	stats.add_child(_stat("ATK", "%+d" % character["attack"], alive))
	stats.add_child(_stat("DEF", "%+d" % character["defence"], alive))
	stats.add_child(_stat("DMG", str(character["damage"]), alive))
	stats.add_child(_stat("INIT", str(character["initiative"]), alive))

	# HP reading and the bar share the stat row, keeping each card to two lines.
	var max_hp := maxi(1, int(character["max_hp"]))
	var fraction := clampf(float(character["hp"]) / float(max_hp), 0.0, 1.0)
	stats.add_child(_stat("HP", "%d/%d" % [character["hp"], max_hp], alive))

	var health := ProgressBar.new()
	health.max_value = max_hp
	health.value = character["hp"]
	health.show_percentage = false
	health.custom_minimum_size.y = 6
	health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.health_color(fraction) if alive else UiTheme.COLOR_FAINT
	fill.set_corner_radius_all(3)
	health.add_theme_stylebox_override("fill", fill)
	stats.add_child(health)

	if character["effect_counters"].get("defensive_stance_active", false):
		stats.add_child(_pill("STANCE +5", UiTheme.COLOR_PLAYER_ONE))

	# Kit strip. Both effects are named on the card and spell themselves out on
	# hover, because kits are public information every read depends on.
	var kit_row := _build_kit_row(character, alive)
	if kit_row != null:
		kit_row.add_theme_constant_override("separation", 5)
		card_box.add_child(kit_row)

	card.tooltip_text = _character_tooltip(character)
	return card


## The named kit effects for a card, each a pill that explains itself on hover.
## Returns null for a character whose kit has no effects.
func _build_kit_row(character: Dictionary, alive: bool) -> HBoxContainer:
	var descriptions: Array = Kits.effect_descriptions(str(character["id"]))
	if descriptions.is_empty():
		return null

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for description in descriptions:
		var color := UiTheme.COLOR_ACCENT if alive else UiTheme.COLOR_FAINT
		var pill := _pill(str(description["name"]).to_upper(), color, 9)
		pill.tooltip_text = "%s\n%s" % [description["name"], description["text"]]
		pill.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(pill)

	# Live kit state, so a player can see an armed or spent effect without doing
	# the bookkeeping in their head.
	var counters: Dictionary = character["effect_counters"]
	if bool(counters.get(Kits.COUNTER_READ_THE_ROOM, false)):
		var armed := _pill("ARMED", UiTheme.COLOR_SUCCESS)
		armed.tooltip_text = "Read the Room is armed
The Mirror's next challenge this round is free. It is correct if the claim was a bluff, and costs nothing if the claim was honest."
		row.add_child(armed)
	var cap := int(counters.get(Kits.COUNTER_AUDIT_CAP, 20))
	if cap < 20:
		var capped := _pill("CAP %d" % cap, UiTheme.COLOR_DANGER)
		capped.tooltip_text = "Audited
The Ledger caught this character bluffing, so their next claim this round cannot go above %d." % cap
		row.add_child(capped)
	var honest_turns := int(counters.get(Kits.COUNTER_COLD_STREAK, 0))
	if honest_turns > 0:
		var reduction := mini(honest_turns * Kits.COLD_STREAK_STEP, Kits.COLD_STREAK_MAX_REDUCTION)
		var streak := _pill("STREAK %d" % honest_turns, UiTheme.COLOR_PLAYER_ONE)
		streak.tooltip_text = "Cold Streak: %d honest claims in a row
If this character's next bluff is caught, the padding damage is reduced by %d. One padded claim resets the count." % [honest_turns, reduction]
		row.add_child(streak)
	return row


## The full card tooltip: stats on one line, then each kit effect in full.
func _character_tooltip(character: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(str(character["display_name"]))
	lines.append("HP %d/%d   ATK %+d   DEF %+d   DMG %d   INIT %d" % [
		character["hp"],
		character["max_hp"],
		character["attack"],
		character["defence"],
		character["damage"],
		character["initiative"],
	])
	lines.append("Position %d  (damage taken x%s)" % [
		int(character["position"]),
		_position_multiplier_text(int(character["position"])),
	])
	for description in Kits.effect_descriptions(str(character["id"])):
		lines.append("")
		lines.append("%s — %s" % [description["name"], description["text"]])
	return "\n".join(lines)


func _position_multiplier_text(position: int) -> String:
	match position:
		1:
			return "0.7"
		2:
			return "0.85"
		4:
			return "1.2"
		_:
			return "1.0"


## The small numbered square marking a rank in the formation.
func _position_badge(position: int, tint: Color, alive: bool) -> PanelContainer:
	var badge := PanelContainer.new()
	var color := tint if alive else UiTheme.COLOR_FAINT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.18)
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_color = Color(color, 0.55)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(_label(str(position), 13, color))
	return badge


## A stat shown as a small muted caption above its value.
func _stat(caption: String, value: String, alive: bool) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(caption, 10, UiTheme.COLOR_FAINT))
	box.add_child(_label(value, 12, UiTheme.COLOR_TEXT if alive else UiTheme.COLOR_FAINT))
	return box


## A compact rounded tag used for statuses like READY, ACTED, or DEFEATED.
func _pill(text: String, color: Color, font_size: int = 10) -> PanelContainer:
	# RulesTooltip rather than a bare PanelContainer: Godot asks the hovered
	# control itself for its tooltip node, so the builder has to live on the pill.
	var pill := RulesTooltip.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.16)
	style.set_corner_radius_all(9)
	style.set_border_width_all(1)
	style.border_color = Color(color, 0.5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(_label(text, font_size, color))
	return pill


## True when this card belongs to the acting side and can still be chosen as
## the acting character.
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
	match ui_stage:
		"START":
			_render_start_prompt()
		"DIRECT_HOST_WAITING":
			_render_host_waiting_prompt()
		"DIRECT_HOST_PREPARING", "DIRECT_JOIN_PREPARING", "DIRECT_HOST_OFFER", "DIRECT_JOIN_ANSWER", "DIRECT_CONNECTING":
			_render_direct_connection_prompt()
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
		"RESOLUTION":
			_render_resolution_prompt()
		"FINISHED":
			_render_finished_prompt()
		"FAILED":
			_render_failed_prompt()
		_:
			prompt_box.add_child(_label("Unknown interface state", 20, UiTheme.COLOR_DANGER))


func _render_start_prompt() -> void:
	prompt_box.add_child(_label("Read the roll. Sell the lie.", 24, UiTheme.COLOR_ACCENT))
	var description := _label("Play on one device or connect two copies of the game. Online matches send gameplay directly between players and use commitments so neither player can change a roll, claim, or challenge after seeing the opponent's choice.", 14, UiTheme.COLOR_TEXT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(description)
	prompt_box.add_child(_label("The prototype uses fixed four-character teams and formations, so a match begins immediately.", 12, UiTheme.COLOR_FAINT))

	var start_button := _button("Start hot-seat match", true)
	start_button.pressed.connect(_start_match)
	prompt_box.add_child(start_button)

	prompt_box.add_child(_section_heading("Play against another window or machine"))
	var host_button := _button("Host a match", false)
	host_button.pressed.connect(_host_address)
	prompt_box.add_child(host_button)

	prompt_box.add_child(_label("To join, enter the address the host shows you.", 12, UiTheme.COLOR_FAINT))
	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 8)
	prompt_box.add_child(address_row)
	var address_input := LineEdit.new()
	address_input.placeholder_text = "127.0.0.1:8910"
	address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_input)
	var join_button := _button("Join", false)
	join_button.pressed.connect(func(): _join_address(address_input.text))
	address_row.add_child(join_button)
	# Enter in the address field joins, which is the common case.
	address_input.text_submitted.connect(func(text: String): _join_address(text))

	prompt_box.add_child(_label("On one machine use 127.0.0.1:8910. On the same network use the LAN address the host shows. Over the internet the host must forward this port on their router.", 11, UiTheme.COLOR_FAINT))


## Shown to the hosting player while they wait for an opponent. It lists the
## addresses this machine can be reached on so they can pass one along.
func _render_host_waiting_prompt() -> void:
	prompt_box.add_child(_section_heading("Waiting for the other player"))
	prompt_box.add_child(_pill_row("LISTENING", UiTheme.COLOR_ACCENT))

	var addresses := DirectTransport.local_addresses()
	prompt_box.add_child(_label("Give the other player one of these:", 13, UiTheme.COLOR_TEXT))
	prompt_box.add_child(_address_row("Same machine", str(addresses["local"])))
	if not str(addresses["lan"]).is_empty():
		prompt_box.add_child(_address_row("Same network", str(addresses["lan"])))
	else:
		prompt_box.add_child(_label("No network address found; only same-machine play is available.", 11, UiTheme.COLOR_FAINT))

	prompt_box.add_child(_label("To play over the internet, forward port %d on the router and share your public address." % int(addresses["port"]), 11, UiTheme.COLOR_FAINT))

	var cancel := _button("Cancel", false)
	cancel.pressed.connect(_return_to_menu)
	prompt_box.add_child(cancel)


## One labelled address with a copy button beside it.
func _address_row(caption: String, address: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption_label := _label(caption, 11, UiTheme.COLOR_FAINT)
	caption_label.custom_minimum_size.x = 110
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption_label)
	var value := _label(address, 17, UiTheme.COLOR_ACCENT_BRIGHT)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_copy_button("Copy", address))
	return row


func _render_direct_connection_prompt() -> void:
	prompt_box.add_child(_section_heading("Direct peer connection"))
	prompt_box.add_child(_label(connection_status, 15, UiTheme.COLOR_TEXT))
	match ui_stage:
		"DIRECT_HOST_PREPARING", "DIRECT_JOIN_PREPARING":
			prompt_box.add_child(_label("Collecting connection details. This usually takes a few seconds.", 14, UiTheme.COLOR_MUTED))
		"DIRECT_HOST_OFFER":
			prompt_box.add_child(_label("1. Send this offer only to the player joining you.", 14, UiTheme.COLOR_MUTED))
			var offer_output := _code_output(game.manual_code)
			prompt_box.add_child(offer_output)
			prompt_box.add_child(_copy_button("Copy offer", game.manual_code))
			prompt_box.add_child(_label("2. Paste the answer they send back.", 14, UiTheme.COLOR_MUTED))
			var answer_input := _code_input("Paste joiner's answer code")
			prompt_box.add_child(answer_input)
			var connect_button := _button("Connect with answer", true)
			connect_button.pressed.connect(func(): _accept_direct_answer(answer_input.text))
			prompt_box.add_child(connect_button)
		"DIRECT_JOIN_ANSWER":
			prompt_box.add_child(_label("Send this answer back to the host. Keep this window open while they paste it.", 14, UiTheme.COLOR_MUTED))
			var answer_output := _code_output(game.manual_code)
			prompt_box.add_child(answer_output)
			prompt_box.add_child(_copy_button("Copy answer", game.manual_code))
		"DIRECT_CONNECTING":
			prompt_box.add_child(_label("The codes were accepted. Waiting for the peer channel to open.", 14, UiTheme.COLOR_MUTED))
	prompt_box.add_child(_label("Connection codes include network address information. Share them only with your opponent.", 12, UiTheme.COLOR_MUTED))
	var cancel := _button("Back to menu", false)
	cancel.pressed.connect(_return_to_menu)
	prompt_box.add_child(cancel)


## A small uppercase caption used to label a form field.
func _field_caption(text: String) -> Label:
	var label := _label(text.to_upper(), 11, UiTheme.COLOR_FAINT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## The private roll, drawn as a large brass-edged die face.
func _roll_face(roll: int, tint: Color) -> CenterContainer:
	var centre := CenterContainer.new()
	var face := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.COLOR_BACKDROP
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = tint
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	style.shadow_color = Color(tint, 0.28)
	style.shadow_size = 10
	face.add_theme_stylebox_override("panel", style)
	var value := _label(str(roll), 38, UiTheme.COLOR_ACCENT_BRIGHT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.add_child(value)
	centre.add_child(face)
	return centre


## One side of the claim comparison shown before a challenge decision.
func _claim_tile(caption: String, value: int, tint: Color) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.panel_style(UiTheme.COLOR_FELT, UiTheme.RADIUS_CARD, Color(tint, 0.55), 1)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	tile.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)
	var caption_label := _label(caption, 10, UiTheme.COLOR_FAINT)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	var value_label := _label(str(value), 26, tint)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value_label)
	return tile


## The full-width result banner shown when a match ends.
func _banner(text: String, tint: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	var style := UiTheme.panel_style(Color(tint, 0.14), UiTheme.RADIUS_CARD, tint, 2)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", style)
	var label := _label(text, 22, tint)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(label)
	return banner


func _code_input(placeholder: String) -> TextEdit:
	var input := TextEdit.new()
	input.placeholder_text = placeholder
	input.custom_minimum_size.y = 72
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
			prompt_box.add_child(_label("%s is active." % _player_name(active), 14, UiTheme.COLOR_TEXT))
	prompt_box.add_child(_label(connection_status, 12, UiTheme.COLOR_FAINT))


## Wraps a pill so it sits left-aligned on its own row instead of stretching.
func _pill_row(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_pill(text, color))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	return row


func _render_select_prompt() -> void:
	var player := int(game.state["active_player"])

	# The OptionButtons remain the model the submit path reads from, but they
	# are no longer shown: the board and the move buttons drive them instead.
	_build_hidden_action_model(player)

	if selected_actor_id.is_empty():
		prompt_box.add_child(_section_heading("%s: choose a character" % _player_name(player)))
		var hint := _label("Click one of your highlighted characters on the board to begin.", 14, UiTheme.COLOR_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prompt_box.add_child(hint)
		return

	var actor: Dictionary = game.find_character(player, selected_actor_id)
	prompt_box.add_child(_section_heading("%s \u2014 choose a move" % str(actor.get("display_name", "Character"))))
	prompt_box.add_child(_build_move_buttons(player, actor))

	if selected_move_id.is_empty():
		prompt_box.add_child(_label("Pick a move, then click its target on the board.", 13, UiTheme.COLOR_MUTED))
	else:
		move_help = _label(_move_description(selected_move_id), 13, UiTheme.COLOR_MUTED)
		move_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prompt_box.add_child(move_help)
		prompt_box.add_child(_build_target_hint(player))

	var change := _button("Choose a different character", false)
	change.pressed.connect(func():
		selected_actor_id = ""
		selected_move_id = ""
		_render()
	)
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


## One button per move, disabled with a reason when the actor cannot use it.
func _build_move_buttons(player: int, actor: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for move_id: String in MOVE_IDS:
		var move := Moves.get_move(move_id)
		var chosen: bool = move_id == selected_move_id
		var button := _button(str(move["display_name"]), chosen)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34

		var blocked := _move_block_reason(player, actor, move_id)
		if not blocked.is_empty():
			button.disabled = true
			button.tooltip_text = blocked
		else:
			var captured := move_id
			button.pressed.connect(func():
				selected_move_id = captured
				_render()
			)
		grid.add_child(button)
	return grid


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
	var instruction := _centered_label("Give the screen to %s. The next view contains their %s." % [_player_name(decision_player), subject], 14, UiTheme.COLOR_TEXT)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(instruction)
	var ready := _button("I am %s" % _player_name(decision_player), true)
	ready.pressed.connect(func():
		ui_stage = next_stage
		_render()
	)
	prompt_box.add_child(ready)


func _render_claim_prompt() -> void:
	var action_player := int(game.state["exchange"]["action"]["player"])
	var role := "attack" if decision_player == action_player else "defence"
	var roll := int(game.true_rolls[decision_player])
	prompt_box.add_child(_section_heading("%s: your private %s roll" % [_player_name(decision_player), role]))
	# The private roll is the dramatic beat of the game, so it gets presented as
	# a die face on the table rather than a bare number.
	prompt_box.add_child(_roll_face(roll, _player_color(decision_player)))
	prompt_box.add_child(_centered_label("Claim this value, or bluff any higher value up to 20.", 13, UiTheme.COLOR_MUTED))

	var claim_row := HBoxContainer.new()
	claim_row.add_theme_constant_override("separation", 10)
	claim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.add_child(claim_row)
	claim_row.add_child(_field_caption("CLAIM"))
	var claim_input := SpinBox.new()
	claim_input.min_value = roll
	claim_input.max_value = 20
	claim_input.step = 1
	claim_input.value = roll
	claim_input.custom_minimum_size.x = 130
	claim_input.add_theme_font_size_override("font_size", 18)
	claim_row.add_child(claim_input)
	var submit := _button("Submit claim", true)
	submit.pressed.connect(func(): _submit_claim(int(claim_input.value)))
	prompt_box.add_child(submit)


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


func _render_challenge_prompt() -> void:
	var opponent := 1 - decision_player
	var opponent_claim := int(game.state["exchange"]["claims"][opponent]["value"])
	var own_claim := int(game.state["exchange"]["claims"][decision_player]["value"])
	prompt_box.add_child(_section_heading("%s: call the opponent" % _player_name(decision_player)))

	# The two claims sit side by side so they can be compared at a glance.
	var claims := HBoxContainer.new()
	claims.add_theme_constant_override("separation", 12)
	prompt_box.add_child(claims)
	claims.add_child(_claim_tile("%s CLAIMED" % _player_name(opponent).to_upper(), opponent_claim, _player_color(opponent)))
	claims.add_child(_claim_tile("YOU CLAIMED", own_claim, _player_color(decision_player)))

	var hint := _label("Challenge if you think their claim is higher than their true roll. Being right cancels their attack and damages them. Being wrong leaves their claim standing and punishes you.", 13, UiTheme.COLOR_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	prompt_box.add_child(buttons)
	var pass_button := _button("Pass", false)
	pass_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_button.pressed.connect(func(): _submit_challenge(false))
	buttons.add_child(pass_button)
	var challenge_button := _button("Challenge", true)
	challenge_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	challenge_button.pressed.connect(func(): _submit_challenge(true))
	buttons.add_child(challenge_button)


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


func _render_resolution_prompt() -> void:
	var resolution: Dictionary = game.state["last_resolution"]
	prompt_box.add_child(_section_heading("Exchange resolved"))
	var details := _label(_format_resolution(resolution), 14, UiTheme.COLOR_TEXT)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_box.add_child(details)
	if game.state["status"] == MatchState.STATUS_FINISHED:
		var winner := int(game.state["winner_player"])
		var result_text := "DRAW" if winner < 0 else "%s WINS" % _player_name(winner).to_upper()
		prompt_box.add_child(_banner(result_text, UiTheme.COLOR_ACCENT if winner < 0 else _player_color(winner)))
		var restart := _button("Back to menu" if online_mode else "Start a new match", true)
		restart.pressed.connect(_return_to_menu if online_mode else _start_match)
		prompt_box.add_child(restart)
	else:
		var continue_button := _button("Continue to next turn", true)
		if online_mode:
			continue_button.pressed.connect(func(): game.continue_after_resolution())
		else:
			continue_button.pressed.connect(func():
				ui_stage = "SELECT"
				_render()
			)
		prompt_box.add_child(continue_button)


func _render_finished_prompt() -> void:
	prompt_box.add_child(_section_heading("Match complete"))
	var winner := int(game.state.get("winner_player", -1))
	prompt_box.add_child(_banner(
		"DRAW" if winner < 0 else "%s WINS" % _player_name(winner).to_upper(),
		UiTheme.COLOR_ACCENT if winner < 0 else _player_color(winner)
	))
	if not connection_status.is_empty():
		prompt_box.add_child(_label(connection_status, 12, UiTheme.COLOR_FAINT))
	var back := _button("Back to menu", true)
	back.pressed.connect(_return_to_menu)
	prompt_box.add_child(back)


func _render_failed_prompt() -> void:
	prompt_box.add_child(_section_heading("Online match stopped"))
	prompt_box.add_child(_pill_row("DISCONNECTED", UiTheme.COLOR_DANGER))
	var message: String = game.last_error if game != null else connection_status
	var details := _label(message, 14, UiTheme.COLOR_TEXT)
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
	var defence_terms := _terms([
		["roll %d" % defence["resolved_value"], int(defence["resolved_value"])],
		["Defence stat", int(resolution["effective_defence"]) - int(defence["resolved_value"]) - stance],
		["stance", stance],
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
	var accent := UiTheme.COLOR_ACCENT.to_html(false)
	var muted := UiTheme.COLOR_MUTED.to_html(false)
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
	if outcome_history.is_empty():
		history_label.text = "[color=#%s]No exchanges resolved yet.[/color]" % UiTheme.COLOR_FAINT.to_html(false)
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
	outcome_history.clear()
	decision_player = -1
	ui_stage = "DIRECT_CONNECTING"


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
	_render_header()
	_render_board()


func _return_to_menu() -> void:
	if online_mode and game != null:
		game.shutdown()
	online_mode = false
	connection_status = ""
	game = HotseatMatch.new()
	decision_player = -1
	outcome_history.clear()
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


## A framed panel with an edge and drop shadow. This is the default for the
## major regions of the layout.
func _surface(color: Color, radius: int = UiTheme.RADIUS_PANEL) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.surface_style(color, radius))
	return panel


## A small-caps style heading with a brass rule beneath it, used to open each
## region of the interface.
func _section_heading(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var heading := _label(text.to_upper(), 13, UiTheme.COLOR_ACCENT)
	heading.add_theme_constant_override("line_spacing", 0)
	box.add_child(heading)
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2
	var rule_style := StyleBoxFlat.new()
	rule_style.bg_color = UiTheme.COLOR_ACCENT_DARK
	rule_style.set_corner_radius_all(1)
	rule_style.content_margin_left = 0
	rule_style.content_margin_right = 0
	rule_style.content_margin_top = 0
	rule_style.content_margin_bottom = 0
	rule.add_theme_stylebox_override("panel", rule_style)
	box.add_child(rule)
	return box


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


## Primary buttons are filled brass and carry the main action of a stage;
## secondary buttons fall back to the outlined style set on the shared Theme.
func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 15)
	if not primary:
		return button

	var normal := UiTheme.button_style(UiTheme.COLOR_ACCENT_DARK, UiTheme.COLOR_ACCENT, 1)
	button.add_theme_stylebox_override("normal", normal)
	var hover := UiTheme.button_style(UiTheme.COLOR_ACCENT, UiTheme.COLOR_ACCENT_BRIGHT, 1)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := UiTheme.button_style(UiTheme.COLOR_ACCENT_DEEP, UiTheme.COLOR_ACCENT_DARK, 1)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := UiTheme.button_style(Color(UiTheme.COLOR_ACCENT_DEEP, 0.5), Color(UiTheme.COLOR_ACCENT_DARK, 0.4), 1)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT_BRIGHT)
	button.add_theme_color_override("font_hover_color", UiTheme.COLOR_BACKDROP)
	button.add_theme_color_override("font_pressed_color", UiTheme.COLOR_ACCENT)
	button.add_theme_color_override("font_disabled_color", UiTheme.COLOR_FAINT)
	return button


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
