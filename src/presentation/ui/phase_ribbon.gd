extends PanelContainer

## The hand-painted tournament score strip across the top of the board.
##
## It shows where the exchange has got to at a glance, which is the one reading
## a player needs before they read anything else. Internal phase names are
## untouched: this file owns only the display labels.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const MatchState = preload("res://src/core/match_state.gd")

## The six steps of one exchange, in order, with the internal phases each covers.
## FIGHTER through RESULT is the whole loop; draft and placement sit before it
## and get their own labels from PHASE_LABELS rather than a ribbon step.
const STEPS := [
	{"label": "FIGHTER", "phases": [MatchState.PHASE_SELECT]},
	{"label": "DICE", "phases": [MatchState.PHASE_COMMIT]},
	{"label": "BOAST", "phases": [MatchState.PHASE_CLAIM]},
	{"label": "CALL", "phases": [MatchState.PHASE_CHALLENGE]},
	{"label": "REVEAL", "phases": [MatchState.PHASE_REVEAL]},
	{"label": "RESULT", "phases": [MatchState.PHASE_RESOLVE]},
]

## Player-facing names for every internal phase. Canonical rules vocabulary
## (claim, padding, caught, wrong call, locked in) stays in the explanatory copy
## and the tooltips; these are the thematic headline only.
const PHASE_LABELS := {
	MatchState.PHASE_DRAFT: {"main": "Pick the crew", "support": "Choose four LARPers"},
	MatchState.PHASE_PLACEMENT: {"main": "Set the line", "support": "Back 1 → 4 front"},
	MatchState.PHASE_SELECT: {"main": "Pick a fighter", "support": "Choose move and target"},
	MatchState.PHASE_COMMIT: {"main": "Dice in the cup", "support": "Rolls are locked"},
	MatchState.PHASE_CLAIM: {"main": "Make your boast", "support": "Tell the truth or pad it"},
	MatchState.PHASE_CHALLENGE: {"main": "Call their bluff", "support": "Challenge or let it stand"},
	MatchState.PHASE_REVEAL: {"main": "Show the dice", "support": "Verify both rolls"},
	MatchState.PHASE_RESOLVE: {"main": "Settle the hit", "support": "Apply calls, kits, and damage"},
	MatchState.PHASE_FINISHED: {"main": "Match over", "support": "Show the winner"},
}

var _steps_row: HBoxContainer
var _timer_label: Label
var _timer_bar: PanelContainer
var _waiting_label: Label
var _current_step := -1


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_style("secondary"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	_steps_row = HBoxContainer.new()
	_steps_row.add_theme_constant_override("separation", 4)
	column.add_child(_steps_row)


## The display label pair for an internal phase, for prompts and headings that
## want the thematic wording without redefining it.
static func phase_label(phase: String) -> Dictionary:
	return PHASE_LABELS.get(phase, {"main": phase.capitalize(), "support": ""})


## Which ribbon step an internal phase belongs to, or -1 for a phase outside the
## exchange loop (draft, placement, finished).
static func step_for_phase(phase: String) -> int:
	for index in STEPS.size():
		if phase in STEPS[index]["phases"]:
			return index
	return -1


## The step index currently painted as active. Exposed so a test can assert the
## ribbon agrees with public state rather than reading pixels.
func current_step() -> int:
	return _current_step


## Repaints the ribbon for a phase.
##
## `waiting` draws the animated ellipsis on the current step; `seconds_left`
## below zero hides the timer entirely, which is the hot-seat case where a clock
## would punish a player for reading their own kit.
func render(phase: String, waiting: bool, seconds_left: int, timer_total: int = 0) -> void:
	_current_step = step_for_phase(phase)
	for child in _steps_row.get_children():
		child.queue_free()
	_timer_label = null
	_timer_bar = null
	_waiting_label = null

	for index in STEPS.size():
		_steps_row.add_child(_build_step(index, waiting))
		if index < STEPS.size() - 1:
			_steps_row.add_child(Widgets.label("→", 12, UiTheme.COLOR_INK_MUTED))

	_steps_row.add_child(Widgets.filler())

	# Outside the exchange loop the ribbon still names where the match is, so
	# draft and placement are not an unlabelled gap in the strip.
	var labels := phase_label(phase)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	heading.add_child(Widgets.label(str(labels["main"]), 15, UiTheme.COLOR_INK))
	heading.add_child(Widgets.label(str(labels["support"]), 11, UiTheme.COLOR_INK_MUTED))
	_steps_row.add_child(heading)

	if seconds_left >= 0:
		_steps_row.add_child(_build_timer(seconds_left, timer_total))


## One painted tab. Current is orange with dark ink; completed carries a tied
## cord and a check; future steps stay muted cardboard.
func _build_step(index: int, waiting: bool) -> Control:
	var completed := _current_step >= 0 and index < _current_step
	var active := index == _current_step

	var text: String = str(STEPS[index]["label"])
	if completed:
		text = "✓ " + text
	elif active and waiting:
		# The waiting cue is a printed ellipsis rather than a spinner: it has to
		# survive reduced motion, and there is nothing to spin about.
		text += " …"

	var color := UiTheme.COLOR_DISABLED
	var state := "disabled"
	if active:
		color = UiTheme.COLOR_ACCENT
		state = "stamped"
	elif completed:
		color = UiTheme.COLOR_SUCCESS
		state = "normal"
	var tab := Widgets.patch(text, color, 12, state)
	if active:
		_waiting_label = null
	return tab


## The online phase clock: exact seconds, with a stitched underline that shrinks
## as supplementary information. The number is the reading; the bar is a glance.
func _build_timer(seconds_left: int, timer_total: int) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.custom_minimum_size.x = 74

	var color := UiTheme.COLOR_INK_MUTED
	if seconds_left <= 2:
		color = UiTheme.COLOR_DANGER
	elif seconds_left <= 5:
		color = UiTheme.COLOR_WARNING
	_timer_label = Widgets.label("%ds left" % seconds_left, 13, color)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_timer_label)

	var track := PanelContainer.new()
	track.custom_minimum_size.y = 4
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = UiTheme.COLOR_CARDBOARD
	track_style.set_corner_radius_all(2)
	track.add_theme_stylebox_override("panel", track_style)
	column.add_child(track)

	_timer_bar = PanelContainer.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	_timer_bar.add_theme_stylebox_override("panel", fill)
	var fraction := 1.0 if timer_total <= 0 else clampf(float(seconds_left) / float(timer_total), 0.0, 1.0)
	_timer_bar.size_flags_horizontal = Control.SIZE_FILL
	_timer_bar.custom_minimum_size.x = 70.0 * fraction
	track.add_child(_timer_bar)
	return column


## Updates only the clock, without repainting the ribbon. The timer ticks once a
## second, and a rebuild there would reset whatever input the player is holding.
func update_timer(seconds_left: int, timer_total: int = 0) -> void:
	if _timer_label == null or not is_instance_valid(_timer_label):
		return
	var color := UiTheme.COLOR_INK_MUTED
	if seconds_left <= 2:
		color = UiTheme.COLOR_DANGER
	elif seconds_left <= 5:
		color = UiTheme.COLOR_WARNING
	_timer_label.text = "%ds left" % seconds_left
	_timer_label.add_theme_color_override("font_color", color)
	if _timer_bar != null and is_instance_valid(_timer_bar):
		var fraction := 1.0 if timer_total <= 0 else clampf(float(seconds_left) / float(timer_total), 0.0, 1.0)
		_timer_bar.custom_minimum_size.x = 70.0 * fraction
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		fill.set_corner_radius_all(2)
		_timer_bar.add_theme_stylebox_override("panel", fill)
