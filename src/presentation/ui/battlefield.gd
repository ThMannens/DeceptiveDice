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

## How much of the room above the ground line one figure takes. Well under 1.0:
## the figures are the scenery the formation is drawn on, and at full height they
## crowded the field and left the nameplates — which carry the actual reading —
## competing with them for attention.
const FIGURE_HEIGHT_RATIO := 0.56

## The ground line, as a fraction of the field's height. Figures stand on it and
## the nameplates hang below, which leaves the upper field free for the banner
## the stage prints over the top.
const GROUND_RATIO := 0.72

## The gap between neighbouring fighters on one side, as a fraction of a figure's
## width. Above 1.0 so the ranks stand clear of each other: overlapping figures
## made two crews read as one crowd, and the nameplates ran together into a
## single illegible strip.
const RANK_SPACING := 1.15

## How far the outermost rank sits from the field edge, as a fraction of the
## field width. Small, because the crews belong at the edges: the middle is the
## no man's land the exchange happens across.
const EDGE_MARGIN := 0.02

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

## The least room a figure gets above the ground line, whatever the banner would
## rather have. A figure below this stops being identifiable at a glance.
const MIN_FIGURE_ROOM := 190.0

## Headroom kept above the figures for the exchange banner that prints over the
## top of the field.
const BANNER_CLEARANCE := 84

## The clear space kept between neighbouring plates, so a row of them reads as
## separate plates rather than one strip.
const PLATE_GUTTER := 8

## The widest a rank step may grow. Past this the four ranks stop reading as one
## crew and start reading as four separate fighters that happen to share a side.
const RANK_STEP_MAX := 210

## The widest a plate may grow. Past this the plates start to read as panels in
## their own right and compete with the figures they belong to.
const PLATE_MAX_WIDTH := 190

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
	# A short field would otherwise scale the figures to specks, because the
	# banner clearance eats a fixed slice of a small number. The floor keeps them
	# recognisable; below it the banner simply overlaps them, which costs less
	# than a board whose fighters cannot be told apart.
	var figure_room := maxf(MIN_FIGURE_ROOM, ground_y - BANNER_CLEARANCE)
	var scale_factor := figure_room * FIGURE_HEIGHT_RATIO / FighterRigs.RIG_HEIGHT
	# The rig's origin sits at hip height, so standing it on the ground line
	# means lifting it by the scaled distance from origin to feet.
	var feet_offset := FighterRigs.RIG_GROUND * scale_factor
	var figure_width := FighterRigs.RIG_HEIGHT * scale_factor * 0.36

	var centre := size.x * 0.5
	var inset := size.x * CENTRE_GAP * 0.5

	# A plate has to hold the longest name on the field, not its own: every plate
	# is the same width, so a row of them reads as a row rather than as ragged
	# tabs, and the step below is what has to make room for that width.
	var widest_name := float(Fighter.PLATE_MIN_WIDTH)
	for key: String in _fighters:
		widest_name = maxf(widest_name, (_fighters[key] as Fighter).name_width())

	# The crews are pushed out to the edges: rank 1 stands an edge margin in from
	# its own side and the ranks march inward from there, so the four are spread
	# across the half rather than huddled against the centre gap.
	#
	# The plate width and the outer margin each want the other first — the margin
	# has to clear half a plate, and the plate takes what the ranks leave it. The
	# knot is cut by reserving against the widest a plate is ever allowed to be,
	# so the edge plates are guaranteed to fit whatever the field width.
	var outer := size.x * EDGE_MARGIN + _reserved_plate_width(size) * 0.5
	var half := maxf(1.0, centre - inset - outer)
	# Three gaps between four ranks. The ranks spread across the whole half-field
	# rather than only as far as the figures need, which is what puts the crews
	# out at the edges instead of bunched beside the centre gap; the figure and
	# plate widths are the floor it may not fall below.
	var step := maxf(
		minf(half / 3.0, RANK_STEP_MAX),
		maxf(figure_width * RANK_SPACING, widest_name + PLATE_GUTTER),
	)
	# The plate takes the room the step leaves it, never less than its name needs
	# and never more than a plate should be. With the crews pushed to the edges
	# the step is wide, so the kit patches fit again at the larger windows and
	# fold away only where they genuinely cannot.
	var plate_width := clampf(step - PLATE_GUTTER, minf(widest_name, step), PLATE_MAX_WIDTH)

	for key: String in _fighters:
		var fighter: Fighter = _fighters[key]
		var facing := 1.0 if fighter.player == 0 else -1.0
		# Rank 4 stands closest to the centre line; rank 1 falls back from it.
		var rank := clampi(fighter.position_rank, 1, 4)
		# Rank 1 sits at the outer edge; each rank forward steps toward the
		# centre. Anchoring outward rather than inward is what keeps the crews on
		# their own sides when the field is wide.
		var distance := inset + half - float(rank - 1) * step
		var x := centre - distance if fighter.player == 0 else centre + distance

		fighter.rig_root.position = Vector2(x, ground_y - feet_offset)
		fighter.rig_root.scale = Vector2(scale_factor * facing, scale_factor)
		# Nearer ranks draw over farther ones, so an overlap reads as depth
		# rather than as a mistake.
		fighter.rig_root.z_index = rank

		fighter.place_plate(Vector2(x, ground_y), plate_width, size, plate_width < KIT_ROW_MIN_WIDTH)


## The widest a plate could be on a field this size.
##
## Used to reserve the outer margin before the real plate width is known, which
## is what breaks the circular dependency between the two.
static func _reserved_plate_width(field_size: Vector2) -> float:
	return clampf(field_size.x * 0.125, 24.0, PLATE_MAX_WIDTH)


static func _key(player: int, character_id: String) -> String:
	return "%d:%s" % [player, character_id]
