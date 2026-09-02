extends PanelContainer

## One player's claim record, pinned beneath their own roster.
##
## The two players' claims used to share a single unrelated panel, which made
## the read every bluffing decision depends on — what has this opponent been
## claiming — a matter of scanning past your own lines. Each sheet now sits under
## the side it belongs to, newest first.
##
## Everything here is public: the claim, and after the reveal the true roll and
## the outcome. Nothing on a sheet is ever added before the reveal makes it
## public.

const UiTheme = preload("res://src/presentation/theme.gd")
const Widgets = preload("res://src/presentation/ui/widgets.gd")
const Kits = preload("res://src/core/kits.gd")

## Outcome marks. Icon and text together, because the mark is the whole reading
## and a colour on its own would not carry it.
const OUTCOME_MARKS := {
	"HONEST_PASS": {"text": "HONEST", "color": "success"},
	"PADDED_PASS": {"text": "LOCKED IN", "color": "accent"},
	"CAUGHT": {"text": "CAUGHT", "color": "danger"},
	"WRONG_CALL": {"text": "WRONG CALL", "color": "danger"},
}

var _rows_box: VBoxContainer
var _ledger_box: HBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_style("raised"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	column.add_child(Widgets.heading("Claim record"))

	# The Scribe's banked paddings sit above the history: they are live state a
	# player has to price a claim against, not a record of what already happened.
	_ledger_box = HBoxContainer.new()
	_ledger_box.add_theme_constant_override("separation", 4)
	column.add_child(_ledger_box)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)


## Renders one player's sheet.
##
## `entries` are newest first, each a dictionary of "character", "claim",
## "true_roll" (-1 before the reveal), "padding", and "outcome".
## `recorded_paddings` is the Scribe's banked list from public team state.
func render(entries: Array, recorded_paddings: Array, tint: Color) -> void:
	for child in _ledger_box.get_children():
		child.queue_free()
	for child in _rows_box.get_children():
		child.queue_free()

	if recorded_paddings.is_empty():
		_ledger_box.add_child(Widgets.label("Nothing on the ledger.", 11, UiTheme.COLOR_INK_MUTED))
	else:
		_ledger_box.add_child(Widgets.label("ON THE LEDGER", 10, UiTheme.COLOR_INK_MUTED))
		# Pinned and ticked, so a recorded padding does not read like another
		# past claim: it is a number that can still be spent.
		for padding in recorded_paddings:
			var pin := Widgets.patch("📌 +%d" % int(padding), UiTheme.COLOR_ACCENT, 10)
			pin.tooltip_text = "Bookkeeping\nThe Scribe has a padding of %d on record. A future claim padded by exactly that amount locks in and cannot be challenged." % int(padding)
			_ledger_box.add_child(pin)
	_ledger_box.add_child(Widgets.filler())

	if entries.is_empty():
		_rows_box.add_child(Widgets.label("No claims yet.", 12, UiTheme.COLOR_INK_MUTED))
		return
	for entry in entries:
		_rows_box.add_child(_entry_row(entry, tint))


## One line: who claimed, what they claimed, what they actually rolled, the
## padding, and how it settled.
func _entry_row(entry: Dictionary, tint: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var initials := _initials(str(entry.get("character", "")))
	row.add_child(Widgets.patch(initials, tint, 10))

	var claim := int(entry.get("claim", 0))
	row.add_child(Widgets.label("claimed %d" % claim, 12, UiTheme.COLOR_INK))

	var true_roll := int(entry.get("true_roll", -1))
	if true_roll >= 0:
		row.add_child(Widgets.label("· rolled %d" % true_roll, 12, UiTheme.COLOR_INK_MUTED))
	var padding := int(entry.get("padding", 0))
	if padding > 0:
		row.add_child(Widgets.label("+%d" % padding, 12, UiTheme.COLOR_ACCENT_DARK))

	row.add_child(Widgets.filler())

	var outcome := str(entry.get("outcome", ""))
	var mark: Dictionary = OUTCOME_MARKS.get(outcome, {})
	if not mark.is_empty():
		row.add_child(Widgets.patch(str(mark["text"]), _mark_color(str(mark["color"])), 9))
	return row


func _mark_color(name: String) -> Color:
	match name:
		"success":
			return UiTheme.COLOR_SUCCESS
		"danger":
			return UiTheme.COLOR_DANGER
		_:
			return UiTheme.COLOR_ACCENT


## The face stand-in for a history line: the character's initials, skipping the
## article so the column does not read as a stack of Ts.
func _initials(display_name: String) -> String:
	for word: String in display_name.strip_edges().split(" ", false):
		if word.to_lower() == "the":
			continue
		return word.substr(0, 3).to_upper()
	return display_name.substr(0, 3).to_upper()
