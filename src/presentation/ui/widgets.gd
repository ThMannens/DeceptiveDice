extends RefCounted

## The small craft-material pieces every other presentation component is built
## from: labels, stitched patches, prop buttons, paper surfaces, and headings.
##
## These live here rather than in main.gd so a component can be written without
## reaching back into the shell, and so the LARP material language is applied in
## exactly one place per piece.

const UiTheme = preload("res://src/presentation/theme.gd")
const RulesTooltip = preload("res://src/presentation/rules_tooltip.gd")


static func label(text: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrapped_label(text: String, font_size: int, color: Color) -> Label:
	var node := label(text, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func centered_label(text: String, font_size: int, color: Color) -> Label:
	var node := label(text, font_size, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


## A stitched fabric patch: a status, a kit effect, or a small state tag. Always
## carries its text, because colour alone is never a state cue here.
##
## Built as a RulesTooltip rather than a bare PanelContainer because Godot asks
## the hovered control itself for its tooltip node, so the builder has to live on
## the patch or the player gets the plain engine default.
static func patch(text: String, color: Color, font_size: int = 10, state: String = "normal") -> PanelContainer:
	var node := RulesTooltip.new()
	node.add_theme_stylebox_override("panel", UiTheme.patch_style(color, state))
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ink := UiTheme.COLOR_INK if state != "stamped" else UiTheme.ink_on(color)
	node.add_child(label(text, font_size, ink))
	return node


## A rubber-stamp label: the loud, inked outcome marks (CAUGHT, LOCKED IN).
static func stamp(text: String, color: Color, font_size: int = 13) -> PanelContainer:
	return patch(text, color, font_size, "stamped")


## A paper surface of the given stock. See UiTheme.paper_style for the kinds.
static func paper(kind: String = "normal") -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", UiTheme.paper_style(kind))
	return node


## A prop button. `kind` is "primary", "secondary", "stamp", or "quiet"; the
## whole state set is styled so keyboard focus stays as loud as mouse hover.
static func button(text: String, kind: String = "secondary") -> Button:
	var node := Button.new()
	node.text = text
	# The accessibility floor for a functional control. Width comes from the
	# layout; height is the one the containers would otherwise shrink away.
	node.custom_minimum_size.y = 40
	node.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		node.add_theme_stylebox_override(state, UiTheme.prop_button_style(kind, state))

	var fill := UiTheme.COLOR_CARDBOARD
	match kind:
		"primary":
			fill = UiTheme.COLOR_ACCENT
		"stamp":
			fill = UiTheme.COLOR_DANGER
		"quiet":
			fill = UiTheme.COLOR_PARCHMENT
	var ink := UiTheme.ink_on(fill)
	node.add_theme_color_override("font_color", ink)
	node.add_theme_color_override("font_hover_color", ink)
	node.add_theme_color_override("font_pressed_color", ink)
	node.add_theme_color_override("font_disabled_color", UiTheme.COLOR_INK_MUTED)
	return node


## A section heading: small caps over a painted rule, the way a hand-lettered
## score sheet divides its columns.
static func heading(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var text_label := label(text.to_upper(), 13, UiTheme.COLOR_INK)
	text_label.add_theme_constant_override("line_spacing", 0)
	box.add_child(text_label)
	box.add_child(rule(UiTheme.COLOR_ACCENT_DARK, 2))
	return box


## A painted horizontal rule.
static func rule(color: Color, thickness: int = 2) -> PanelContainer:
	var node := PanelContainer.new()
	node.custom_minimum_size.y = thickness
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(1)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	node.add_theme_stylebox_override("panel", style)
	return node


## A vertical spacer of a fixed height, for separating blocks inside a column.
static func spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	return node


## A control that eats the remaining space in a row or column.
static func filler() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


## A patch on its own row, left aligned rather than stretched across the column.
static func patch_row(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(patch(text, color))
	row.add_child(filler())
	return row
