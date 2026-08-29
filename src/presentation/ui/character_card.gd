extends PanelContainer

## One LARPer's card: portrait, name, formation slot, HP, the four stats, both
## kit effects, and every live status.
##
## The card accepts state and reports clicks. It never queries or mutates the
## reducer, so the same component renders a live match, a snapshot mid-animation,
## and a defeated character with no branching on where the data came from.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const Portrait = preload("res://src/presentation/ui/portrait.gd")
const Kits = preload("res://src/core/kits.gd")
const RulesTooltip = preload("res://src/presentation/rules_tooltip.gd")

## Emitted when the player clicks a card that is currently interactive.
signal card_clicked(player: int, character_id: String)

## Interaction states, in the order the card resolves them. A card is only ever
## in one, so the border and the printed tag can never disagree.
const STATE_NORMAL := "NORMAL"
const STATE_READY := "READY"
const STATE_SELECTED := "SELECTED"
const STATE_LEGAL_TARGET := "LEGAL_TARGET"
const STATE_ATTACKER := "ATTACKER"
const STATE_DEFENDER := "DEFENDER"
const STATE_ACTED := "ACTED"
const STATE_DEFEATED := "DEFEATED"

## Damage taken by formation slot, printed on the card so a player never has to
## remember which rank is soft. Mirrors CombatResolver.POSITION_DAMAGE_PERCENT,
## which stays the authority; this is the display string only.
const POSITION_LABELS := {1: "70%", 2: "85%", 3: "100%", 4: "120%"}

## How the card styles each interaction state. The theme owns the colours; this
## is only the mapping from a card state to a style state and a printed tag.
const STATE_STYLE := {
	STATE_SELECTED: "selected",
	STATE_ATTACKER: "attacker",
	STATE_DEFENDER: "defender",
	STATE_LEGAL_TARGET: "legal_target",
	STATE_READY: "ready",
	STATE_ACTED: "acted",
	STATE_DEFEATED: "defeated",
	STATE_NORMAL: "normal",
}

var player := -1
var character_id := ""
var interaction_state := STATE_NORMAL

var _tint: Color = UiTheme.COLOR_PLAYER_ONE
var _character: Dictionary = {}
var _compact := false
var _health_bar: ProgressBar
var _hp_label: Label
var _body: VBoxContainer
var _effect_patches: Dictionary = {}


func _init() -> void:
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)


## Renders a character onto this card.
##
## `view` carries the presentation-only facts the character dictionary cannot
## know: "tint" (the owning player's colour), "state" (one of the STATE_
## constants), "compact" (true at the smaller window size, which trims the
## portrait rather than the body text), and "clickable".
func bind_character(owning_player: int, character: Dictionary, view: Dictionary) -> void:
	player = owning_player
	character_id = str(character.get("id", ""))
	_character = character
	_tint = view.get("tint", UiTheme.COLOR_PLAYER_ONE)
	_compact = bool(view.get("compact", false))
	set_interaction_state(str(view.get("state", STATE_NORMAL)))
	_wire_click(bool(view.get("clickable", false)))
	_rebuild()


## Switches the card between interaction states without rebuilding its contents.
func set_interaction_state(state: String) -> void:
	interaction_state = state
	add_theme_stylebox_override("panel", UiTheme.team_card_style(_tint, str(STATE_STYLE.get(state, "normal"))))


## Runs the HP bar and the printed figure from one value to another. Returns the
## Tween so a resolution sequence can chain on it; under reduced motion the
## numbers are already correct and the returned Tween finishes immediately.
func animate_hp(from_hp: int, to_hp: int) -> Tween:
	var tween := create_tween()
	if _health_bar == null or _hp_label == null:
		return tween
	var max_hp := maxi(1, int(_character.get("max_hp", 1)))
	if UiTheme.reduced_motion:
		_set_hp_display(to_hp, max_hp)
		return tween
	_set_hp_display(from_hp, max_hp)
	tween.tween_method(
		func(value: float): _set_hp_display(int(round(value)), max_hp),
		float(from_hp), float(to_hp), 0.6,
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


## Slides the card between two formation slots. The card itself does not move in
## the tree; the roster reorders, so this animates the offset the roster will
## settle to and is safe to run against a card that is about to be rebuilt.
func animate_position(from_position: int, to_position: int) -> Tween:
	var tween := create_tween()
	if UiTheme.reduced_motion or from_position == to_position:
		position.y = 0.0
		return tween
	# Slots run back to front down the column, so a move toward the front is a
	# move down the screen.
	var travel := float(to_position - from_position) * size.y
	position.y = -travel
	tween.tween_property(self, "position:y", 0.0, 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


## Draws attention to one kit patch just before the number it changed appears,
## so a modified figure is never unexplained.
func pulse_effect(effect_id: String) -> void:
	var patch: Control = _effect_patches.get(effect_id)
	if patch == null or not is_instance_valid(patch):
		return
	if UiTheme.reduced_motion:
		return
	var tween := create_tween()
	tween.tween_property(patch, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(patch, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)


func _wire_click(clickable: bool) -> void:
	for connection in gui_input.get_connections():
		gui_input.disconnect(connection["callable"])
	if not clickable:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(player, character_id)


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	_effect_patches.clear()

	var alive: bool = bool(_character.get("is_alive", true))
	var ink := UiTheme.COLOR_INK if alive else UiTheme.COLOR_INK_MUTED

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_body.add_child(top)

	# The portrait shrinks before any body text does, which is the whole reason
	# the compact flag exists.
	top.add_child(Portrait.build(
		character_id,
		str(_character.get("display_name", character_id)),
		_tint,
		40 if _compact else 52,
		alive,
	))

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 2)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(detail)

	detail.add_child(_name_row(alive, ink))
	detail.add_child(_slot_row(alive))
	detail.add_child(_health_row(alive))

	_body.add_child(_stat_row(alive, ink))

	var statuses := _status_row(alive)
	if statuses != null:
		_body.add_child(statuses)

	var kits := _kit_row(alive)
	if kits != null:
		_body.add_child(kits)

	tooltip_text = _tooltip()


## Name and the one state tag that applies. A defeated or spent card also gets a
## diagonal grey strip through the tag, so the state survives desaturation.
func _name_row(alive: bool, ink: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := Widgets.label(str(_character.get("display_name", character_id)), 16, ink)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	match interaction_state:
		STATE_DEFEATED:
			row.add_child(Widgets.stamp("OUT", UiTheme.COLOR_DANGER, 10))
		STATE_SELECTED:
			row.add_child(Widgets.stamp("PICKED", UiTheme.COLOR_ACCENT, 10))
		STATE_LEGAL_TARGET:
			row.add_child(Widgets.stamp("TARGET", UiTheme.COLOR_DANGER, 10))
		STATE_ATTACKER:
			var attacker := Widgets.stamp("⚔ SWINGING", UiTheme.COLOR_ACCENT, 10)
			attacker.tooltip_text = "This character is making the attack in the current exchange."
			row.add_child(attacker)
		STATE_DEFENDER:
			var defender := Widgets.stamp("⛨ TAKING IT", UiTheme.COLOR_INFO, 10)
			defender.tooltip_text = "This character is the target of the current attack."
			row.add_child(defender)
		STATE_ACTED:
			row.add_child(Widgets.patch("ACTED", UiTheme.COLOR_DISABLED, 10, "disabled"))
		STATE_READY:
			row.add_child(Widgets.patch("READY", UiTheme.COLOR_SUCCESS, 10))
	return row


## The formation slot and what standing there costs, printed together because
## the multiplier is the only reason the slot number matters.
func _slot_row(alive: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var position := int(_character.get("position", 0))
	var slot_name := "FRONT" if position == 4 else ("BACK" if position == 1 else "MID")
	var color := UiTheme.COLOR_INK if alive else UiTheme.COLOR_DISABLED
	row.add_child(Widgets.patch("%s %d" % [slot_name, position], color, 9,
		"disabled" if not alive else "normal"))
	row.add_child(Widgets.label(
		"takes %s" % str(POSITION_LABELS.get(position, "100%")),
		11,
		UiTheme.COLOR_INK_MUTED,
	))
	row.add_child(Widgets.filler())
	return row


## HP as a figure and a slot-cut bar. The figure is the real reading; the bar is
## the glance, which is why both are always present.
func _health_row(alive: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var max_hp := maxi(1, int(_character.get("max_hp", 1)))
	var hp := int(_character.get("hp", 0))

	_hp_label = Widgets.label("", 13, UiTheme.COLOR_INK if alive else UiTheme.COLOR_INK_MUTED)
	_hp_label.custom_minimum_size.x = 56
	row.add_child(_hp_label)

	_health_bar = ProgressBar.new()
	_health_bar.max_value = max_hp
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size.y = 9
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_health_bar)

	_set_hp_display(hp, max_hp)
	if not alive:
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.COLOR_DISABLED
		fill.set_corner_radius_all(2)
		_health_bar.add_theme_stylebox_override("fill", fill)
	return row


func _set_hp_display(hp: int, max_hp: int) -> void:
	if _health_bar != null and is_instance_valid(_health_bar):
		_health_bar.value = hp
		if bool(_character.get("is_alive", true)):
			var fill := StyleBoxFlat.new()
			fill.bg_color = UiTheme.health_color(clampf(float(hp) / float(max_hp), 0.0, 1.0))
			fill.set_corner_radius_all(2)
			_health_bar.add_theme_stylebox_override("fill", fill)
	if _hp_label != null and is_instance_valid(_hp_label):
		_hp_label.text = "%d/%d" % [hp, max_hp]


func _stat_row(alive: bool, ink: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for entry in [
		["ATK", "%+d" % int(_character.get("attack", 0))],
		["DEF", "%+d" % int(_character.get("defence", 0))],
		["DMG", str(int(_character.get("damage", 0)))],
		["INIT", str(int(_character.get("initiative", 0)))],
	]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(Widgets.label(str(entry[0]), 10, UiTheme.COLOR_INK_MUTED))
		cell.add_child(Widgets.label(str(entry[1]), 13, ink))
		row.add_child(cell)
	row.add_child(Widgets.filler())
	return row


## Live combat statuses: stance and exposure. Returns null when nothing is on.
func _status_row(alive: bool) -> HBoxContainer:
	var counters: Dictionary = _character.get("effect_counters", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var any := false

	if bool(counters.get("defensive_stance_active", false)):
		var stance := Widgets.patch("⛨ STANCE +5", UiTheme.COLOR_INFO, 10)
		stance.tooltip_text = "Defensive stance\nThis character gains +5 defence until their next turn."
		row.add_child(stance)
		any = true
	if bool(counters.get("exposed_after_wrong_call", false)):
		var exposed := Widgets.patch("⚠ EXPOSED -5", UiTheme.COLOR_DANGER, 10)
		exposed.tooltip_text = "Exposed\nA challenge involving this character settled for nothing at the time: either they called wrongly for free, or they were caught bluffing on defence without it costing them. Their next defence roll takes a 5 point penalty."
		row.add_child(exposed)
		any = true

	if not any:
		# The row was never parented, so queue_free would never run on it.
		row.free()
		return null
	row.add_child(Widgets.filler())
	return row


## Both kit effects by name, plus the live counters that say what state those
## effects are currently in. Kits are public information every read depends on,
## so nothing here is ever hidden behind a hover.
func _kit_row(alive: bool) -> HBoxContainer:
	var descriptions: Array = Kits.effect_descriptions(character_id)
	var counters: Dictionary = _character.get("effect_counters", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var any := false

	for description in descriptions:
		var patch := Widgets.patch(
			str(description["name"]).to_upper(),
			UiTheme.COLOR_ACCENT if alive else UiTheme.COLOR_DISABLED,
			9,
			"disabled" if not alive else "normal",
		)
		patch.tooltip_text = "%s\n%s" % [description["name"], description["text"]]
		patch.mouse_filter = Control.MOUSE_FILTER_STOP
		patch.pivot_offset = patch.size / 2.0
		_effect_patches[str(description["effect"])] = patch
		row.add_child(patch)
		any = true

	if bool(counters.get(Kits.COUNTER_READ_THE_ROOM, false)):
		var armed := Widgets.patch("ARMED", UiTheme.COLOR_SUCCESS, 9)
		armed.tooltip_text = "Read the Room is armed\nThe Mirror's next challenge this round is free. It is correct if the claim was a bluff, and costs nothing if the claim was honest."
		row.add_child(armed)
		any = true
	var cap := int(counters.get(Kits.COUNTER_AUDIT_CAP, 20))
	if cap < 20:
		var capped := Widgets.patch("CAP %d" % cap, UiTheme.COLOR_DANGER, 9)
		capped.tooltip_text = "Audited\nThe Ledger caught this character bluffing, so their next claim this round cannot go above %d." % cap
		row.add_child(capped)
		any = true
	var honest_turns := int(counters.get(Kits.COUNTER_COLD_STREAK, 0))
	if honest_turns > 0:
		var reduction := mini(honest_turns * Kits.COLD_STREAK_STEP, Kits.COLD_STREAK_MAX_REDUCTION)
		var streak := Widgets.patch("STREAK %d" % honest_turns, UiTheme.COLOR_INFO, 9)
		streak.tooltip_text = "Cold Streak: %d honest claims in a row\nIf this character's next bluff is caught, the padding damage is reduced by %d. One padded claim resets the count." % [honest_turns, reduction]
		row.add_child(streak)
		any = true

	if not any:
		# The row was never parented, so queue_free would never run on it.
		row.free()
		return null
	row.add_child(Widgets.filler())
	return row


## The full card tooltip: stats on one line, then each kit effect in full.
func _tooltip() -> String:
	var lines: Array[String] = []
	lines.append(str(_character.get("display_name", character_id)))
	lines.append("HP %d/%d   ATK %+d   DEF %+d   DMG %d   INIT %d" % [
		int(_character.get("hp", 0)),
		int(_character.get("max_hp", 0)),
		int(_character.get("attack", 0)),
		int(_character.get("defence", 0)),
		int(_character.get("damage", 0)),
		int(_character.get("initiative", 0)),
	])
	var position := int(_character.get("position", 0))
	lines.append("Position %d  (damage taken %s)" % [position, str(POSITION_LABELS.get(position, "100%"))])
	for description in Kits.effect_descriptions(character_id):
		lines.append("")
		lines.append("%s — %s" % [description["name"], description["text"]])
	return "\n".join(lines)


## Godot asks the hovered control itself for its tooltip node, so the rules
## tooltip builder has to live on the card as well as on the patches.
func _make_custom_tooltip(for_text: String) -> Object:
	return RulesTooltip.build_tooltip(for_text)
