extends RefCounted

## Character portraits: the hand-drawn faces on every card, and the placeholder
## that stands in until a clean export exists.
##
## The placeholder is deliberately not a stock avatar. It is the character's
## initial on cloth-taped card with the prop they are known for, so a player can
## still tell the five apart at roster size before any art lands.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")

const PORTRAIT_DIR := "res://src/presentation/assets/portraits"

## The prop each LARPer turns up with. Drawn in the same dark stroke as the
## faces will be, so the placeholder and a finished portrait sit in the same
## frame without a second visual language.
const PROPS := {
	"ledger": "✎",
	"bruiser": "⚒",
	"mirror": "⛨",
	"gambler": "⚅",
	"hook": "⚓",
}


## True when a production export exists for this character. Kept as its own
## check so a caller can report which portraits are still placeholders without
## having to build the node first.
static func has_portrait(character_id: String) -> bool:
	return ResourceLoader.exists(portrait_path(character_id))


static func portrait_path(character_id: String) -> String:
	return "%s/%s.png" % [PORTRAIT_DIR, character_id]


## A framed portrait at the given edge length. Falls back to the placeholder
## whenever the export is absent, so a missing file is a visual state and never
## an error.
static func build(character_id: String, display_name: String, tint: Color, size: int, alive: bool = true) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(size, size)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(UiTheme.RADIUS_CARD)
	style.set_border_width_all(2)
	style.border_color = UiTheme.COLOR_INK if alive else UiTheme.COLOR_DISABLED
	# The pale ownership tint belongs to the portrait well, which is the one
	# place a wash of player colour cannot be mistaken for an outcome.
	style.bg_color = _pale(tint) if alive else UiTheme.COLOR_CARDBOARD
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", style)

	if has_portrait(character_id):
		var texture := TextureRect.new()
		texture.texture = load(portrait_path(character_id))
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not alive:
			texture.modulate = Color(1, 1, 1, 0.45)
		frame.add_child(texture)
		return frame

	frame.add_child(_placeholder(character_id, display_name, tint, size, alive))
	return frame


## The stand-in face: the character's initial with their prop tucked beside it.
static func _placeholder(character_id: String, display_name: String, tint: Color, size: int, alive: bool) -> Control:
	var stack := CenterContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(column)

	var ink := UiTheme.COLOR_INK if alive else UiTheme.COLOR_DISABLED
	var initial := _initial(display_name)
	var initial_label := Widgets.centered_label(initial, maxi(12, int(size * 0.44)), ink)
	column.add_child(initial_label)

	var prop := str(PROPS.get(character_id, "❖"))
	var prop_label := Widgets.centered_label(prop, maxi(9, int(size * 0.24)), ink)
	column.add_child(prop_label)
	return stack


## The letter to print: the first letter of the character's own name rather than
## the article, so "The Ledger" reads as L and not as a column of Ts.
static func _initial(display_name: String) -> String:
	var words := display_name.strip_edges().split(" ", false)
	for word: String in words:
		if word.to_lower() == "the":
			continue
		return word.substr(0, 1).to_upper()
	return display_name.substr(0, 1).to_upper()


## The pale ownership wash behind a placeholder face.
static func _pale(tint: Color) -> Color:
	if tint.is_equal_approx(UiTheme.COLOR_PLAYER_TWO):
		return UiTheme.COLOR_PLAYER_TWO_LIGHT
	if tint.is_equal_approx(UiTheme.COLOR_PLAYER_ONE):
		return UiTheme.COLOR_PLAYER_ONE_LIGHT
	return UiTheme.COLOR_PARCHMENT
