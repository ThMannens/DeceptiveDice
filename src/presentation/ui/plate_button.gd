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
