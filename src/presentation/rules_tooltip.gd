extends PanelContainer

## A panel that builds its own tooltip.
##
## Godot asks the *hovered control* for its tooltip node, not the window or any
## ancestor, so a `_make_custom_tooltip` on the root scene is never called. Any
## control that needs the rules tooltip has to carry the method itself, which is
## what this class is for.
##
## The tooltip gives kit text a bounded width and a heading, and appends the
## definition of any rules vocabulary the text actually uses. Godot tooltips are
## transient popups that cannot themselves be hovered, so a nested tooltip is not
## available: the definitions travel with the term instead.

const Kits = preload("res://src/core/kits.gd")
const UiTheme = preload("res://src/presentation/theme.gd")

## Wrap width for long lines, and the length past which a line is wrapped at all.
## A short tooltip should size to its own text rather than be padded out.
const WRAP_WIDTH := 330
const WRAP_THRESHOLD := 46


func _make_custom_tooltip(for_text: String) -> Object:
	return build_tooltip(for_text)


## Builds the tooltip node for `for_text`. Static so the same construction is
## available to any caller that needs to render one outside a hover.
static func build_tooltip(for_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.tooltip_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var lines := for_text.split("\n")
	for index in lines.size():
		var line := str(lines[index])
		if line.is_empty():
			var gap := Control.new()
			gap.custom_minimum_size.y = 3
			box.add_child(gap)
			continue
		# The first line is the subject of the tooltip, so it reads as a title.
		var is_heading := index == 0
		var label := _tooltip_label(
			line,
			14 if is_heading else 13,
			# The heading is ink on parchment like the body, one size larger.
			# Orange on cream is the one accent pairing that fails the contrast
			# floor, and a tooltip is where the rules text actually lives.
			UiTheme.COLOR_INK,
		)
		if line.length() > WRAP_THRESHOLD:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = WRAP_WIDTH
		box.add_child(label)

	_append_glossary(box, for_text)
	return panel


## Defines the rules vocabulary this tooltip uses, set apart below a rule so the
## definitions read as a footnote rather than as more effect text.
static func _append_glossary(box: VBoxContainer, for_text: String) -> void:
	var entries: Array = Kits.glossary_for(for_text)
	if entries.is_empty():
		return

	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 1
	var rule_style := StyleBoxFlat.new()
	rule_style.bg_color = UiTheme.COLOR_CANVAS_DARK
	rule.add_theme_stylebox_override("panel", rule_style)
	box.add_child(rule)

	for entry in entries:
		var definition := _tooltip_label(
			"%s: %s" % [entry["label"], entry["text"]],
			12,
			UiTheme.COLOR_INK_MUTED,
		)
		definition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		definition.custom_minimum_size.x = WRAP_WIDTH
		box.add_child(definition)


static func _tooltip_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
