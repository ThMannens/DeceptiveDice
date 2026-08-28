extends RefCounted

## Visual language for Deceptive Dice.
##
## The prototype is a game of hidden rolls and bluffing, so the look leans on a
## dark felt table, warm brass accents, and card-like surfaces with a raised
## edge. Every widget the interface builds goes through this file, which keeps
## the styling in one place instead of spread across the render functions.

# Table surface, from deepest to nearest the player.
const COLOR_BACKDROP := Color("07090f")
const COLOR_FELT := Color("11172a")
const COLOR_FELT_EDGE := Color("1d2740")
const COLOR_PANEL := Color("161d31")
const COLOR_PANEL_ALT := Color("1f2942")
const COLOR_PANEL_RAISED := Color("27334f")

# Brass accents.
const COLOR_ACCENT := Color("e8b552")
const COLOR_ACCENT_BRIGHT := Color("ffd68a")
const COLOR_ACCENT_DARK := Color("6d4f1d")
const COLOR_ACCENT_DEEP := Color("40301a")

# Type.
const COLOR_TEXT := Color("f4f1e6")
const COLOR_MUTED := Color("8f9ab4")
const COLOR_FAINT := Color("5c6782")

# Semantic.
const COLOR_DANGER := Color("e46f61")
const COLOR_SUCCESS := Color("6fc48a")
const COLOR_PLAYER_ONE := Color("5f9eea")
const COLOR_PLAYER_TWO := Color("d978a7")

# A defeated character's card desaturates toward this.
const COLOR_DEFEATED := Color("241d24")

const RADIUS_PANEL := 14
const RADIUS_CARD := 10
const RADIUS_BUTTON := 9


## A flat surface with a soft border and rounded corners.
static func panel_style(
	color: Color,
	radius: int = RADIUS_PANEL,
	border_color: Color = Color(0, 0, 0, 0),
	border_width: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	if border_width > 0:
		style.set_border_width_all(border_width)
		style.border_color = border_color
	return style


## The main framed surfaces: a lifted panel with a hairline edge and a drop
## shadow, so the layout reads as stacked physical pieces instead of flat boxes.
static func surface_style(color: Color, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var style := panel_style(color, radius, COLOR_FELT_EDGE, 1)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


## A surface that carries a coloured top edge, used to tag a panel as belonging
## to one player without tinting the whole card.
static func accented_surface_style(color: Color, accent: Color, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var style := surface_style(color, radius)
	style.border_width_top = 3
	style.border_color = accent
	return style


static func card_style(color: Color, accent: Color, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = 11
	style.content_margin_right = 11
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.set_border_width_all(1)
	style.border_color = COLOR_FELT_EDGE
	# The acting side's ready characters get a bright left spine so the player
	# can find who can still move at a glance.
	style.border_width_left = 4
	style.border_color = accent if highlighted else COLOR_FELT_EDGE
	if highlighted:
		style.shadow_color = Color(accent, 0.20)
		style.shadow_size = 5
	return style


static func button_style(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.set_border_width_all(border_width)
	style.border_color = border
	return style


## Builds the Theme applied to the whole interface. Doing this once means the
## stock Godot widgets (OptionButton, SpinBox, TextEdit, ProgressBar, scrollbars)
## stop looking like the editor defaults.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15

	_style_buttons(theme)
	_style_inputs(theme)
	_style_progress(theme)
	_style_scrollbars(theme)
	_style_misc(theme)
	return theme


static func _style_buttons(theme: Theme) -> void:
	# Secondary buttons: outlined, quiet until hovered.
	var normal := button_style(COLOR_PANEL_ALT, COLOR_FELT_EDGE)
	var hover := button_style(COLOR_PANEL_RAISED, COLOR_ACCENT_DARK)
	var pressed := button_style(COLOR_FELT, COLOR_ACCENT_DARK)
	var disabled := button_style(Color(COLOR_PANEL_ALT, 0.45), Color(COLOR_FELT_EDGE, 0.5))

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", button_style(Color(0, 0, 0, 0), COLOR_ACCENT, 2))
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_ACCENT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_disabled_color", "Button", COLOR_FAINT)
	theme.set_font_size("font_size", "Button", 15)


static func _style_inputs(theme: Theme) -> void:
	var field := button_style(COLOR_FELT, COLOR_FELT_EDGE)
	field.content_margin_top = 6
	field.content_margin_bottom = 6

	for type in ["OptionButton", "LineEdit", "TextEdit", "SpinBox"]:
		theme.set_stylebox("normal", type, field)
		theme.set_color("font_color", type, COLOR_TEXT)

	var field_hover := field.duplicate() as StyleBoxFlat
	field_hover.border_color = COLOR_ACCENT_DARK
	theme.set_stylebox("hover", "OptionButton", field_hover)
	theme.set_stylebox("pressed", "OptionButton", field_hover)
	theme.set_stylebox("focus", "OptionButton", button_style(Color(0, 0, 0, 0), COLOR_ACCENT, 2))
	theme.set_color("font_color", "OptionButton", COLOR_TEXT)
	theme.set_color("font_hover_color", "OptionButton", COLOR_ACCENT_BRIGHT)

	# The dropdown list that OptionButton opens.
	var popup := panel_style(COLOR_PANEL_ALT, RADIUS_CARD, COLOR_ACCENT_DARK, 1)
	popup.content_margin_left = 6
	popup.content_margin_right = 6
	popup.content_margin_top = 6
	popup.content_margin_bottom = 6
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", button_style(COLOR_ACCENT_DEEP, Color(0, 0, 0, 0), 0))
	theme.set_color("font_color", "PopupMenu", COLOR_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_ACCENT_BRIGHT)

	theme.set_stylebox("normal", "TextEdit", field)
	theme.set_stylebox("focus", "TextEdit", button_style(COLOR_FELT, COLOR_ACCENT, 2))
	theme.set_color("font_color", "TextEdit", COLOR_TEXT)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_FAINT)
	theme.set_color("caret_color", "TextEdit", COLOR_ACCENT)
	theme.set_color("selection_color", "TextEdit", Color(COLOR_ACCENT, 0.28))


static func _style_progress(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = COLOR_BACKDROP
	track.set_corner_radius_all(5)
	track.set_border_width_all(1)
	track.border_color = COLOR_FELT_EDGE
	theme.set_stylebox("background", "ProgressBar", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_SUCCESS
	fill.set_corner_radius_all(5)
	theme.set_stylebox("fill", "ProgressBar", fill)


static func _style_scrollbars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.25)
	track.set_corner_radius_all(4)
	track.content_margin_left = 3
	track.content_margin_right = 3

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = COLOR_PANEL_RAISED
	grabber.set_corner_radius_all(4)

	var grabber_hover := grabber.duplicate() as StyleBoxFlat
	grabber_hover.bg_color = COLOR_ACCENT_DARK

	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, grabber_hover)
		theme.set_stylebox("grabber_pressed", type, grabber_hover)


static func _style_misc(theme: Theme) -> void:
	var separator := StyleBoxLine.new()
	separator.color = COLOR_FELT_EDGE
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)

	_style_tooltips(theme)


## The tooltip background. Fully opaque, because a tooltip sits over character
## cards and stat text: any transparency lets the wording underneath bleed
## through, which is what makes the engine default unreadable here.
static func tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_RAISED
	style.set_corner_radius_all(RADIUS_PANEL)
	style.set_border_width_all(1)
	style.border_color = COLOR_ACCENT_DARK
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


## Tooltips carry the kit rules, so they have to be readable over the board
## rather than the engine default, which is a near-transparent dark box.
static func _style_tooltips(theme: Theme) -> void:
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style())

	theme.set_color("font_color", "TooltipLabel", COLOR_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 13)
	# The engine draws tooltip text with an outline by default, which smears the
	# small type. Turn it off now that the panel behind it is solid.
	theme.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	theme.set_constant("shadow_outline_size", "TooltipLabel", 0)
	theme.set_constant("shadow_offset_x", "TooltipLabel", 0)
	theme.set_constant("shadow_offset_y", "TooltipLabel", 0)

	theme.set_color("default_color", "RichTextLabel", COLOR_MUTED)
	theme.set_font_size("normal_font_size", "RichTextLabel", 14)
	theme.set_color("font_color", "Label", COLOR_TEXT)


## Health bar colour shifts from healthy green through amber to red as a
## character is worn down, so damage is legible without reading the numbers.
static func health_color(fraction: float) -> Color:
	if fraction > 0.6:
		return COLOR_SUCCESS
	if fraction > 0.3:
		return COLOR_ACCENT
	return COLOR_DANGER
