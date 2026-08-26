# Match state and event schema

This document fixes the shared data contract for the rules core, protocol, tests, and interface. The code definitions live in `src/core/match_state.gd` and `src/core/match_event.gd`.

## Match state

The root match dictionary contains:

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | integer | Version of this persisted shape. Starts at 1. |
| `match_id` | string | Stable id included in every event and protocol message. |
| `status` | string | `DRAFT`, `ACTIVE`, `FINISHED`, or `ABORTED`. |
| `phase` | string | `DRAFT`, `PLACEMENT`, `SELECT`, `COMMIT`, `CLAIM`, `CHALLENGE`, `REVEAL`, `RESOLVE`, or `FINISHED`. |
| `exchange_number` | integer | Zero before play, then one-based. |
| `round_number` | integer | Zero before play, then one-based. |
| `active_player` | integer | Player slot 0 or 1. `-1` before play. |
| `starting_player` | integer | Player that opened the current round. |
| `winner_player` | integer | Winning player slot. `-1` until the match ends. |
| `teams` | array | Two team records, indexed by player slot. |
| `exchange` | dictionary | In-progress exchange data. Reset after resolution. |
| `last_resolution` | dictionary | Itemized outcome of the latest completed exchange. |
| `event_count` | integer | Number of accepted state-changing events. |

A team record contains its stable `player_id`, draft and formation locks, the four drafted character ids, all character state, ids used this round, claim history, and team-level effect counters.

A character record contains its catalog id and display name, current and maximum HP, base combat stats, position, alive flag, temporary statuses, and character-level effect counters. Positions run from 1 at the back to 4 at the front. A drafted but unplaced character has position 0.

Claim history entries will contain the exchange number, character id, true roll, claim, padding, challenge result, and whether the claim locked in. They stay public after reveal.

The exchange record contains:

- selected actor, move, and target;
- one commit submission per player;
- one claim submission per player;
- one challenge submission per player;
- one reveal submission per player;
- phase timeout records;
- the computed resolution summary.

The rules core owns the canonical full state. The interface may receive a filtered view while a blind submission phase is open.

## Events

Every event has the same envelope:

```text
type: event kind
match_id: target match
exchange_number: expected exchange
phase: expected current phase
sender: player slot 0 or 1, or -1 for a system event
payload: event-specific dictionary
```

The reducer accepts these event kinds:

| Event | Phase | Sender | Payload |
|---|---|---|---|
| `draft_submitted` | `DRAFT` | player | `character_ids`, four unique roster ids |
| `formation_submitted` | `PLACEMENT` | player | `character_ids`, back-to-front order |
| `action_selected` | `SELECT` | active player | `actor_id`, `move_id`, `target_id` |
| `commit_submitted` | `COMMIT` | player | `roll_commit`, `observer_secret` |
| `claim_submitted` | `CLAIM` | player | `value`, from 1 through 20 |
| `challenge_submitted` | `CHALLENGE` | player | `challenge`, boolean |
| `reveal_submitted` | `REVEAL` | player | `secret` |
| `phase_timeout` | current phase | system | `timed_out_sender` |
| `exchange_resolved` | `RESOLVE` | system | Attack moves require `true_rolls`, one protocol-verified roll per player. Non-attack moves use an empty payload. |
| `player_forfeited` | any live phase | player | optional `reason` |

Events are append-only. A peer records accepted events in order outside the state, then can replay them from a fresh initial state. The reducer does not read a clock, network socket, random source, or scene tree.

## Reducer contract

`MatchReducer.apply(state, event)` returns:

```text
ok: whether the event was accepted
state: a deep copy containing the next state, or the unchanged input on rejection
effects: presentation and protocol notifications emitted by the transition
error: a stable rejection message, empty on success
```

An event is rejected if its match id, exchange number, phase, sender, payload, or submission order is invalid. Rejected events never change state.

When initiative is tied at match or round start, player slot 0 starts. This tie-break keeps replay deterministic. Players alternate while both have unused living characters. If one player runs out first, the other finishes their remaining turns. A new round starts after every living character has acted.

## Combat resolution order

The resolution event contains only the true rolls verified by the protocol. The rules core combines them with the selected action, submitted claims, submitted challenges, and public character state.

Damage resolves in this order:

1. Resolve both challenge outcomes and any caught-bluff self-damage.
2. Cancel the attack if its padded attack claim was caught.
3. Calculate effective attack, effective defence, and margin.
4. Add positive margin to the attacker's Damage stat.
5. Apply the target position percentage and round down.
6. Double damage for a wrong call against an honest attack claim.
7. Halve damage for a wrong call against an honest defence claim and round down.

If both players make a wrong call, the attack doubling and defence halving cancel each other. Padding self-damage ignores position scaling.
