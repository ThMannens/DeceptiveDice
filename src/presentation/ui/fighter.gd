extends RefCounted

## One character on the field: the animated rig, and the nameplate hanging under
## its feet that carries the name, the rank, and the health bar.
##
## The rig is decoration and the plate is the interface. Everything a player must
## be able to read or click lives on the plate, which is a real Control, so the
## board stays usable when a character has no rig yet and stays reachable by
## keyboard either way.
##
## The fighter plays animation beats but never decides when: the shell asks for
## a swing or a flinch off `last_resolution` fields, exactly as the resolution
## sequence does for the numbers.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const FighterRigs = preload("res://src/presentation/ui/fighter_rigs.gd")
const Kits = preload("res://src/core/kits.gd")
const PlateButton = preload("res://src/presentation/ui/plate_button.gd")

signal clicked(player: int, character_id: String)

## How far under the ground line the nameplate hangs, in pixels.
const PLATE_DROP := 6
const PLATE_MIN_WIDTH := 84

## The least height a plate may take, so a plate whose rows have not been laid
## out yet still reserves room rather than collapsing to its own margins.
const PLATE_MIN_HEIGHT := 44

## Damage taken by formation slot. Mirrors CombatResolver.POSITION_DAMAGE_PERCENT,
## which stays the authority; this is the display string only.
const POSITION_LABELS := {1: "70%", 2: "85%", 3: "100%", 4: "120%"}

var player := -1
var character_id := ""
var position_rank := 4

## The rig's parent. Always present, even when the character has no rig: the
## board positions this node regardless, so layout never has to special-case a
## missing export.
var rig_root: Node2D
## The clickable nameplate. This is the fighter's whole interface.
var plate: PlateButton

var _rig: Node2D
var _playback: AnimationNodeStateMachinePlayback
var _name_label: Label
var _rank_label: Label
var _health_bar: ProgressBar
var _stamp_row: HBoxContainer
var _kit_row: HBoxContainer
var _placeholder: Node2D
var _alive := true
## A beat waiting on the current one to finish, and whether a poll is already
## running for it.
var _pending_beat := ""
var _pending_variant := 0
var _pending_poll := false


func _init(owning_player: int = -1, id: String = "") -> void:
	player = owning_player
	character_id = id

	rig_root = Node2D.new()
	_rig = FighterRigs.instantiate(character_id)
	if _rig != null:
		# The rig scenes ship with a keyboard-driven animation cycler for
		# reviewing the art on its own. On the board the shell decides the
		# beats, so the script comes off and this drives the tree directly.
		_rig.set_script(null)
		_rig.position = Vector2.ZERO
		rig_root.add_child(_rig)
	else:
		_placeholder = _build_placeholder()
		rig_root.add_child(_placeholder)

	plate = _build_plate()


## Frees both halves. The rig lives in a viewport and the plate in the control
## layer, so a departing fighter has to drop both.
func dispose() -> void:
	if is_instance_valid(rig_root):
		rig_root.queue_free()
	if is_instance_valid(plate):
		plate.queue_free()


## Applies one character's public state.
##
## `view` carries the interaction state the shell worked out: "tint",
## "clickable", "selected", "target", "acting_side".
func bind(character: Dictionary, view: Dictionary) -> void:
	position_rank = int(character.get("position", 4))
	var was_alive := _alive
	_alive = bool(character.get("is_alive", true))

	var tint: Color = view.get("tint", UiTheme.COLOR_PLAYER_ONE)
	# "The Scribe" costs four characters to the article that carry no meaning,
	# and at four ranks a side the plate has no room to spare. The full name
	# stays in the tooltip and the claim record.
	_name_label.text = _short_name(str(character.get("display_name", character_id)))
	# A label in an expanding row reports a near-zero minimum, so without this
	# the row squeezes it and the name is cut on a plate that was sized to fit
	# it. This is the width name_width() then reports up to the board.
	var name_font := _name_label.get_theme_font("font")
	if name_font != null:
		_name_label.custom_minimum_size.x = ceilf(name_font.get_string_size(
			_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_name_label.get_theme_font_size("font_size"),
		).x)
	_name_label.add_theme_color_override("font_color", UiTheme.COLOR_INK if _alive else UiTheme.COLOR_DISABLED)
	_rank_label.text = "%d" % position_rank

	var max_hp := maxi(1, int(character.get("max_hp", 1)))
	var hp := clampi(int(character.get("hp", 0)), 0, max_hp)
	_health_bar.max_value = max_hp
	_health_bar.value = hp
	_health_bar.tooltip_text = "%d / %d HP" % [hp, max_hp]
	var fill := UiTheme.health_color(float(hp) / float(max_hp))
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = fill
	bar_style.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", bar_style)

	var clickable := bool(view.get("clickable", false)) and _alive
	plate.disabled = not clickable
	plate.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	_apply_plate_style(UiTheme.team_card_style(tint, _plate_state(view, clickable)))

	_render_stamps(character, view)
	# The plate replaced the card as the place a character is read, so it has to
	# carry what the card carried: the full stat line and both kit effects. They
	# are public information the whole game reasons about, so they cannot be
	# reachable only by clicking.
	plate.tooltip_text = _tooltip(character)

	# A character that just died drops out of its idle loop and stays down, so
	# the field never shows a corpse breathing.
	if was_alive and not _alive:
		_settle_defeated()
	if _placeholder != null:
		_placeholder.modulate = Color(1, 1, 1, 1.0 if _alive else 0.4)
	elif _rig != null:
		_rig.modulate = Color(1, 1, 1, 1.0 if _alive else 0.4)


## The name as it fits on a plate: the character's own word, without the article.
static func _short_name(display_name: String) -> String:
	var words := display_name.strip_edges().split(" ", false)
	for word: String in words:
		if word.to_lower() == "the":
			continue
		return word.to_upper()
	return display_name.to_upper()


## The full plate tooltip: the stat line, the rank multiplier, then each kit
## effect in full. Mirrors the card tooltip it replaced — the information is
## public, so moving the board to figures must not make it harder to reach.
func _tooltip(character: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(str(character.get("display_name", character_id)))
	lines.append("HP %d/%d   ATK %+d   DEF %+d   DMG %d   INIT %d" % [
		int(character.get("hp", 0)),
		int(character.get("max_hp", 0)),
		int(character.get("attack", 0)),
		int(character.get("defence", 0)),
		int(character.get("damage", 0)),
		int(character.get("initiative", 0)),
	])
	var rank := int(character.get("position", 0))
	lines.append("Position %d  (damage taken %s)" % [
		rank, str(POSITION_LABELS.get(rank, "100%")),
	])
	for description in Kits.effect_descriptions(character_id):
		lines.append("")
		lines.append("%s — %s" % [description["name"], description["text"]])
	return "
".join(lines)


## Which card state the plate paints. Selection and targeting outrank the
## quieter cues, because those two are the ones a click is about to act on.
func _plate_state(view: Dictionary, clickable: bool) -> String:
	if not _alive:
		return "defeated"
	if bool(view.get("selected", false)):
		return "selected"
	if bool(view.get("target", false)):
		return "legal_target"
	if clickable:
		return "ready"
	return "normal"


## The tags under the name: the rank multiplier, and whatever statuses the
## reducer has put on this character.
func _render_stamps(character: Dictionary, view: Dictionary) -> void:
	for child in _stamp_row.get_children():
		child.queue_free()
	for child in _kit_row.get_children():
		child.queue_free()
	if not _alive:
		_stamp_row.add_child(Widgets.patch("DOWN", UiTheme.COLOR_DISABLED, 8))
		return
	if bool(view.get("target", false)):
		_stamp_row.add_child(Widgets.patch("TARGET", UiTheme.COLOR_DANGER, 8))
	var statuses: Array = character.get("statuses", [])
	for status in statuses:
		_stamp_row.add_child(Widgets.patch(str(status).to_upper(), UiTheme.COLOR_INFO, 8))

	# Both kit effects are named on the plate itself. Kits are public: an
	# opponent reasons about them every claim, so they must be readable without
	# hovering anything.
	for description in Kits.effect_descriptions(character_id):
		var kit_patch := Widgets.patch(str(description["name"]).to_upper(), UiTheme.COLOR_ACCENT, 8)
		kit_patch.tooltip_text = "%s
%s" % [description["name"], description["text"]]
		_kit_row.add_child(kit_patch)


## The plate width this fighter needs to print its name in full.
##
## Measured off the assembled rows rather than re-derived from the font, so it
## accounts for the rank digit, the row separation, and the stylebox margins
## without a second copy of the plate's own geometry that could drift from it.
func name_width() -> float:
	if plate == null:
		return float(PLATE_MIN_WIDTH)
	return maxf(PLATE_MIN_WIDTH, ceilf(plate.get_combined_minimum_size().x))


## Positions the plate under a figure standing at `anchor` on the field.
##
## `compact` drops the kit row: at the smallest window four plates a side cannot
## hold both effect names legibly, and the names are still on the plate tooltip
## and the claim record, so nothing becomes unreachable.
func place_plate(anchor: Vector2, width: float, field_size: Vector2, compact: bool = false) -> void:
	_kit_row.visible = not compact
	# Below a readable name the plate keeps only the rank and the health bar.
	# A clipped word is worse than no word: the name is still on the tooltip,
	# but a health bar has no other home on the field. The stamps stay whatever
	# the width — TARGET and DOWN are the two cues a player acts on, and the
	# plate is the only place either of them appears.
	#
	# The board asks name_width() before choosing this width, so in practice the
	# name prints in full; this is the fallback for a field too narrow for that.
	_name_label.visible = width + 0.5 >= name_width()
	# Width is the board's call; height is the plate's own, and it has to be
	# asked for after the rows inside it are laid out or the plate collapses to
	# its stylebox margins and clips every line. reset_size() then re-measures.
	var height := maxf(PLATE_MIN_HEIGHT, plate.get_combined_minimum_size().y)
	plate.size = Vector2(width, height)
	var x := clampf(anchor.x - width * 0.5, 2.0, maxf(2.0, field_size.x - width - 2.0))
	# The plate and everything hanging off it must stay inside the field, or a
	# status patch prints over the panel edge.
	var y := minf(anchor.y + PLATE_DROP, field_size.y - height - 2.0)
	plate.position = Vector2(x, y)


# --- animation beats -------------------------------------------------------
#
# Each of these asks the rig's state machine to travel to a beat. They are safe
# to call on a fighter with no rig, which simply has nothing to play.


## Starts the idle loop. Called once the rig is inside the tree, because an
## AnimationTree has no playback object before then.
func start_idle() -> void:
	if _rig == null or not _rig.is_inside_tree():
		return
	var tree := _rig.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		return
	tree.active = true
	_playback = tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		return
	_playback.start(FighterRigs.animation_for(character_id, FighterRigs.BEAT_IDLE))


## Plays one beat. `variant` picks among a rig's several attacks; pass the
## exchange number so a replay swings the same way on both peers.
func play(beat: String, variant: int = 0) -> void:
	if UiTheme.reduced_motion:
		return
	if _playback == null:
		start_idle()
	if _playback == null or not _alive:
		return
	var animation := FighterRigs.animation_for(character_id, beat, variant)
	if animation == &"":
		return
	_playback.travel(animation)


## Queues a beat to play once the current one returns to idle.
##
## The state machine has no queue of its own, so this polls the playback rather
## than guessing a duration: an animation whose length changes in the editor
## still chains correctly.
func play_after(beat: String, variant: int = 0) -> void:
	if UiTheme.reduced_motion or _playback == null:
		return
	if not is_instance_valid(plate) or not plate.is_inside_tree():
		return
	var tree := plate.get_tree()
	if tree == null:
		return
	_pending_beat = beat
	_pending_variant = variant
	if _pending_poll:
		return
	_pending_poll = true
	_poll_pending(tree)


## Waits out the current beat, then plays the queued one. Bounded so a rig that
## never leaves its animation cannot hold the poll open for the whole match.
func _poll_pending(tree: SceneTree) -> void:
	for _attempt in 240:
		await tree.process_frame
		if not is_instance_valid(plate):
			_pending_poll = false
			return
		if not is_animating():
			break
	_pending_poll = false
	if _pending_beat.is_empty():
		return
	var beat := _pending_beat
	var variant := _pending_variant
	_pending_beat = ""
	play(beat, variant)


## Flashes the figure when one of its kit effects fires, so a number named in the
## reveal has something on the field to point at. Pure decoration: an effect that
## cannot be flashed is still spelled out in the sequence text.
func pulse_effect(_effect: String) -> void:
	if UiTheme.reduced_motion or not is_instance_valid(plate) or not plate.is_inside_tree():
		return
	var tween := plate.create_tween()
	tween.tween_property(plate, "modulate", Color(1.25, 1.15, 0.85), 0.12)
	tween.tween_property(plate, "modulate", Color(1, 1, 1), 0.22)


## Whether this fighter is showing something other than its idle loop. The shell
## waits on this before moving the board on, so a beat is never cut off.
func is_animating() -> bool:
	if _playback == null:
		return false
	return _playback.get_current_node() != FighterRigs.animation_for(character_id, FighterRigs.BEAT_IDLE)


## Stops a defeated fighter on its last flinch rather than looping an idle.
func _settle_defeated() -> void:
	if _playback == null:
		return
	var hurt := FighterRigs.animation_for(character_id, FighterRigs.BEAT_HURT)
	if hurt != &"" and not UiTheme.reduced_motion:
		_playback.travel(hurt)


## The stand-in figure for a character with no rig yet: the portrait placeholder
## as a paper standee on the same ground line, so the formation still reads.
func _build_placeholder() -> Node2D:
	var node := Node2D.new()
	var body := ColorRect.new()
	body.color = UiTheme.COLOR_CARDBOARD
	# Sized in rig units so the board scales it exactly like a real rig.
	var width := FighterRigs.RIG_HEIGHT * 0.22
	body.size = Vector2(width, FighterRigs.RIG_HEIGHT * 0.52)
	body.position = Vector2(-width * 0.5, FighterRigs.RIG_GROUND - body.size.y)
	node.add_child(body)

	# The board mirrors the whole rig root so player 2 faces left. A letter is
	# not a figure: counter-flipping it here keeps the standee readable instead
	# of printing it backwards.
	var text_holder := Node2D.new()
	if player == 1:
		text_holder.scale = Vector2(-1, 1)
	node.add_child(text_holder)

	var initial := Label.new()
	initial.text = _initial()
	initial.add_theme_font_size_override("font_size", int(FighterRigs.RIG_HEIGHT * 0.13))
	initial.add_theme_color_override("font_color", UiTheme.COLOR_INK)
	initial.size = body.size
	initial.position = body.position
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_holder.add_child(initial)
	return node


func _initial() -> String:
	if character_id.is_empty():
		return "?"
	return character_id.substr(0, 1).to_upper()


## Paints one card style across every button state.
##
## A Button asks for a stylebox per state, so a single card look has to be
## applied five times or hover and focus fall back to the engine default and the
## plate stops looking like the paper it is made of.
func _apply_plate_style(style: StyleBoxFlat) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var variant := style.duplicate() as StyleBoxFlat
		if state == "hover":
			variant.bg_color = variant.bg_color.lightened(0.06)
		elif state == "focus":
			variant.border_color = UiTheme.COLOR_ACCENT_DARK
			variant.set_border_width_all(3)
			variant.border_width_left = 8
		plate.add_theme_stylebox_override(state, variant)


## The nameplate: a Button so the whole plate is one click target and one focus
## stop, with the readable rows drawn inside it.
func _build_plate() -> PlateButton:
	# Godot asks the hovered control itself for its tooltip node, so the plate
	# has to be a button that carries the rules tooltip builder rather than a
	# plain one, or the stat line falls back to the engine default.
	var node := PlateButton.new()
	node.focus_mode = Control.FOCUS_ALL
	node.pressed.connect(func() -> void: clicked.emit(player, character_id))

	# A MarginContainer rather than an anchored child: an anchored VBox
	# contributes nothing to its parent's minimum size, so the plate collapsed to
	# its own stylebox margins and clipped every row inside it. Laid out as a
	# real child, the plate is as tall as its contents need.
	var frame := MarginContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		frame.add_theme_constant_override("margin_%s" % side, 2)
	node.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	_rank_label = Widgets.label("4", 9, UiTheme.COLOR_INK_MUTED)
	title.add_child(_rank_label)
	# Not clip_text: a clipping label reports a near-zero minimum width, so the
	# row happily squeezes it to nothing and the name is cut even on a plate that
	# was sized to fit it. The board asks name_width() and gives the plate the
	# room, and the label is left to insist on that room.
	_name_label = Widgets.label("", 10, UiTheme.COLOR_INK)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_name_label)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size.y = 6
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_health_bar)

	_stamp_row = HBoxContainer.new()
	_stamp_row.add_theme_constant_override("separation", 3)
	_stamp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stamp_row)

	_kit_row = HBoxContainer.new()
	_kit_row.add_theme_constant_override("separation", 3)
	# The kit patches carry their own rules tooltips, so this row passes hover
	# through to them rather than swallowing it for the plate.
	_kit_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_kit_row)
	return node
