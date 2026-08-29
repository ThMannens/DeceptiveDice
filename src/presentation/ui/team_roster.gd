extends PanelContainer

## One player's team area: a canvas panel with a cloth name tape and the four
## character cards stacked back to front.
##
## Like the card, it accepts state and reports clicks. The shell decides what
## each card's interaction state is, because that depends on the current UI
## stage and the selection, neither of which belongs to a roster.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const CharacterCard = preload("res://src/presentation/ui/character_card.gd")

signal card_clicked(player: int, character_id: String)

var player := -1

var _column: VBoxContainer
var _cards_box: VBoxContainer
var _cards: Dictionary = {}


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_style("canvas"))
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)


## The card node for a character id, so a resolution sequence can animate one
## card without knowing how the roster laid them out. Null when absent.
func card_for(character_id: String) -> CharacterCard:
	return _cards.get(character_id)


## Renders a team.
##
## `view` carries: "name" (the team's display name), "tint", "acting" (whether
## this side is on the clock), "compact", and "card_states" — a character id to
## interaction state map the shell has already worked out.
func render(owning_player: int, characters: Array, view: Dictionary) -> void:
	player = owning_player
	for child in _column.get_children():
		child.queue_free()
	_cards.clear()

	var tint: Color = view.get("tint", UiTheme.COLOR_PLAYER_ONE)
	_column.add_child(_name_tape(str(view.get("name", "")), tint, bool(view.get("acting", false))))

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 4 if bool(view.get("compact", false)) else 6)
	_column.add_child(_cards_box)

	# Back rank first, so the column reads top to bottom the way the formation
	# reads back to front.
	var ordered: Array = characters.duplicate()
	ordered.sort_custom(func(left, right): return int(left["position"]) < int(right["position"]))

	var states: Dictionary = view.get("card_states", {})
	for character in ordered:
		var character_id := str(character["id"])
		var card := CharacterCard.new()
		card.card_clicked.connect(func(p: int, id: String): card_clicked.emit(p, id))
		_cards_box.add_child(card)
		card.bind_character(owning_player, character, {
			"tint": tint,
			"state": str(states.get(character_id, CharacterCard.STATE_NORMAL)),
			"compact": bool(view.get("compact", false)),
			"clickable": character_id in view.get("clickable_ids", []),
		})
		_cards[character_id] = card


## The team's name on a strip of coloured cloth tape. This is the one place the
## player's own colour fills a surface, and it carries nothing but ownership.
func _name_tape(team_name: String, tint: Color, acting: bool) -> PanelContainer:
	var tape := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	style.border_color = UiTheme.COLOR_INK
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tape.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tape.add_child(row)
	row.add_child(Widgets.label(team_name.to_upper(), 15, UiTheme.ink_on(tint)))
	row.add_child(Widgets.label("1 back → 4 front", 10, UiTheme.ink_on(tint)))
	row.add_child(Widgets.filler())
	if acting:
		row.add_child(Widgets.stamp("ON THE CLOCK", UiTheme.COLOR_ACCENT, 10))
	return tape
