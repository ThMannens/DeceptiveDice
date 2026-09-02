extends RefCounted

## Which animated rig stands in for each character, and what its animation state
## machine calls the beats the board needs.
##
## The rigs are art, not rules: a character with no rig is a visual state the
## battlefield falls back from, never an error. Two rigs currently exist, so the
## table below is mostly aspiration — adding a third character rig means adding
## its scene here and nothing else.
##
## Animation names differ per rig (the wizard's three attacks are wand moves,
## the bard's two are lute moves), so each entry translates the board's own
## vocabulary — idle, move, hurt, attack — into that rig's state names. The
## board never names a rig animation directly.

const RIG_DIR := "res://scenes"

## The beats every rig must answer to. A rig that lists no attack cannot be
## asked to swing, and the battlefield holds it on idle instead.
const BEAT_IDLE := "idle"
const BEAT_MOVE := "move"
const BEAT_HURT := "hurt"
const BEAT_ATTACK := "attack"

## Per-character rig assignments. `attacks` is a list because a rig with several
## swings should not play the same one every exchange; the battlefield picks by
## exchange number so both peers pick the same one without needing a shared RNG.
const RIGS := {
	"wizard": {
		"scene": "res://scenes/character_wizard.tscn",
		"idle": &"idle_animation",
		"move": &"move_animation",
		"hurt": &"hurt_animation",
		"attacks": [
			&"wand_attack_animation",
			&"wand_attack_2_animation",
			&"wand_slap_animation",
		],
	},
	"bard": {
		"scene": "res://scenes/character_bard.tscn",
		"idle": &"idle_animation",
		"move": &"move_animation",
		"hurt": &"hurt_animation",
		"attacks": [
			&"attack_1_animation",
			&"attack_2_animation",
		],
	},
}

## The rig geometry the board lays out against. Both current rigs share one
## skeleton, so these are constants rather than per-rig fields; a rig built to a
## different scale would need its own entry before this could stay true.
##
## Local units, measured from the scene root: the feet stand at GROUND and the
## head clears the top at CREST.
const RIG_GROUND := 275.0
const RIG_CREST := -205.0
const RIG_HEIGHT := RIG_GROUND - RIG_CREST


## True when this character has an animated rig to stand on the field.
static func has_rig(character_id: String) -> bool:
	return RIGS.has(character_id) and ResourceLoader.exists(str(RIGS[character_id]["scene"]))


## The rig table for a character, or an empty dictionary when it has no art yet.
static func rig(character_id: String) -> Dictionary:
	if not has_rig(character_id):
		return {}
	return (RIGS[character_id] as Dictionary).duplicate(true)


## Instantiates a character's rig, or null when it has none.
static func instantiate(character_id: String) -> Node2D:
	if not has_rig(character_id):
		return null
	var packed: PackedScene = load(str(RIGS[character_id]["scene"]))
	if packed == null:
		return null
	return packed.instantiate() as Node2D


## The rig's own name for one of the board's beats.
##
## `variant` selects among a rig's several attacks. It is the exchange number
## rather than a random draw, so a replay of the same match plays the same swing
## on both peers.
static func animation_for(character_id: String, beat: String, variant: int = 0) -> StringName:
	var table := rig(character_id)
	if table.is_empty():
		return &""
	if beat != BEAT_ATTACK:
		return table.get(beat, &"")
	var attacks: Array = table.get("attacks", [])
	if attacks.is_empty():
		return table.get(BEAT_IDLE, &"")
	return attacks[absi(variant) % attacks.size()]
