extends PanelContainer

## The field both crews stand on: eight animated fighters on one ground line,
## the two teams facing each other, with a clickable nameplate under each.
##
## This is the primary board. It replaces the paper roster columns, so it has to
## carry everything those carried — who is who, how hurt they are, whose turn it
## is, what is selectable right now — without becoming a second rules engine.
## Like every other component here it accepts state and reports clicks; it never
## queries the reducer and never decides what is legal.
##
## Formation reads outward from the centre: position 4 stands closest to the
## opponent and position 1 farthest back, on both sides. That is the same order
## the rules use for the position damage multiplier, so a player can read the
## board rather than remember the table.

const UiTheme = preload("res://src/presentation/theme.gd")
const FighterRigs = preload("res://src/presentation/ui/fighter_rigs.gd")
const Fighter = preload("res://src/presentation/ui/fighter.gd")

signal fighter_clicked(player: int, character_id: String)

## How much of the field's height one figure takes. The rig is scaled to this,
## so the board is legible at the 1024x640 floor without the art dictating a
## minimum the decision footer would have to pay for.
const FIGURE_HEIGHT_RATIO := 1.0

## The ground line, as a fraction of the field's height. Figures stand on it and
## the nameplates hang below, which leaves the upper field free for the banner
## the stage prints over the top.
const GROUND_RATIO := 0.72

## The gap between neighbouring fighters on one side, as a fraction of a figure's
## width. Above 1.0 so the ranks stand clear of each other: overlapping figures
## made two crews read as one crowd, and the nameplates ran together into a
## single illegible strip.
const RANK_SPACING := 1.15

## How far the two front ranks stay apart, as a fraction of the field width. The
## centre has to stay clear: it is where the exchange banner and the clash sit.
const CENTRE_GAP := 0.13

## The least height the field may take: the plate band plus enough room above it
## that a figure still reads as one.
##
## The decision footer outranks the field. This floor is deliberately small
## enough that 1024x640 still fits every primary control above the fold, which
## the UI smoke test asserts — a taller field would look better and cost the
## player the button they need.
const MIN_FIELD_HEIGHT := 210

## The band under the ground line the nameplates hang in. Reserved rather than
## derived, so a short field shrinks the figures and never the plates.
const PLATE_BAND := 70

## Headroom kept above the figures for the exchange banner that prints over the
## top of the field.
const BANNER_CLEARANCE := 84

## The plate width below which the kit names stop fitting and the row is dropped.
## The field decides this from its own measurements rather than from the window
## tier, so a narrow field folds the same way whatever put it there.
const KIT_ROW_MIN_WIDTH := 168

var _viewport: SubViewport
var _viewport_holder: SubViewportContainer
var _world: Node2D
var _plate_layer: Control
## Every fighter on the field, keyed "<player>:<character_id>". Held so a
## resolution can animate one fighter without rebuilding the board.
var _fighters: Dictionary = {}
var _field_size := Vector2.ZERO


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_style("well"))
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The field is the board now, so unlike the stage it replaced it cannot be
	# squeezed to nothing: the nameplates are the only place a character's health
	# and rank are readable. This floor is what the plates need, and it still
	# leaves the decision footer its full height at the 1024x640 minimum.
	custom_minimum_size = Vector2(0, MIN_FIELD_HEIGHT)

	_viewport_holder = SubViewportContainer.new()
	_viewport_holder.stretch = true
	_viewport_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The rigs are art. Clicks belong to the nameplates above them, which are
	# real Controls and therefore reachable by keyboard.
	_viewport_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_holder)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport_holder.add_child(_viewport)

	_world = Node2D.new()
	_viewport.add_child(_world)

	_plate_layer = Control.new()
	_plate_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate_layer)

	resized.connect(_on_resized)


## The fighter node for one character, so a resolution sequence can drive a
## single figure without knowing how the field laid the ranks out. Null when the
## character is not on the board.
func fighter_for(player: int, character_id: String) -> Fighter:
	return _fighters.get(_key(player, character_id))


## Draws both crews.
##
## `view` carries what the field cannot work out for itself: "tints" (a colour
## per player), "clickable" (a list of "<player>:<id>" keys the shell has decided
## are selectable now), "selected", "target", and "active_player".
func render(teams: Array, view: Dictionary) -> void:
	var wanted := {}
	for player in mini(teams.size(), 2):
		for character in teams[player]["characters"]:
			wanted[_key(player, str(character["id"]))] = true

	# Fighters persist across renders: rebuilding them every phase would restart
	# every idle animation and lose whatever beat a resolution is mid-way
	# through. Only departures are freed.
	for key: String in _fighters.keys():
		if not wanted.has(key):
			var leaving: Fighter = _fighters[key]
			_fighters.erase(key)
			leaving.dispose()

	var tints: Array = view.get("tints", [UiTheme.COLOR_PLAYER_ONE, UiTheme.COLOR_PLAYER_TWO])
	for player in mini(teams.size(), 2):
		for character in teams[player]["characters"]:
			_sync_fighter(player, character, tints[player], view)

	_layout()


## Creates or updates one fighter to match its character state.
func _sync_fighter(player: int, character: Dictionary, tint: Color, view: Dictionary) -> void:
	var character_id := str(character["id"])
	var key := _key(player, character_id)
	var fighter: Fighter = _fighters.get(key)
	if fighter == null:
		fighter = Fighter.new(player, character_id)
		fighter.clicked.connect(_on_fighter_clicked)
		_fighters[key] = fighter
		_world.add_child(fighter.rig_root)
		_plate_layer.add_child(fighter.plate)
		# An AnimationTree has no playback object until it is inside the tree, so
		# the idle loop can only start once the rig has been parented.
		fighter.start_idle()

	var clickable: Array = view.get("clickable", [])
	fighter.bind(character, {
		"tint": tint,
		"clickable": key in clickable,
		"selected": str(view.get("selected", "")) == key,
		"target": str(view.get("target", "")) == key,
		"acting_side": int(view.get("active_player", -1)) == player,
	})


func _on_fighter_clicked(player: int, character_id: String) -> void:
	fighter_clicked.emit(player, character_id)


func _on_resized() -> void:
	if size.is_equal_approx(_field_size):
		return
	_field_size = size
	_layout()


## Places both crews on the ground line and hangs each nameplate beneath its
## figure.
##
## Player 0 stands on the left facing right, player 1 on the right facing left.
## Within a side the ranks run outward from the centre, so position 4 — the one
## the rules hit hardest — is the one visibly at the front.
func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# The plates get a fixed band at the bottom and the figures take what is
	# left, so squeezing the field shortens the fighters rather than pushing
	# their health bars off the edge.
	var ground_y := maxf(size.y * GROUND_RATIO, size.y - PLATE_BAND)
	var figure_room := maxf(40.0, ground_y - BANNER_CLEARANCE)
	var scale_factor := figure_room * FIGURE_HEIGHT_RATIO / FighterRigs.RIG_HEIGHT
	# The rig's origin sits at hip height, so standing it on the ground line
	# means lifting it by the scaled distance from origin to feet.
	var feet_offset := FighterRigs.RIG_GROUND * scale_factor
	var figure_width := FighterRigs.RIG_HEIGHT * scale_factor * 0.36

	var centre := size.x * 0.5
	var inset := size.x * CENTRE_GAP * 0.5

	# Four ranks and the centre gap have to fit one half of the field, and a
	# plate is what actually has to stay legible, so the rank step is bounded by
	# the space available rather than by the figure alone. Without this the
	# plates overlap at the smallest window and the names clip to nothing.
	var half := maxf(1.0, centre - inset - 4.0)
	var step := minf(figure_width * RANK_SPACING, half / 3.0)
	var plate_width := minf(maxf(Fighter.PLATE_MIN_WIDTH, figure_width * 1.15), step - 4.0)

	for key: String in _fighters:
		var fighter: Fighter = _fighters[key]
		var facing := 1.0 if fighter.player == 0 else -1.0
		# Rank 4 stands closest to the centre line; rank 1 falls back from it.
		var rank := clampi(fighter.position_rank, 1, 4)
		var distance := inset + float(4 - rank) * step
		var x := centre - distance if fighter.player == 0 else centre + distance

		fighter.rig_root.position = Vector2(x, ground_y - feet_offset)
		fighter.rig_root.scale = Vector2(scale_factor * facing, scale_factor)
		# Nearer ranks draw over farther ones, so an overlap reads as depth
		# rather than as a mistake.
		fighter.rig_root.z_index = rank

		fighter.place_plate(Vector2(x, ground_y), plate_width, size, plate_width < KIT_ROW_MIN_WIDTH)


static func _key(player: int, character_id: String) -> String:
	return "%d:%s" % [player, character_id]
