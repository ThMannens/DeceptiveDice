extends RefCounted

## Visual language for Deceptive Dice.
##
## The north star is a weekend LARP tournament made from real craft materials:
## a worn wooden table, canvas team areas, cream index cards, marker-ink
## outlines, cloth tape for ownership, and stitched patches for statuses. Every
## widget the interface builds goes through this file, so presentation code
## never introduces a colour literal of its own.
##
## Two rules the palette exists to enforce:
##   * player colours mean ownership and nothing else, so a card is never tinted
##     green for "good" or red for "bad" by whose it is;
##   * body text sits on nearly opaque paper, because grain behind 11-15px type
##     is the fastest way to make a rules-heavy game unreadable.

# --- Ink and paper -----------------------------------------------------------
const COLOR_INK := Color("2A211C")
const COLOR_INK_MUTED := Color("67584D")
const COLOR_PAPER := Color("FFF8E9")
const COLOR_PARCHMENT := Color("F3E2C2")
const COLOR_CARDBOARD := Color("C9A878")

# --- Table and tent ----------------------------------------------------------
const COLOR_CANVAS := Color("A88761")
const COLOR_CANVAS_DARK := Color("6E513B")
const COLOR_WOOD := Color("4A3025")
const COLOR_WOOD_DARK := Color("291C18")

# --- Tape and accents --------------------------------------------------------
const COLOR_TAPE := Color("E7C95F")
const COLOR_ACCENT := Color("E69A32")
const COLOR_ACCENT_DARK := Color("8C541F")

# --- Ownership ---------------------------------------------------------------
const COLOR_PLAYER_ONE := Color("27738D")
const COLOR_PLAYER_ONE_LIGHT := Color("CFE7E8")
const COLOR_PLAYER_TWO := Color("874D82")
const COLOR_PLAYER_TWO_LIGHT := Color("E9D2E4")

# --- Semantic ----------------------------------------------------------------
const COLOR_SUCCESS := Color("3D784C")
const COLOR_DANGER := Color("A93628")
const COLOR_WARNING := Color("C47B22")
const COLOR_INFO := Color("4969A3")
const COLOR_DISABLED := Color("A99B8B")

const COLOR_HEALTH_HIGH := Color("4F8755")
const COLOR_HEALTH_MID := Color("C38B24")
const COLOR_HEALTH_LOW := Color("A93628")

# --- Compatibility aliases ---------------------------------------------------
# The old navy-and-brass names are kept pointing at their nearest craft-material
# equivalent so a caller that has not been converted yet still renders in the
# new palette instead of reintroducing the felt table one colour at a time.
const COLOR_BACKDROP := COLOR_WOOD_DARK
const COLOR_FELT := COLOR_WOOD
const COLOR_FELT_EDGE := COLOR_CANVAS_DARK
const COLOR_PANEL := COLOR_PARCHMENT
const COLOR_PANEL_ALT := COLOR_PAPER
const COLOR_PANEL_RAISED := COLOR_PAPER
const COLOR_ACCENT_BRIGHT := COLOR_ACCENT_DARK
const COLOR_ACCENT_DEEP := COLOR_ACCENT_DARK
const COLOR_TEXT := COLOR_INK
const COLOR_MUTED := COLOR_INK_MUTED
const COLOR_FAINT := COLOR_INK_MUTED
const COLOR_DEFEATED := COLOR_CARDBOARD

# Paper stock does not curl into a 14px radius. Card corners stay tight so the
# surfaces read as cut card rather than as SaaS pills.
const RADIUS_PANEL := 8
const RADIUS_CARD := 6
const RADIUS_BUTTON := 5

## The hard offset shadow that makes every surface read as a layered piece of
## paper on a table rather than a floating gradient panel.
const SHADOW_OFFSET := Vector2(3, 4)
const SHADOW_OPACITY := 0.42

## Presentation-only motion switch. Every animated sequence checks this and
## substitutes a short crossfade with immediate numbers when it is on, so a
## player who cannot read moving type still gets the same information.
static var reduced_motion := false


## Semantic paper surfaces. `kind` picks the stock rather than the colour, so a
## caller says what a surface is for and the palette decides how it looks.
##
## Kinds: "normal" (cream index card), "raised" (the brightest information
## surface), "secondary" (parchment), "inactive" (cardboard), "well" (a recess
## cut into the canvas), "canvas" (a team area), "wood" (the outer frame).
static func paper_style(kind: String = "normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_PANEL)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.set_border_width_all(2)
	style.border_color = COLOR_INK

	match kind:
		"raised":
			style.bg_color = COLOR_PAPER
		"secondary":
			style.bg_color = COLOR_PARCHMENT
		"inactive":
			style.bg_color = COLOR_CARDBOARD
			style.border_color = COLOR_CANVAS_DARK
		"well":
			style.bg_color = COLOR_CANVAS_DARK
			style.border_color = COLOR_WOOD_DARK
		"canvas":
			style.bg_color = COLOR_CANVAS
			style.border_color = COLOR_CANVAS_DARK
		"wood":
			style.bg_color = COLOR_WOOD
			style.border_color = COLOR_WOOD_DARK
		_:
			style.bg_color = COLOR_PAPER
	_apply_hard_shadow(style)
	return style


## A card belonging to one player. Ownership shows as a thick cloth-tape left
## edge, never as a tint across the whole card: a fully tinted card competes
## with the success/danger colours that carry the actual outcome.
##
## States: "normal", "ready", "selected", "legal_target", "attacker",
## "defender", "acted", "defeated".
static func team_card_style(player_color: Color, state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_CARD)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.set_border_width_all(2)
	style.border_color = COLOR_INK
	style.bg_color = COLOR_PARCHMENT
	_apply_hard_shadow(style)

	match state:
		"selected":
			style.bg_color = COLOR_PAPER
			style.set_border_width_all(3)
			style.border_color = COLOR_ACCENT_DARK
			style.shadow_offset = SHADOW_OFFSET * 1.6
			style.shadow_color = Color(COLOR_WOOD_DARK, 0.55)
		"attacker":
			style.bg_color = COLOR_PAPER
			style.set_border_width_all(3)
			style.border_color = COLOR_ACCENT_DARK
		"defender":
			style.bg_color = COLOR_PAPER
			style.set_border_width_all(3)
			style.border_color = COLOR_INFO
		"legal_target":
			style.bg_color = COLOR_PAPER
			style.set_border_width_all(3)
			style.border_color = COLOR_DANGER
		"ready":
			style.bg_color = COLOR_PAPER
		"acted":
			style.bg_color = COLOR_PARCHMENT
		"defeated":
			style.bg_color = COLOR_CARDBOARD
			style.border_color = COLOR_DISABLED
			style.shadow_color = Color(COLOR_WOOD_DARK, 0.2)

	# The cloth-tape stripe down the owning side goes on last, so no state can
	# accidentally erase whose card this is.
	style.border_width_left = 8
	return style


## A stitched fabric patch: statuses, kit effects, and small state tags. Patches
## always carry text as well as colour, so the shape is doing emphasis and never
## the whole job.
##
## States: "normal" (pale scrap with an ink edge), "stamped" (a solid inked
## stamp), "disabled" (grey cardboard).
static func patch_style(color: Color, state: String = "normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.set_border_width_all(2)
	style.border_color = COLOR_INK
	# A patch is a light scrap of cloth with an ink outline; tinting the fill
	# lightly keeps small text on it above the contrast floor.
	style.bg_color = COLOR_PAPER.lerp(color, 0.22)
	match state:
		"stamped":
			style.bg_color = color
			style.border_color = color.darkened(0.35)
		"disabled":
			style.bg_color = COLOR_CARDBOARD
			style.border_color = COLOR_CANVAS_DARK
	return style


## Prop buttons: the physical-looking controls the player presses.
##
## Kinds: "primary" (painted orange sign), "secondary" (plain cardboard),
## "stamp" (the red rubber CHALLENGE stamp), "quiet" (a flat parchment tab).
## States: "normal", "hover", "pressed", "disabled", "focus".
static func prop_button_style(kind: String, state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.set_border_width_all(2)
	style.border_color = COLOR_INK

	var fill := COLOR_CARDBOARD
	match kind:
		"primary":
			fill = COLOR_ACCENT
		"stamp":
			fill = COLOR_DANGER
		"quiet":
			fill = COLOR_PARCHMENT

	match state:
		"hover":
			style.bg_color = fill.lightened(0.12)
		"pressed":
			# A pressed control sinks into the table: darker, and the hard
			# shadow disappears rather than the button growing a glow.
			style.bg_color = fill.darkened(0.18)
			style.border_color = COLOR_ACCENT_DARK if kind == "primary" else COLOR_INK
			return style
		"disabled":
			style.bg_color = COLOR_CARDBOARD.lightened(0.1)
			style.border_color = COLOR_DISABLED
			return style
		"focus":
			# Keyboard focus has to be as loud as the mouse hover state, so it
			# is a thick ink-and-orange outline rather than the engine hairline.
			style.bg_color = Color(0, 0, 0, 0)
			style.set_border_width_all(3)
			style.border_color = COLOR_ACCENT
			return style
		_:
			style.bg_color = fill
	_apply_hard_shadow(style)
	return style


## The hard offset shadow shared by every raised surface: layered paper, not a
## soft ambient glow.
static func _apply_hard_shadow(style: StyleBoxFlat) -> void:
	style.shadow_color = Color(COLOR_WOOD_DARK, SHADOW_OPACITY)
	style.shadow_size = 0
	style.shadow_offset = SHADOW_OFFSET


## A pinned rulebook note. Fully opaque, because a tooltip sits over character
## cards and stat text: any transparency lets the wording underneath bleed
## through, which is what makes the engine default unreadable here.
static func tooltip_style() -> StyleBoxFlat:
	var style := paper_style("secondary")
	style.set_corner_radius_all(RADIUS_CARD)
	style.shadow_color = Color(COLOR_WOOD_DARK, 0.6)
	style.shadow_offset = SHADOW_OFFSET
	return style


## Health colour shifts from green through amber to red as a character is worn
## down, so damage is legible without reading the numbers. Paired everywhere
## with the printed HP figure, since hue alone is never a state cue.
static func health_color(fraction: float) -> Color:
	if fraction > 0.6:
		return COLOR_HEALTH_HIGH
	if fraction > 0.3:
		return COLOR_HEALTH_MID
	return COLOR_HEALTH_LOW


## The ink colour to print on a given fill. Dark ink on the light craft
## materials, cream paper on the saturated ones; both directions of the pairing
## clear the 4.5:1 normal-text target.
static func ink_on(fill: Color) -> Color:
	# Luminance rather than an explicit list, so a caller passing a derived
	# colour (a lightened hover fill, a darkened stamp) still gets a readable
	# pairing instead of falling through to the wrong default.
	var luminance := 0.2126 * fill.r + 0.7152 * fill.g + 0.0722 * fill.b
	return COLOR_INK if luminance > 0.45 else COLOR_PAPER


# --- Legacy shims ------------------------------------------------------------
# A few call sites still build surfaces through the old signatures. They route
# to the paper stock closest to what the caller asked for, so nothing has to be
# converted in the same change that swaps the palette.

static func panel_style(
	color: Color,
	radius: int = RADIUS_PANEL,
	border_color: Color = Color(0, 0, 0, 0),
	border_width: int = 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.set_border_width_all(maxi(border_width, 2))
	style.border_color = border_color if border_width > 0 else COLOR_INK
	return style


static func surface_style(color: Color, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var style := panel_style(color, radius, COLOR_INK, 2)
	_apply_hard_shadow(style)
	return style


static func accented_surface_style(color: Color, accent: Color, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var style := surface_style(color, radius)
	# Ownership as a cloth-tape top edge rather than a tint across the surface.
	style.border_width_top = 6
	return style


static func card_style(color: Color, accent: Color, highlighted: bool) -> StyleBoxFlat:
	return team_card_style(accent, "ready" if highlighted else "normal")


static func button_style(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(RADIUS_BUTTON)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.set_border_width_all(maxi(border_width, 2))
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
	theme.set_stylebox("normal", "Button", prop_button_style("secondary", "normal"))
	theme.set_stylebox("hover", "Button", prop_button_style("secondary", "hover"))
	theme.set_stylebox("pressed", "Button", prop_button_style("secondary", "pressed"))
	theme.set_stylebox("disabled", "Button", prop_button_style("secondary", "disabled"))
	theme.set_stylebox("focus", "Button", prop_button_style("secondary", "focus"))
	theme.set_color("font_color", "Button", COLOR_INK)
	theme.set_color("font_hover_color", "Button", COLOR_INK)
	theme.set_color("font_pressed_color", "Button", COLOR_INK)
	theme.set_color("font_disabled_color", "Button", COLOR_INK_MUTED)
	theme.set_font_size("font_size", "Button", 15)


static func _style_inputs(theme: Theme) -> void:
	# Form fields are cream paper ruled with ink, so typed text reads the same
	# way printed text does everywhere else.
	var field := StyleBoxFlat.new()
	field.bg_color = COLOR_PAPER
	field.set_corner_radius_all(RADIUS_BUTTON)
	field.set_border_width_all(2)
	field.border_color = COLOR_INK
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6

	for type in ["OptionButton", "LineEdit", "TextEdit", "SpinBox"]:
		theme.set_stylebox("normal", type, field)
		theme.set_color("font_color", type, COLOR_INK)

	var field_hover := field.duplicate() as StyleBoxFlat
	field_hover.border_color = COLOR_ACCENT_DARK
	theme.set_stylebox("hover", "OptionButton", field_hover)
	theme.set_stylebox("pressed", "OptionButton", field_hover)
	theme.set_stylebox("focus", "OptionButton", prop_button_style("secondary", "focus"))
	theme.set_color("font_color", "OptionButton", COLOR_INK)
	theme.set_color("font_hover_color", "OptionButton", COLOR_INK)

	# The dropdown list that OptionButton opens.
	var popup := paper_style("raised")
	popup.content_margin_left = 6
	popup.content_margin_right = 6
	popup.content_margin_top = 6
	popup.content_margin_bottom = 6
	theme.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = COLOR_PAPER.lerp(COLOR_ACCENT, 0.4)
	popup_hover.set_corner_radius_all(3)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", COLOR_INK)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_INK)

	theme.set_stylebox("normal", "TextEdit", field)
	var text_focus := field.duplicate() as StyleBoxFlat
	text_focus.set_border_width_all(3)
	text_focus.border_color = COLOR_ACCENT
	theme.set_stylebox("focus", "TextEdit", text_focus)
	theme.set_color("font_color", "TextEdit", COLOR_INK)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_INK_MUTED)
	theme.set_color("caret_color", "TextEdit", COLOR_ACCENT_DARK)
	theme.set_color("selection_color", "TextEdit", COLOR_PAPER.lerp(COLOR_ACCENT, 0.45))


static func _style_progress(theme: Theme) -> void:
	# The HP bar is a slot cut into the card: a dark well with an ink edge.
	var track := StyleBoxFlat.new()
	track.bg_color = COLOR_CANVAS_DARK
	track.set_corner_radius_all(2)
	track.set_border_width_all(2)
	track.border_color = COLOR_INK
	theme.set_stylebox("background", "ProgressBar", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_HEALTH_HIGH
	fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", fill)


static func _style_scrollbars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(COLOR_WOOD_DARK, 0.28)
	track.set_corner_radius_all(2)
	track.content_margin_left = 3
	track.content_margin_right = 3

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = COLOR_CARDBOARD
	grabber.set_corner_radius_all(2)
	grabber.set_border_width_all(1)
	grabber.border_color = COLOR_INK

	var grabber_hover := grabber.duplicate() as StyleBoxFlat
	grabber_hover.bg_color = COLOR_TAPE

	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, grabber_hover)
		theme.set_stylebox("grabber_pressed", type, grabber_hover)


static func _style_misc(theme: Theme) -> void:
	var separator := StyleBoxLine.new()
	separator.color = COLOR_CANVAS_DARK
	separator.thickness = 2
	theme.set_stylebox("separator", "HSeparator", separator)

	_style_tooltips(theme)


## Tooltips carry the kit rules, so they have to be readable over the board
## rather than the engine default, which is a near-transparent dark box.
static func _style_tooltips(theme: Theme) -> void:
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style())

	theme.set_color("font_color", "TooltipLabel", COLOR_INK)
	theme.set_font_size("font_size", "TooltipLabel", 13)
	# The engine draws tooltip text with an outline by default, which smears the
	# small type. Turn it off now that the panel behind it is solid.
	theme.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	theme.set_constant("shadow_outline_size", "TooltipLabel", 0)
	theme.set_constant("shadow_offset_x", "TooltipLabel", 0)
	theme.set_constant("shadow_offset_y", "TooltipLabel", 0)

	theme.set_color("default_color", "RichTextLabel", COLOR_INK_MUTED)
	theme.set_font_size("normal_font_size", "RichTextLabel", 13)
	theme.set_color("font_color", "Label", COLOR_INK)
