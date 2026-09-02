extends Button

## The nameplate under a fighter: a button that builds its own rules tooltip.
##
## Godot asks the hovered control for its tooltip node rather than any ancestor,
## so the builder has to sit on the plate itself. Without this the stat line and
## the kit text fall back to the plain engine tooltip, which is a silent failure
## the UI smoke test exists to catch.

const RulesTooltip = preload("res://src/presentation/rules_tooltip.gd")


func _make_custom_tooltip(for_text: String) -> Object:
	return RulesTooltip.build_tooltip(for_text)


## The plate is as tall as the rows inside it.
##
## A Button sizes itself from its own `text` and ignores its children, so the
## plate collapsed to its stylebox margins and clipped every row it was built to
## show. Overriding this makes it behave like the container it is being used as.
func _get_minimum_size() -> Vector2:
	var content := Vector2.ZERO
	for child in get_children():
		if child is Control and (child as Control).visible:
			content = content.max((child as Control).get_combined_minimum_size())
	var style := get_theme_stylebox("normal")
	if style != null:
		content += Vector2(
			style.content_margin_left + style.content_margin_right,
			style.content_margin_top + style.content_margin_bottom,
		)
	return content
