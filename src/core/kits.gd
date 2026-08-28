extends RefCounted

## A6 — Kit effect hook API.
##
## A kit is a set of named effects belonging to one roster character. Effects observe
## a resolved exchange and may modify a bounded part of it. Everything here is pure:
## no scene tree, no clock, no randomness. The reducer owns all state mutation, so an
## effect never writes to the match state directly. It returns a decision, and the
## reducer applies it.
##
## Hook points, in the order the reducer calls them:
##
##   modify_self_damage(context)  -> {"amount": int, "notes": Array}
##       Fires once per player that was caught bluffing this exchange, before any
##       damage is applied. Owned by the caught character's kit. May only change the
##       padding self-damage figure for its own character.
##
##   redirect_self_damage(context) -> {"redirect": bool, "notes": Array}
##       Fires for the character that correctly called a bluff, after
##       modify_self_damage settled the amount. Owned by the challenger's kit. May
##       move that damage onto the bluffer's opponent instead of the bluffer.
##
##   after_exchange(context) -> {"counters": Dictionary, "notes": Array}
##       Fires once per living character on both teams after damage lands. Used for
##       round-scoped bookkeeping. May only set effect counters on its own character.
##
## Resolution order when two kits fire at the same hook is fixed and deterministic:
## the attacking player's character first, then the defending player's, and where a
## hook fires for many characters at once (after_exchange), by player slot then by
## board position. Effects never see each other's pending decisions, so order only
## matters for the note log, not for the numbers.
##
## Every fired effect appends a note naming itself. The reducer turns notes into
## `kit_effect_fired` entries so the interface can say which effect changed a number.

const EFFECT_THICK_SKULL := "THICK_SKULL"
const EFFECT_FRONT_FIGHTER := "FRONT_FIGHTER"
const EFFECT_REFLECT := "REFLECT"
const EFFECT_READ_THE_ROOM := "READ_THE_ROOM"
const EFFECT_BOOKKEEPING := "BOOKKEEPING"
const EFFECT_AUDIT := "AUDIT"
const EFFECT_ALL_IN := "ALL_IN"
const EFFECT_COLD_STREAK := "COLD_STREAK"
const EFFECT_DRAG := "DRAG"
const EFFECT_SLIPPERY := "SLIPPERY"

const COUNTER_READ_THE_ROOM := "read_the_room_armed"
const COUNTER_AUDIT_CAP := "audit_claim_cap"
const COUNTER_COLD_STREAK := "cold_streak_honest_turns"

## All In fires on a locked-in claim at or above this value.
const ALL_IN_THRESHOLD := 15
## Cold Streak takes this much off caught-padding damage per consecutive honest
## claim, and stops at COLD_STREAK_MAX_REDUCTION.
const COLD_STREAK_STEP := 3
const COLD_STREAK_MAX_REDUCTION := 9
## Drag deals this instead of pulling a target that is already at the front.
const DRAG_FRONT_DAMAGE := 8


static func has_kit(character_id: String) -> bool:
	return _kit_effect_names().has(character_id)


## Public list of the effects a character owns, for the always-visible kit display.
static func effect_names(character_id: String) -> Array:
	return _kit_effect_names().get(character_id, []).duplicate()


## Damage modifier a character's kit contributes to an attack it is making.
## `attacker` is the acting character record. Pure read, no mutation.
static func attack_damage_modifier(attacker: Dictionary) -> Dictionary:
	var notes: Array = []
	var modifier := 0

	if str(attacker.get("id", "")) == "bruiser":
		# Front Fighter. +6 from position 4, and no damage bonus from 1 or 2. The
		# stat itself is untouched; only the move's damage modifier moves.
		var position := int(attacker.get("position", 0))
		if position == 4:
			modifier += 6
			notes.append(_note("bruiser", EFFECT_FRONT_FIGHTER, "POSITION_4_BONUS", {"damage_modifier": 6}))

	return {"modifier": modifier, "notes": notes}


## Whether a character's kit suppresses positive damage modifiers from its position.
## Front Fighter reads as "no damage bonus from positions 1 and 2", which cancels the
## margin bonus rather than the flat stat.
static func suppresses_margin_bonus(attacker: Dictionary) -> Dictionary:
	var notes: Array = []
	if str(attacker.get("id", "")) == "bruiser" and int(attacker.get("position", 0)) in [1, 2]:
		notes.append(_note("bruiser", EFFECT_FRONT_FIGHTER, "BACK_POSITION_PENALTY", {}))
		return {"suppressed": true, "notes": notes}
	return {"suppressed": false, "notes": notes}


## Hook: a character was caught bluffing and is about to take `amount` self-damage.
static func modify_self_damage(character: Dictionary, amount: int) -> Dictionary:
	var notes: Array = []
	var result := amount
	if amount <= 0:
		return {"amount": 0, "notes": notes}

	var character_id := str(character.get("id", ""))
	match character_id:
		"bruiser":
			# Thick Skull. Padding damage from being caught is halved, rounded down
			# to match every other rounding rule in the game.
			result = floori(float(amount) / 2.0)
			notes.append(_note("bruiser", EFFECT_THICK_SKULL, "PADDING_HALVED", {
				"amount_before": amount,
				"amount_after": result,
			}))
		"gambler":
			# All In. Being caught costs the Gambler double padding. Cold Streak then
			# discounts that doubled figure, so a long honest run softens a big lie
			# without ever making the gamble free.
			result = amount * 2
			notes.append(_note("gambler", EFFECT_ALL_IN, "PADDING_DOUBLED", {
				"amount_before": amount,
				"amount_after": result,
			}))
			var honest_turns := int(character.get("effect_counters", {}).get(COUNTER_COLD_STREAK, 0))
			var reduction := mini(honest_turns * COLD_STREAK_STEP, COLD_STREAK_MAX_REDUCTION)
			if reduction > 0:
				var reduced := maxi(0, result - reduction)
				notes.append(_note("gambler", EFFECT_COLD_STREAK, "PADDING_REDUCED", {
					"honest_turns": honest_turns,
					"reduction": reduction,
					"amount_before": result,
					"amount_after": reduced,
				}))
				result = reduced

	return {"amount": result, "notes": notes}


## Hook: `challenger` correctly called `bluffer`'s padded claim, and `amount` is the
## settled self-damage. A kit may redirect that damage onto the bluffer as a hit from
## the challenger instead of leaving it as self-damage.
static func redirect_self_damage(challenger: Dictionary, amount: int) -> Dictionary:
	var notes: Array = []

	if amount > 0 and str(challenger.get("id", "")) == "mirror":
		# Reflect. The Mirror deals the padded amount instead of the bluffer taking
		# it as self-damage. The figure is whatever survived the bluffer's own kit,
		# so Thick Skull still halves what Reflect then deals.
		notes.append(_note("mirror", EFFECT_REFLECT, "PADDING_REFLECTED", {"amount": amount}))
		return {"redirect": true, "notes": notes}

	return {"redirect": false, "notes": notes}


## Hook: whether `challenger`'s kit converts a wrong call into a free one. Read the
## Room resolves a wrong call as costing nothing, so the reducer drops the wrong-call
## bonus the opponent would otherwise receive.
static func absorbs_wrong_call(challenger: Dictionary) -> Dictionary:
	var notes: Array = []

	if str(challenger.get("id", "")) == "mirror" and bool(challenger.get("effect_counters", {}).get(COUNTER_READ_THE_ROOM, false)):
		notes.append(_note("mirror", EFFECT_READ_THE_ROOM, "WRONG_CALL_ABSORBED", {}))
		return {"absorbed": true, "notes": notes}

	return {"absorbed": false, "notes": notes}


## Hook: bookkeeping after damage has landed. Returns counters to set on `character`.
## `locked_in_claim` is true when this character's own claim survived the challenge
## phase this exchange; `challenged` is true when this character spent its challenge.
static func after_exchange(character: Dictionary, own_claim: Dictionary, opposing_claim: Dictionary) -> Dictionary:
	var counters: Dictionary = {}
	var notes: Array = []
	var locked_in_claim := bool(own_claim.get("locked_in", false))
	var challenged := bool(opposing_claim.get("challenged", false))

	match str(character.get("id", "")):
		"mirror":
			# Read the Room. Arming lasts until the Mirror spends the challenge, and
			# is cleared at round rollover by the reducer, since the spec scopes it to
			# "this round". Spending it and re-arming in the same exchange is legal:
			# the Mirror used the armed challenge and locked its own claim in.
			var armed := bool(character.get("effect_counters", {}).get(COUNTER_READ_THE_ROOM, false))
			if challenged and armed:
				armed = false
				notes.append(_note("mirror", EFFECT_READ_THE_ROOM, "SPENT", {}))
			if locked_in_claim:
				if not armed:
					notes.append(_note("mirror", EFFECT_READ_THE_ROOM, "ARMED", {}))
				armed = true
			counters[COUNTER_READ_THE_ROOM] = armed
		"gambler":
			# Cold Streak. Count consecutive honest claims, and reset the moment the
			# Gambler pads one, whether or not that padding was caught.
			var honest_turns := int(character.get("effect_counters", {}).get(COUNTER_COLD_STREAK, 0))
			if bool(own_claim.get("is_padded", false)):
				if honest_turns > 0:
					notes.append(_note("gambler", EFFECT_COLD_STREAK, "RESET", {"honest_turns_before": honest_turns}))
				honest_turns = 0
			else:
				honest_turns += 1
				notes.append(_note("gambler", EFFECT_COLD_STREAK, "EXTENDED", {"honest_turns": honest_turns}))
			counters[COUNTER_COLD_STREAK] = honest_turns

	# An Audit cap is consumed by the capped character's next claim, whoever imposed
	# it. Clearing it here means the cap lasts exactly one claim.
	if int(character.get("effect_counters", {}).get(COUNTER_AUDIT_CAP, 20)) < 20:
		counters[COUNTER_AUDIT_CAP] = 20
		notes.append(_note(str(character.get("id", "")), EFFECT_AUDIT, "CAP_EXPIRED", {}))

	return {"counters": counters, "notes": notes}


## Hook: a cap one kit imposes on the character it just caught bluffing. Returns 20
## when nothing is imposed. Owned by the challenger's kit.
static func imposes_claim_cap(challenger: Dictionary, caught_claim: Dictionary) -> Dictionary:
	if str(challenger.get("id", "")) != "ledger":
		return {"cap": 20, "notes": []}

	# Audit. The caught character's next claim this round is capped at the value of
	# their previous claim, which is the claim they were just caught on.
	var cap := int(caught_claim.get("claim", 20))
	return {"cap": cap, "notes": [_note("ledger", EFFECT_AUDIT, "CAP_IMPOSED", {"cap": cap})]}


## Counters cleared when a new round begins. Kit state scoped to "this round" lives
## here so the reducer does not need to know which kit owns which counter.
static func round_scoped_counters() -> Array:
	return [COUNTER_READ_THE_ROOM, COUNTER_AUDIT_CAP]


## Hook: the highest claim `character` may legally submit right now. Returns 20 when
## no kit constrains it. The reducer rejects a claim above this value.
static func claim_ceiling(character: Dictionary) -> Dictionary:
	var cap := int(character.get("effect_counters", {}).get(COUNTER_AUDIT_CAP, 20))
	if cap < 20:
		# Audit. The capped character is the one that was caught, so the note names
		# the capped character rather than the Ledger that imposed the cap.
		return {"ceiling": cap, "notes": [_note(str(character.get("id", "")), EFFECT_AUDIT, "CLAIM_CAPPED", {"cap": cap})]}
	return {"ceiling": 20, "notes": []}


## Hook: whether `character`'s claim cannot be challenged and locks in automatically.
##
## Bookkeeping matches on *padding*, not on the claimed number: what the Ledger has
## on record is how far it lied, so a padding of 6 recorded by claiming 18 on a roll
## of 12 also covers claiming 9 on a roll of 3. The entry is spent by the claim it
## protects, so the same padding has to be put back on record before it works again.
##
## `recorded_paddings` is the player's live ledger. The reducer owns writing to it;
## this hook only reports whether a match exists.
static func claim_is_immune(character: Dictionary, padding: int, recorded_paddings: Array) -> Dictionary:
	if str(character.get("id", "")) != "ledger":
		return {"immune": false, "notes": []}

	if padding in recorded_paddings:
		return {
			"immune": true,
			"consumes_padding": padding,
			"notes": [_note("ledger", EFFECT_BOOKKEEPING, "CLAIM_LOCKED_IN", {"padding": padding})],
		}
	return {"immune": false, "notes": []}


## Hook: whether this player's claim goes onto the Bookkeeping ledger. Only the
## Ledger's own claims are recorded, and only when they did not just consume an
## entry: a claim that spent its padding has to earn that padding again.
static func records_padding(character: Dictionary) -> bool:
	return str(character.get("id", "")) == "ledger"


## Hook: a multiplier on the hit damage a locked-in claim produces.
static func hit_damage_multiplier(attacker: Dictionary, attack_result: Dictionary) -> Dictionary:
	if str(attacker.get("id", "")) != "gambler":
		return {"multiplier": 1, "notes": []}

	# All In. A locked-in claim of 15 or higher doubles margin damage.
	if bool(attack_result.get("locked_in", false)) and int(attack_result.get("claim", 0)) >= ALL_IN_THRESHOLD:
		return {"multiplier": 2, "notes": [_note("gambler", EFFECT_ALL_IN, "DAMAGE_DOUBLED", {"claim": int(attack_result["claim"])})]}
	return {"multiplier": 1, "notes": []}


## Hook: a target position change caused by a landed hit. `steps_forward` moves the
## target toward the front; `extra_damage` applies when it cannot be moved further.
static func on_hit(attacker: Dictionary, target: Dictionary) -> Dictionary:
	if str(attacker.get("id", "")) != "hook":
		return {"steps_forward": 0, "extra_damage": 0, "notes": []}

	# Drag. Pull the target one position toward the front, or hit an already-front
	# target for extra damage instead.
	if int(target.get("position", 0)) >= 4:
		return {
			"steps_forward": 0,
			"extra_damage": DRAG_FRONT_DAMAGE,
			"notes": [_note("hook", EFFECT_DRAG, "FRONT_TARGET_BONUS", {"extra_damage": DRAG_FRONT_DAMAGE})],
		}
	return {
		"steps_forward": 1,
		"extra_damage": 0,
		"notes": [_note("hook", EFFECT_DRAG, "TARGET_PULLED", {"from_position": int(target.get("position", 0))})],
	}


## Hook: whether a caught character escapes its padding damage by moving instead.
## The reducer performs the swap, because only it knows the rest of the team.
static func evades_padding_by_swapping(character: Dictionary) -> Dictionary:
	if str(character.get("id", "")) == "hook":
		# Slippery. The Hook swaps with an ally rather than taking padding damage.
		return {"evades": true, "notes": [_note("hook", EFFECT_SLIPPERY, "SWAPPED_INSTEAD_OF_DAMAGE", {})]}
	return {"evades": false, "notes": []}


static func _note(character_id: String, effect: String, detail: String, data: Dictionary) -> Dictionary:
	var note := {
		"character_id": character_id,
		"effect": effect,
		"detail": detail,
	}
	note.merge(data)
	return note


## Public kit text. The interface reads this so the effect wording players see and
## the effect the reducer runs can never drift apart.
const EFFECT_TEXT := {
	EFFECT_THICK_SKULL: {
		"name": "Thick Skull",
		"text": "Padding damage from being caught is halved.",
	},
	EFFECT_FRONT_FIGHTER: {
		"name": "Front Fighter",
		"text": "+6 damage from position 4. No margin damage bonus from positions 1 and 2.",
	},
	EFFECT_REFLECT: {
		"name": "Reflect",
		"text": "When the Mirror challenges a bluff and is right, the bluffer takes that padding as damage dealt by the Mirror rather than as self-damage.",
	},
	EFFECT_READ_THE_ROOM: {
		"name": "Read the Room",
		"text": "Once the Mirror's own claim locks in, its next challenge this round is free: correct against a bluff, and costing nothing against an honest claim.",
	},
	EFFECT_BOOKKEEPING: {
		"name": "Bookkeeping",
		"text": "The Ledger keeps a record of how far this player has padded before. A claim that pads by an amount already on record cannot be challenged and locks in automatically, but using it spends that entry: the same padding must be recorded again before it protects another claim.",
	},
	EFFECT_AUDIT: {
		"name": "Audit",
		"text": "When the Ledger challenges a bluff and is right, the character it caught cannot claim above that same value on their next claim this round.",
	},
	EFFECT_ALL_IN: {
		"name": "All In",
		"text": "If the Gambler claims 15 or higher and the claim locks in, hit damage is doubled. If the claim is caught instead, the padding damage is doubled.",
	},
	EFFECT_COLD_STREAK: {
		"name": "Cold Streak",
		"text": "Every consecutive honest claim takes 3 more off the padding damage of the Gambler's next caught bluff, up to 9. One padded claim resets the count to zero.",
	},
	EFFECT_DRAG: {
		"name": "Drag",
		"text": "On a hit, pull the target one position forward, toward the front. A target already at position 4 takes 8 extra damage instead.",
	},
	EFFECT_SLIPPERY: {
		"name": "Slippery",
		"text": "When the Hook's bluff is caught, it swaps positions with an ally and takes no padding damage at all.",
	},
}


## Rules vocabulary that kit text and resolution text both lean on. The interface
## appends the definition of any term a tooltip actually uses, so a player never
## has to already know the word to read the tooltip.
##
## Keyed by the term as it should be matched, lowercase. `aliases` catches the
## other forms the same idea appears in.
const GLOSSARY := [
	{
		"term": "locks in",
		"aliases": ["locked in", "locked-in", "lock in", "locks in"],
		"label": "Locked in",
		"text": "A claim that survived the challenge phase, either because nobody challenged it or because the challenge was wrong. It counts at its claimed value even if it was a lie, and kit effects only fire on locked-in claims.",
	},
	{
		"term": "padding",
		"aliases": ["padding", "padded", "pads"],
		"label": "Padding",
		"text": "How far a claim sits above the true roll. Padding of zero is an honest claim. A caught bluffer takes their padding as damage.",
	},
	{
		"term": "caught",
		"aliases": ["caught", "catches"],
		"label": "Caught",
		"text": "Challenged while padding was above zero. An attack that is caught is cancelled entirely, and the bluffer takes the padding as damage.",
	},
	{
		"term": "wrong call",
		"aliases": ["wrong call", "wrongly challenged"],
		"label": "Wrong call",
		"text": "Challenging a claim that was honest. The claim still stands, and the challenger is punished: doubled damage against them on attack, or halved damage on defence.",
	},
	{
		"term": "bluff",
		"aliases": ["bluff", "bluffer", "bluffs"],
		"label": "Bluff",
		"text": "A claim above the true roll. Claims can never be below the roll, so lying only ever means claiming higher.",
	},
	{
		"term": "claim",
		"aliases": ["claim", "claims", "claimed"],
		"label": "Claim",
		"text": "The value a player reports for their die. Always at least the true roll and never above 20. Only the roller sees the true roll until the reveal.",
	},
	{
		"term": "margin",
		"aliases": ["margin"],
		"label": "Margin",
		"text": "Effective attack minus effective defence. Zero or less is a miss; above zero it is added to the attacker's Damage stat.",
	},
]


## The glossary entries a piece of text actually uses, in glossary order, capped
## at `limit` so a tooltip never turns into a wall of definitions. `known` lets a
## caller suppress terms it has already defined higher up the same tooltip.
static func glossary_for(text: String, limit: int = 2, known: Array = []) -> Array:
	var lowered := text.to_lower()
	var matches: Array = []
	for entry in GLOSSARY:
		if str(entry["term"]) in known:
			continue
		for alias in entry["aliases"]:
			if _contains_word(lowered, str(alias)):
				matches.append(entry)
				break
		if matches.size() >= limit:
			break
	return matches


## Whole-word containment, so "claim" does not match inside "claimant" and
## "bluff" does not fire on a word that merely starts the same way.
static func _contains_word(haystack: String, needle: String) -> bool:
	var from := 0
	while true:
		var index := haystack.find(needle, from)
		if index < 0:
			return false
		var before_ok := index == 0 or not _is_word_character(haystack[index - 1])
		var after_index := index + needle.length()
		var after_ok := after_index >= haystack.length() or not _is_word_character(haystack[after_index])
		if before_ok and after_ok:
			return true
		from = index + 1
	return false


static func _is_word_character(character: String) -> bool:
	return (character >= "a" and character <= "z") or (character >= "0" and character <= "9")


## The kit text for one character, ready to render: an array of {name, text}.
static func effect_descriptions(character_id: String) -> Array:
	var descriptions: Array = []
	for effect in effect_names(character_id):
		var entry: Dictionary = EFFECT_TEXT.get(effect, {})
		descriptions.append({
			"effect": effect,
			"name": str(entry.get("name", effect)),
			"text": str(entry.get("text", "")),
		})
	return descriptions


static func _kit_effect_names() -> Dictionary:
	return {
		"ledger": [EFFECT_BOOKKEEPING, EFFECT_AUDIT],
		"bruiser": [EFFECT_THICK_SKULL, EFFECT_FRONT_FIGHTER],
		"mirror": [EFFECT_REFLECT, EFFECT_READ_THE_ROOM],
		"gambler": [EFFECT_ALL_IN, EFFECT_COLD_STREAK],
		"hook": [EFFECT_DRAG, EFFECT_SLIPPERY],
	}
