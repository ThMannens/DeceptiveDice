# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Deceptive Dice is a two-player bluffing combat game in Godot 4.6 / GDScript, playable hot-seat locally and peer-to-peer online with **no game server**. Hidden d20 rolls are protected by commit-reveal; both peers run the same deterministic reducer and compare a full-state hash after every exchange.

Two design documents are the authority on rules and intent, and are worth reading before non-trivial work:

- `deceptive-dice-dev-doc.md` — the spec: protocol properties, resolution tables, module boundaries, testing decisions.
- `docs/state-and-event-schema.md` — the state/event data contract shared by core, protocol, tests, and UI.
- `deceptive-dice-tasks.md` — task IDs (A1, B3, C4, …) used in commits and branch names, and in source comments.

## Commands

```powershell
.\run-tests.ps1                    # full suite, headless
.\run-tests.ps1 -GodotPath <path>  # when godot is not on PATH
.\run-two-players.ps1              # two windowed instances side by side for online testing
```

`run-tests.ps1` runs stages sequentially and stops at the first failure: reducer/protocol tests (`tests/run_tests.gd`), full-match bot test, UI smoke, WebRTC smoke, online match smoke, WebRTC timeout smoke, disconnect smoke, direct match smoke, reconnection smoke. It imports the bundled native WebRTC extension first if `.godot/extension_list.cfg` lacks it.

Run one stage directly (much faster than the whole script):

```powershell
godot --headless --path . --script "res://tests/run_tests.gd"
godot --headless --path . --script "res://tests/network_match_smoke.gd"
```

Each stage writes its exit code to a `tests/*-result.tmp` file and its log to `.godot/*.log`; the PowerShell script reads those rather than trusting Godot's exit code alone. Check the `.godot` log when a stage fails without useful console output.

There is no single-test filter. To run one reducer scenario, temporarily narrow `_find_transcripts()` in [tests/run_tests.gd](tests/run_tests.gd) or move the other transcripts aside.

## Architecture

Dependency direction is one way: presentation and protocol depend on the rules core; **the rules core depends on nothing**.

### `src/core` — rules core (pure)

`MatchReducer.apply(state, event) -> {ok, state, effects, error}`. No scene tree, no clock, no randomness, no network, no I/O. Returns a deep copy on success and the unchanged input on rejection. Events are append-only and replayable from a fresh initial state.

- [match_reducer.gd](src/core/match_reducer.gd) — the whole state machine and damage resolution (~1000 lines; the largest single seam).
- [match_state.gd](src/core/match_state.gd) / [match_event.gd](src/core/match_event.gd) — the schema in `docs/state-and-event-schema.md` as code.
- [kits.gd](src/core/kits.gd) — per-character effects behind a **pure hook API** (`modify_self_damage`, `redirect_self_damage`, `after_exchange`). Kits never mutate state; they return a decision and the reducer applies it. Hook firing order is fixed (attacker's character, then defender's; then by player slot and board position) so replay stays deterministic. See the header comment in that file before adding an effect.
- [combat_resolver.gd](src/core/combat_resolver.gd), [roster.gd](src/core/roster.gd), [moves.gd](src/core/moves.gd) — stats and move definitions as data tables.
- [state_hash.gd](src/core/state_hash.gd) — canonical encoding (sorted keys) then SHA-256, for desync detection.

Phases: `SELECT → COMMIT → CLAIM → CHALLENGE → REVEAL → RESOLVE`. A phase advances only when both players have submitted. Out-of-phase events are rejected, never queued. Ties in initiative go to player slot 0.

### `src/protocol` — commit-reveal (no combat knowledge)

[commit_reveal.gd](src/protocol/commit_reveal.gd) derives the roll as `(sha256(secret_R || secret_O) mod 20) + 1`, so neither peer controls it. [exchange_protocol.gd](src/protocol/exchange_protocol.gd) drives one exchange: commits, then blind claim commit/reveal, then blind challenge commit/reveal, then roll reveal. Claims and challenges are themselves committed so neither player sees the other's choice first — that blindness is the core mechanic, not an optimization.

### `src/network` — transport and online coordinator

[network_match.gd](src/network/network_match.gd) is the online counterpart of the local coordinator: it owns the reducer, drives `ExchangeProtocol`, and exchanges state hashes after every resolution. A mismatch aborts the match. [webrtc_transport.gd](src/network/webrtc_transport.gd) plus [manual_signal_code.gd](src/network/manual_signal_code.gd) implement serverless signalling — players copy offer/answer codes by hand, so there is no lobby or signalling server. [direct_transport.gd](src/network/direct_transport.gd) is a plain address-based ENet path used for LAN and tests. Both waits (candidate gathering, channel open) are explicitly bounded, because WebRTC reports no error when peers simply cannot reach each other.

### `src/bots` — scripted policies

[bot_policy.gd](src/bots/bot_policy.gd) reads state and returns intents, never applying an event or holding a coordinator. Two policies: always honest, and always pad to 20. They exist for the full-match test and as the balance baseline.

### `src/local` — hot-seat coordinator

[hotseat_match.gd](src/local/hotseat_match.gd) is trusted and rolls locally with an RNG; it fills in placeholder commit/reveal payloads since there is no adversary. It is the only place outside tests that may call a random source.

### `src/presentation` — Godot scene, no rules

[main.gd](src/presentation/main.gd) builds the whole UI in code (no scene-tree editing beyond `main.tscn`) and holds `game` as either a `HotseatMatch` or a `NetworkMatch`. It reads state and emits intents only. It owns stage routing, the layout shell, and intent orchestration; the reusable pieces live beside it.

The look is specified in [docs/larp-ui-visual-overhaul.md](docs/larp-ui-visual-overhaul.md): a weekend LARP tournament assembled from real craft materials. Resolve visual questions against that document rather than inventing a second language.

- [theme.gd](src/presentation/theme.gd) — the whole palette and every reusable style. Presentation code must not introduce colour literals; ask for a paper stock (`paper_style`), a card state (`team_card_style`), a patch, or a prop button instead. `UiTheme.reduced_motion` is the presentation-only motion switch every animated sequence checks.
- `ui/` — [widgets.gd](src/presentation/ui/widgets.gd) (labels, patches, prop buttons), [battlefield.gd](src/presentation/ui/battlefield.gd), [fighter.gd](src/presentation/ui/fighter.gd), [fighter_rigs.gd](src/presentation/ui/fighter_rigs.gd), [plate_button.gd](src/presentation/ui/plate_button.gd), [phase_ribbon.gd](src/presentation/ui/phase_ribbon.gd), [claim_sheet.gd](src/presentation/ui/claim_sheet.gd), [portrait.gd](src/presentation/ui/portrait.gd). Each accepts state and reports clicks; none queries the reducer.

The board is [battlefield.gd](src/presentation/ui/battlefield.gd): both crews stand facing each other on one ground line, position 1 farthest from the opponent and position 4 closest, which is the order the position damage multiplier uses. Each figure is a [fighter.gd](src/presentation/ui/fighter.gd) — an animated rig inside a `SubViewport` plus a clickable nameplate above it. The rig is decoration; the plate is the whole interface, so a character with no rig yet is a visual state and the board stays keyboard-reachable either way. The paper `character_card.gd` and `team_roster.gd` this replaced are gone; the draft and placement screens draw their own rows.

[fighter_rigs.gd](src/presentation/ui/fighter_rigs.gd) maps a character id to its rig scene in [scenes/](scenes/) and translates the board's beats — idle, move, hurt, attack — into that rig's own animation names. Adding art for a character means adding a row there and nothing else. Attack variants are picked by exchange number, never randomly, so a replay swings identically on both peers.
- `animation/` — [resolution_sequence.gd](src/presentation/animation/resolution_sequence.gd) plays the reveal from `last_resolution` fields only. It never infers a rule: if a beat cannot be derived from an existing field, add a presentation effect to the reducer's `effects` output rather than recomputing it here.

The layout has three size tiers (compact below 1180px wide, roomy at 1600x900 and above). Every column bounds its own contents so the pinned decision footer can never fall below the fold; that is what the `1024x640` assertion in the UI smoke test protects.

Character portraits load from `src/presentation/assets/portraits/<id>.png` when present and fall back to a styled placeholder otherwise. A missing export is a visual state, never an error.

## Tests

**Transcript tests are the primary form.** A scenario is a JSON file in [tests/transcripts/](tests/transcripts/): an initial state, optional `setup_steps`, then `steps` of `{event, expect_ok, error_contains, assertions}`. Assertions are `{path, equals}` over dotted state paths. To cover a new rule or kit effect, add a transcript — not test scaffolding code. Rejection steps also assert that state was not mutated.

Transcript files are named by task ID (`a5_wrong_call_cost.json`, `b4_bard.json`). A kit is not considered done until each of its effects has a transcript for firing, for not firing, and for interacting with a challenge outcome.

JSON numbers parse as floats while the reducer holds ints; `_values_match` recurses so transcripts need not care.

The `tests/*_smoke.gd` scripts each `extends SceneTree` and run one integration path headless, writing an exit code to a `.tmp` file.

[full_match_smoke.gd](tests/full_match_smoke.gd) plays twelve seeded bot matches to a win through the reducer, asserting termination, HP bounds, and hash stability. It is the only test that would catch a rule which lets a match run forever, since every other test drives a fixed number of exchanges.

## Conventions

- GDScript with tabs, static typing on function signatures, `##` doc comments on non-obvious functions.
- Comments explain *why* a rule exists, usually referencing a balance concern (e.g. `EXPOSED_DEFENCE_PENALTY` in the reducer). Match that density and register rather than restating what the code does.
- Cross-module references use `preload("res://src/...")` constants at the top of the file.
- Keep the core pure: if a change wants a clock, a socket, or `randi()` inside `src/core`, the design is wrong — pass the value in through an event instead.
