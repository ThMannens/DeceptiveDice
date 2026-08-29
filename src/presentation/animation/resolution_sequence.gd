extends VBoxContainer

## The reveal: both true rolls, the outcome stamps, the totals, and the damage,
## played back as a short skippable sequence.
##
## The sequence infers no rules. Every number it shows is a field the reducer
## already produced in `last_resolution`; all this decides is the order they
## appear in and how long each beat holds. If a beat cannot be derived from an
## existing field it does not get animated — a presentation effect would have to
## be added to the reducer's own `effects` output first.
##
## The settled view is the whole result, and stays on screen afterwards. A player
## never has to replay the animation to understand what happened.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")

## Emitted once every beat has landed, whether it played out or was skipped.
signal settled

## Beat timings, in the order they play. A normal attack resolution runs about
## 2.4 seconds through these; a non-attack move skips most of them and lands
## well under 1.2.
const BEAT_ROLLS := 0.5
const BEAT_STAMP := 0.16
const BEAT_TOTALS := 0.32
const BEAT_DAMAGE := 0.22

## Outcome stamps, keyed by the reducer's own outcome constants. Icon-free by
## design: the words are the reading, and a stamp is what a scorekeeper would
## actually press onto a card.
const OUTCOME_STAMPS := {
	"HONEST_PASS": "HONEST",
	"PADDED_PASS": "LOCKED IN",
	"CAUGHT": "CAUGHT",
	"WRONG_CALL": "WRONG CALL",
}

var _beats: Array = []
var _tween: Tween
var _finished := false


func _init() -> void:
	add_theme_constant_override("separation", 6)


## Whether the sequence has reached its settled view.
func is_settled() -> bool:
	return _finished


## Plays `beats` in order. Each beat is a Callable that adds its own row.
##
## Under reduced motion every beat is applied at once, so the settled values are
## identical and no tween is ever queued.
func play(beats: Array) -> void:
	_beats = beats
	_finished = false
	if UiTheme.reduced_motion:
		skip()
		return
	_tween = create_tween()
	for index in _beats.size():
		_tween.tween_callback(_run_beat.bind(index))
		_tween.tween_interval(float(_beats[index]["hold"]))
	_tween.tween_callback(_mark_settled)


## Jumps straight to the settled view. Safe to call at any point, including
## after the sequence has already settled, so a stray click cannot double-run it.
func skip() -> void:
	if _finished:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# Only the beats that have not run yet: replaying a landed beat would double
	# its row.
	for index in _beats.size():
		_run_beat(index)
	_mark_settled()


func _mark_settled() -> void:
	if _finished:
		return
	_finished = true
	settled.emit()


## Wraps a row builder into a beat.
##
## The done flag lives on the sequence rather than inside the beat dictionary: a
## dictionary whose own value closes over it is a reference cycle GDScript never
## collects, and every resolution would leak one.
func beat(hold: float, run: Callable) -> Dictionary:
	return {"hold": hold, "run": run, "done": false}


## Runs one beat and marks it, so skip() knows which are still outstanding.
func _run_beat(index: int) -> void:
	if index < 0 or index >= _beats.size():
		return
	var record: Dictionary = _beats[index]
	if bool(record["done"]):
		return
	record["done"] = true
	(record["run"] as Callable).call()


## A line of the reveal. Rows are appended in beat order and never removed, so
## the finished sequence is the full arithmetic laid out top to bottom.
func add_line(text: String, font_size: int = 12, color: Color = UiTheme.COLOR_INK) -> void:
	add_child(Widgets.wrapped_label(text, font_size, color))


## One side stamped with how its claim settled.
func add_stamp_row(who: String, claim: int, true_roll: int, outcome: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(Widgets.label(who, 12, UiTheme.COLOR_INK))
	row.add_child(Widgets.label("rolled %d, claimed %d" % [true_roll, claim], 12, UiTheme.COLOR_INK_MUTED))
	if claim > true_roll:
		row.add_child(Widgets.patch("+%d" % (claim - true_roll), UiTheme.COLOR_ACCENT, 10))
	row.add_child(Widgets.filler())
	var stamp_text := str(OUTCOME_STAMPS.get(outcome, outcome))
	row.add_child(Widgets.stamp(stamp_text, _stamp_color(outcome), 10))
	add_child(row)


static func _stamp_color(outcome: String) -> Color:
	match outcome:
		"HONEST_PASS":
			return UiTheme.COLOR_SUCCESS
		"PADDED_PASS":
			return UiTheme.COLOR_ACCENT
		_:
			return UiTheme.COLOR_DANGER


## A damage figure attributed to its cause, so an HP change is never
## unexplained: self-damage, reflected damage, and the hit are separate rows.
func add_damage_row(caption: String, amount: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(Widgets.patch("-%d HP" % amount, color, 12))
	row.add_child(Widgets.label(caption, 12, UiTheme.COLOR_INK))
	row.add_child(Widgets.filler())
	add_child(row)
