extends RefCounted

const DEFINITIONS := {
	"scribe": {
		"display_name": "The Scribe",
		"max_hp": 55,
		"defence": 1,
		"attack": 2,
		"damage": 18,
		"initiative": 6,
	},
	"knight": {
		"display_name": "The Knight",
		"max_hp": 70,
		"defence": -2,
		"attack": 3,
		"damage": 24,
		"initiative": 3,
	},
	"wizard": {
		"display_name": "The Wizard",
		"max_hp": 50,
		"defence": 2,
		"attack": 1,
		"damage": 16,
		"initiative": 8,
	},
	"bard": {
		"display_name": "The Bard",
		"max_hp": 45,
		"defence": 0,
		"attack": 2,
		"damage": 20,
		"initiative": 7,
	},
	"rogue": {
		"display_name": "The Rogue",
		"max_hp": 60,
		"defence": 0,
		"attack": 1,
		"damage": 14,
		"initiative": 4,
	},
}


## Every draftable character id, in a fixed order so the draft screen and any
## replay of a draft event list the roster the same way on both peers.
static func character_ids() -> Array:
	return DEFINITIONS.keys()


## The stat block for one character, without the per-match fields that only a
## character in play has.
static func definition(character_id: String) -> Dictionary:
	if not has_character(character_id):
		return {}
	return DEFINITIONS[character_id].duplicate(true)


static func has_character(character_id: String) -> bool:
	return DEFINITIONS.has(character_id)


static func create_character_state(character_id: String) -> Dictionary:
	if not has_character(character_id):
		return {}

	var definition: Dictionary = DEFINITIONS[character_id]
	return {
		"id": character_id,
		"display_name": definition["display_name"],
		"max_hp": definition["max_hp"],
		"hp": definition["max_hp"],
		"defence": definition["defence"],
		"attack": definition["attack"],
		"damage": definition["damage"],
		"initiative": definition["initiative"],
		"position": 0,
		"is_alive": true,
		"statuses": [],
		"effect_counters": {},
	}
