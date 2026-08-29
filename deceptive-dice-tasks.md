# Deceptive Dice — task breakdown

Companion to the dev spec. Task IDs are stable, so use them in commits and branch names.

Written for four to five people. If you are fewer, cut the roster to three characters and drop workstream F to a stylesheet.

## The one thing that has to happen first

Everything downstream depends on two schemas: the match state and the event list. Until those exist, nobody can work in parallel without guessing, and guesses diverge in ways that cost a day to merge.

Do task 0 together, in one room, before anyone opens a branch. Timebox it to two hours. It does not have to be right, it has to be shared.

**Task 0 — State and event schema.** Write down every field in the match state, and every event that can change it. State covers both teams, each character's HP and position and per-match effect counters, whose turn it is, the current phase, the exchange number, and the claim history. Events cover move selection, both commits, both claims, both challenges, both reveals, and phase timeouts. Nothing else in this document can start until this is agreed.

Done when: both schemas are committed as data definitions and every task owner below has read them.

---

## Workstream A — Rules core

Pure GDScript. No scene tree, no network, no clock, no random calls. One person owns this. It is the highest-risk work because everything else asserts against it.

**A1 — Reducer skeleton.** `apply(state, event) -> (state, effects)`. Phase transitions only, no combat. Rejects out-of-phase events. *Depends on: 0.* Done when: a hardcoded event list drives a match from draft to first exchange and back to SELECT.

**A2 — Damage resolution.** Margin calculation, position multipliers, the two resolution tables from the spec. *Depends on: A1.* Done when: all eight rows of both tables produce the numbers in the spec.

**A3 — Basic moves.** Light, heavy, defensive stance, swap. Position restriction on heavy. *Depends on: A2.*

**A4 — Turn and round structure.** Alternating turns, unused-character tracking, round rollover, initiative for first turn. *Depends on: A1.*

**A5 — Win and loss.** Death removal, four-dead win check, forfeit. *Depends on: A4.*

**A6 — Kit effect hook API.** The interface kits implement: which events they observe, what they may modify, resolution order when two fire at once. Publish this early even if empty, because workstream B is blocked on it. *Depends on: A2.* Done when: a stub kit with one effect fires through the reducer and workstream B can start.

**A7 — State hashing.** Deterministic hash of the full state for desync detection. *Depends on: A1.*

---

## Workstream B — Kits

One person, or split two ways. Each kit is independent, so this parallelizes well once A6 lands.

**B1 — The Bruiser.** *Depends on: A6.*
**B2 — The Mirror.** *Depends on: A6.*
**B3 — The Ledger.** *Depends on: A6.* Bookkeeping touches the challenge phase, so coordinate with C3.
**B4 — The Gambler.** *Depends on: A6.*
**B5 — The Hook.** *Depends on: A6, A3.* Drag moves positions, so it needs swap logic in place.

Each kit is done when both its effects have transcripts for firing, for not firing, and for interacting with a challenge outcome. Not before.

Build B1 and B2 first. They are the opposed pair, and if that matchup is boring the whole system needs rethinking, which you want to learn on day two rather than day five.

---

## Workstream C — Protocol

One person. Runs alongside A without touching it.

**C1 — Commit-reveal module.** Already written. Wire it in and test it. *Depends on: nothing.* Done when: a thousand derived rolls are uniform across 1 to 20, and a tampered secret fails verification.

**C2 — Phase machine.** SELECT through RESOLVE, both peers, waiting for both submissions before advancing. *Depends on: 0, C1.*

**C3 — Blind simultaneous submission.** Claims held until both are in, challenges held until both are in. This is the mechanic, so it gets its own task. *Depends on: C2.*

**C4 — Timeout handling.** *Done.* 60s select, 45s claim, 30s challenge, started on local receipt. The default is submitted through the ordinary path so both reducers stay in step. A failed or missing reveal resolves as caught at a true roll of 1 and never aborts the match. Covered by `tests/transcripts/c4_phase_timeouts.json`.

**C5 — In-process two-peer harness.** Two protocol instances in one process, no sockets. Everything in C is tested through this. *Depends on: C2.* Done when: workstream D can be developed against it without a real connection.

**C6 — Adversarial peer.** Deliberately misbehaves: bad hashes, out-of-phase messages, claims below the roll or above 20, silence. Every case has a defined outcome in the spec. *Depends on: C5.*

---

## Workstream D — Transport

One person. The riskiest schedule item, so start it early even though it lands late.

**D1 — ~~Signalling server~~ Manual signalling.** *Cut, replaced.* No server: the host emits an offer code, the joiner pastes it and returns an answer code, and players move the codes themselves. A plain ENet address transport covers LAN play and the headless tests. See the Connection section of the spec for the reasoning and what it costs.

**D2 — WebRTC peer.** *Done.* Godot side, reliable ordered channel, connected through pasted codes rather than a server. Both waits are bounded, because WebRTC reports no error when two peers simply cannot reach each other.

**D3 — Protocol over transport.** Swap C5's in-process harness for the real channel. If C was built properly this is a small change. *Depends on: D2, C5.*

**D4 — Two-network test.** Two people, two physical networks, one full match. Not two windows on one machine. *Depends on: D3.* Run this the day D3 lands. NAT failures do not reproduce locally and this is what breaks at the demo.

**D5 — ~~TURN fallback~~.** *Cut.* A relay is infrastructure, and this build ships none. Connections STUN cannot punch through fail with a message saying so and an offer of the same-network path.

**D6 — Reconnection window.** *Done.* Thirty seconds, exchange number and state hash compared on resume, phase clock stopped while the window is open. Address transport only; the manual-code path cannot be waited out. Covered by `tests/reconnect_smoke.gd`.

---

## Workstream E — Interface

One person. Can start as soon as task 0 lands, using fake state.

**E1 — Board view.** Two teams, four positions each, HP bars, initiative order. *Depends on: 0.*

**E2 — Kit information display.** All stats and both effects for every character, visible always. This is public information the whole game depends on, so it cannot be buried in a tooltip. *Depends on: 0.*

**E3 — Move selection.** Character, move, target. Illegal moves blocked with a visible reason. *Depends on: E1, A3.*

**E4 — Claim entry.** Private roll display, claim slider or input constrained between the true roll and 20. *Depends on: 0.*

**E5 — Challenge prompt.** *Done.* Both claims with the totals they resolve to, the margin between them, challenge or pass, and a countdown online. Hot-seat has no countdown by design.

**E6 — Reveal and resolution.** Both true rolls, both claims, every damage source itemised, kit effects named as they fire. *Depends on: E5, A2.*

**E7 — Claim history panel.** Every claim the opponent has made this match. Cheap to build and it is where the reads come from. *Depends on: E6.*

**E8 — Draft and placement.** *Done for hot-seat.* Pick four of five with full stats and kit text on the cards, then order them back to front. Online play still uses preset teams. Covered by `tests/transcripts/e8_draft_and_placement.json` and the UI smoke.

**E9 — Lobby.** *Done.* Host and get a code to paste, join by pasting one, or connect by address on a shared network. Connection failures say which wait expired and offer the same-network path.

---

## Workstream F — Presentation

Whoever has time. Nothing depends on this, so it is also the first thing to cut.

**F1 — Character art.** Five characters. Silhouette-readable at position size.
**F2 — Dice and reveal animation.** The reveal is the emotional beat of every exchange. Spend time here before spending it anywhere else in F.
**F3 — Sound.** Roll, claim submitted, challenge, caught, wrong call. Five sounds, and the caught sound matters most.
**F4 — Tension pass.** Timer pressure, the moment both claims flip face up.

---

## Workstream G — Tests

Shared. Everyone writes transcripts for their own work. One person owns the harness.

**G1 — Transcript harness.** Tests are data: an event list plus assertions. Adding a test must not require touching scaffolding. *Depends on: A1.*

**G2 — Single command runner.** Full suite, headless, no editor, no display. *Depends on: G1.* Done on day one of workstream A, not later.

**G3 — Scripted bots.** *Done.* `src/bots/bot_policy.gd`, seeded rather than random so a failing match is reproducible.

**G4 — Full-match test.** *Done.* Twelve seeded matches per run, asserting termination, HP bounds, and hash stability. Current lengths: 21 to 33 exchanges, median 26.

---

## Suggested split

Person 1: A, then G4. The reducer owner should also own the end-to-end test.
Person 2: C, then B3 and B4.
Person 3: D. Starts on D1 immediately, it has no dependencies.
Person 4: E.
Person 5: B1, B2, B5, then F.

If four people, fold F into whoever finishes first and accept placeholder art.

## Critical path

Task 0, then A1, A2, A6, then the kits, then G4.

Transport is the parallel risk. It has no dependency on the rules core at all, which means it can be finished early or discovered broken early. D4 is the checkpoint. If it has not run by the midpoint of the jam, cut online play to hot-seat on one machine and ship the game. A hot-seat bluffing game is a real game. A networked one that does not connect at the demo is not.

## Playtest checkpoints

Do not leave these to the end.

After A3 and E3, play a match with no kits and no lying, just moves and rolls. Confirm the combat is not boring on its own.

After B1 and B2, play the Bruiser against the Mirror, hot-seat, on paper if needed. This is the design test. If it does not produce interesting decisions, the kit system needs changing and you want to know now.

After G4, run twenty bot matches and check the length. Twenty successful hits to win may be too long. Damage numbers are the easiest thing to change and the last thing anyone remembers to check.

*Done:* twelve matches per suite run, 21 to 33 exchanges, median 26. Length is fine. The single-exchange damage spike is still unchecked, because neither bot policy chooses its padding and so neither sets up the case that worry is about.
