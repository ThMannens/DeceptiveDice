# Deceptive Dice — development spec

Two-player online game about lying on dice rolls. Peer to peer over the internet. Godot 4, GDScript.

## Problem statement

Bluffing games need a trusted referee. A physical game has one because everyone watches the die land. An online game normally has one because a server rolls the die and holds the secret. This game has neither: it runs peer to peer, and the whole point is that a player reports a number nobody else can see.

Without a fix, a cheating peer can roll until it likes the result, or change its roll after seeing whether the opponent challenged. Both attacks are invisible to the opponent and both destroy the game. Online this is not hypothetical. The opponent is a stranger with no social cost for running a modified client, and a modified client wins every match. The fix has to be in place before any combat rule is written, because it decides the shape of every exchange.

Two peers on the open internet also cannot find each other unaided. Home connections sit behind NAT, so some third party has to introduce them. Pure peer to peer with zero infrastructure is not available; the question is only how small the infrastructure can be.

## Solution

Roll generation and roll reporting are split.

The value of a die is derived from two secrets, one per peer, so neither peer controls it. The roller learns the value; the opponent does not, until reveal. The roller is committed to that value before the opponent decides whether to challenge, so the reported number is the only thing the roller controls, and that is exactly the lie the game is about.

On top of that sits a deterministic combat reducer that both peers run against the same event stream. Neither peer is authoritative. Divergence means someone cheated or something broke, and the match aborts.

For connection, a small signalling server introduces the two peers and then drops out of the match. It never sees a secret, never sees a roll, and holds no game state. Gameplay traffic goes directly between peers, with a relay fallback for the connections that cannot be punched through.

## Vocabulary

- **Roll** — the true d20 value, derived from both peers' secrets.
- **Claim** — the value a player reports. Always greater than or equal to the roll, never above 20.
- **Padding** — claim minus roll. Zero means honest.
- **Challenge** — an opponent's assertion that a claim is padded.
- **Caught** — challenged with padding above zero.
- **Wrong call** — challenged with padding of zero.
- **Locked in** — a claim that survived the challenge phase, whether unchallenged or wrongly challenged. Kit effects fire only on locked-in claims.
- **Exchange** — one attacker turn, from move selection through resolution.
- **Round** — every living character on both sides has acted once.

## The commit-reveal protocol

This is the load-bearing part. Both peers implement it identically.

Per die, with the roller R and the observer O:

1. R generates a 32-byte secret and sends `hash(secret_R)` to O.
2. O generates a 32-byte secret and sends `secret_O` to R in the clear.
3. R computes `roll = (hash(secret_R || secret_O) mod 20) + 1`. Only R knows the roll.
4. R declares a claim.
5. O declares challenge or pass.
6. R sends `secret_R`. Both peers verify the hash from step 1 and recompute the roll.

Properties this buys, all of which should be stated as tests:

- R cannot steer the roll, because R commits to `secret_R` before seeing `secret_O`.
- O cannot learn the roll before the challenge decision, because O never has `secret_R` until step 6.
- R cannot change the roll after seeing the challenge decision, because the hash pins it.
- A malformed or non-matching reveal is not a draw and not an error. Treat it as caught: the claim is discarded and the claimant takes the maximum possible padding for that claim as damage.
- Failure to reveal within the timeout resolves the same way. Quitting rather than revealing must never be better than being caught.

Simultaneous exchanges run two instances of this protocol, one in each direction, interleaved. Attacker is R for the attack die; defender is R for the defence die.

## Exchange structure

Both rolls happen. Both claims are declared blind, so neither player sees the other's claim before committing to their own. Then both challenge phases resolve simultaneously.

1. Active player selects an unused living character, a move, and a target.
2. Attack die and defence die both run the commit phase.
3. Both players declare claims. Neither sees the other's claim until both are submitted.
4. Both players declare challenge or pass. Neither sees the other's decision until both are submitted.
5. Both reveal. Verify. Resolve.

Blind declaration is what makes the defence bluff a different decision from the attack bluff rather than a repeat of it. Do not add a phase where the defender sees the attack claim first.

## Resolution

Effective attack is the resolved attack value plus the attacker's Attack stat plus move modifiers. Effective defence is the resolved defence value plus the defender's Defence stat plus move modifiers.

```
margin = effective_attack - effective_defence
if margin <= 0: miss
else: damage = attacker.Damage + margin, scaled by target position
```

Which value resolves depends on the challenge outcome:

| Claim | Challenge | Resolves at | Extra |
|---|---|---|---|
| Honest | Pass | Claim | Locked in |
| Padded | Pass | Claim | Locked in, kit bluff effects fire |
| Padded | Challenge (caught) | Attack cancelled entirely | Attacker takes padding as damage |
| Honest | Challenge (wrong call) | Claim | Damage doubled |

Defence side is symmetric:

| Claim | Challenge | Resolves at | Extra |
|---|---|---|---|
| Honest | Pass | Claim | Locked in |
| Padded | Pass | Claim | Locked in, kit bluff effects fire |
| Padded | Challenge (caught) | True roll | Defender takes padding as damage |
| Honest | Challenge (wrong call) | Claim | Incoming damage halved, rounded down |

Claims are capped at 20 by the die itself, so no separate padding cap is needed. A claim of 20 is legal from anyone and maximally suspicious.

## Positions

Four positions per side, 1 at the back, 4 closest to the enemy. Targeting is free unless a kit restricts it.

Damage taken multiplier by target position: 1 gives x0.7, 2 gives x0.85, 3 gives x1.0, 4 gives x1.2. Round down.

Heavy attack requires position 3 or 4. This is what stops the whole formation from hiding at the back.

## Basic moves

- **Light attack** — Damage as stat. No position requirement.
- **Heavy attack** — Damage +8, attack roll modifier -4, positions 3 and 4 only.
- **Defensive stance** — No attack. +5 to this character's defence rolls until their next turn.
- **Swap** — Swap with an adjacent ally. No attack.

## Roster

Five characters. Each player drafts four. Base stats: HP 60, Defence 0, Attack +2, Damage 20, Initiative 5.

### The Ledger — HP 55, Def +1, Atk +2, Dmg 18, Init 6

**Bookkeeping.** The Ledger records every claim its owner makes with any character. A claim whose value has already been claimed once this match cannot be challenged and locks in automatically.

**Audit.** When the Ledger correctly calls a bluff, the bluffing character's next claim this round is capped at the value of their previous claim.

Bookkeeping gives free immunity at the cost of telegraphing which number is coming.

### The Bruiser — HP 70, Def -2, Atk +3, Dmg 24, Init 3

**Thick Skull.** Padding damage from being caught is halved.

**Front Fighter.** +6 damage from position 4. No damage bonus from positions 1 and 2.

The character who can afford to lie, which is exactly why sitting on honest rolls with him works.

### The Mirror — HP 50, Def +2, Atk +1, Dmg 16, Init 8

**Reflect.** When the Mirror correctly calls a bluff, the Mirror deals the padded amount as damage to the bluffer instead of the bluffer taking it as self-damage.

**Read the Room.** If the Mirror's own claim locks in, the Mirror's next challenge this round cannot be a wrong call. It resolves as correct if the claim was padded and costs nothing if it was honest.

Low offence. Her value is punishing liars, which counters the Bruiser directly.

### The Gambler — HP 45, Def 0, Atk +2, Dmg 20, Init 7

**All In.** If the Gambler's claim is 15 or higher and locks in, margin damage is doubled. If caught, the Gambler takes double padding.

**Cold Streak.** Each consecutive turn the Gambler claims honestly, the padding damage on their next caught bluff drops by 3, to a maximum reduction of 9. Reset on any padded claim.

The only kit whose honest and dishonest incentives are linked. The line is honest, honest, honest, then one large lie.

### The Hook — HP 60, Def 0, Atk +1, Dmg 14, Init 4

**Drag.** On a successful hit, pull the target one position toward the front. A target already at position 4 takes 8 extra damage instead.

**Slippery.** When caught, the Hook swaps positions with an ally instead of taking padding damage.

Sets up the Bruiser, gets shut down by the Ledger's Audit.

## User stories

1. As a player, I want to host a match and get a short lobby code, so that I can send it to an opponent anywhere.
2. As a player, I want to join by entering a lobby code, so that I can start playing without knowing anyone's address.
3. As a player, I want a clear message when the connection cannot be established, so that I know to retry rather than wait.
4. As a player, I want a short window to reconnect after a brief network drop, so that a dropped wifi packet does not cost me the match.
5. As a player, I want an opponent who disconnects for good to forfeit, so that leaving is never better than losing.
6. As a player, I want to draft four characters from the roster before the match, so that I make a strategic choice before any dice are thrown.
7. As a player, I want to place my drafted characters in positions 1 through 4, so that I control my exposure.
8. As a player, I want to see both full rosters, all stats, and all kit effects at all times, so that my reads are based on public information.
9. As a player, I want to select a character, a move, and a target on my turn, so that I take an action.
10. As a player, I want illegal moves to be blocked with a visible reason, so that I do not lose a turn to a rules mistake.
11. As a player, I want to see my true roll privately, so that I can decide what to claim.
12. As a player, I want to submit a claim between my true roll and 20, so that I can lie by as much as I choose.
13. As a player, I want to see my opponent's claim only after I have submitted my own, so that the defence bluff is a blind decision.
14. As a player, I want to challenge or pass within a visible time limit, so that the decision has pressure.
15. As a player, I want the full outcome shown after reveal, including both true rolls, both claims, and every damage source, so that I can learn my opponent's tendencies.
16. As a player, I want a log of every claim my opponent has made this match, so that I can build a read across rounds.
17. As a player, I want kit effects to fire visibly and be named when they fire, so that I understand why a number changed.
18. As a player, I want the match to end when all four of my opponent's characters are dead, so that there is a clear win condition.
19. As a player, I want a failed reveal to be treated as being caught, so that refusing to reveal is never better than being caught.
20. As a host, I want the match to abort with a clear message if the two peers' states diverge, so that a desync is not silently played out.
21. As a developer, I want the combat rules to run headlessly with no Godot scene tree, so that the full ruleset is testable in one command.
22. As a developer, I want a match to be reproducible from a recorded event stream, so that any reported bug can be replayed exactly.
23. As a developer, I want a scripted bot opponent, so that full matches can be run in tests without a second human.
24. As a developer, I want the protocol layer testable with two in-process peers, so that network behaviour is verifiable without real sockets.

## Implementation decisions

### Modules

**Rules core.** Pure and deterministic. A reducer of the form `apply(state, event) -> (state, effects)`. No Godot node dependencies, no randomness, no clock, no network. Every combat rule, kit effect, position rule, and damage calculation lives here. This is the single seam the test suite targets.

**Protocol.** Commit-reveal, message schema, phase enforcement, verification, timeouts. Produces events for the rules core. Knows nothing about combat.

**Transport.** WebRTC data channels through Godot's WebRTCMultiplayerPeer, with a signalling server over WebSocket. Reliable ordered channel only; nothing here needs unreliable delivery. Knows nothing about the game.

**Presentation.** Godot scenes. Reads state, emits intents. Contains no rules.

**Bots.** Scripted policies that consume state and emit intents, used by tests and by solo play.

The dependency direction is one way: presentation and protocol depend on the rules core; the rules core depends on nothing.

### State machine

Exchange phases, strictly ordered. Any message arriving out of phase is rejected, not queued.

```
SELECT      -> active player submits character, move, target
COMMIT      -> both peers exchange hash(secret) and secret
CLAIM       -> both peers submit claims, revealed to each other only when both are in
CHALLENGE   -> both peers submit challenge/pass, revealed only when both are in
REVEAL      -> both peers send secrets, both verify
RESOLVE     -> reducer applies the exchange, effects fire
```

A phase advances only when both peers have submitted. Timeouts resolve as: no claim submitted means an honest claim, no challenge submitted means pass, no reveal means caught.

### Determinism and desync

Both peers run the same reducer over the same event stream. After each RESOLVE, peers exchange a hash of the resulting state. A mismatch aborts the match with a desync message naming the exchange number. Build this in the first working version, not later. Retrofitting a desync check into a game that has already diverged in twelve places is much worse than having it from the start.

All randomness enters through the commit-reveal protocol. The rules core never calls a random function.

### Message schema

Every message carries a match id, an exchange number, a phase, and a sender. A message whose exchange number or phase does not match local state is dropped and logged. This single rule prevents most replay and reorder problems and is cheap to test.

### Connection

The signalling server is the smallest piece that can do the job. It does three things and nothing else:

1. Issues a short lobby code to a hosting peer.
2. Matches a joining peer to that code.
3. Relays WebRTC offers, answers, and ICE candidates between the two until the data channel opens.

Once the channel is open the server is out of the match. It never receives a secret, a claim, or a state hash. If it goes down mid-match, running matches continue.

STUN handles most NAT traversal. A meaningful share of connections will still fail, mostly symmetric NAT, so a TURN relay is needed for those. Traffic through TURN is still end to end from the game's perspective; the relay forwards bytes and holds no state. Budget for a public STUN server and either a hosted TURN service or a small self-run one.

The alternative, if the jam ships on Steam, is Steam Networking Sockets. It solves NAT traversal, relay, and identity in one dependency and removes the signalling server entirely. It costs a Steam dependency and makes headless testing harder.

### Latency and disconnection

Online play adds a clock that LAN did not have. Every phase timeout must be generous enough for a 200ms round trip plus the human decision, and the timer shown to the player starts when their client receives the phase, not when the opponent sent it.

Timeouts already have defined outcomes in the phase section. Add:

- **Brief drop.** A peer that loses the data channel gets a reconnection window of about 30 seconds. The signalling server keeps the lobby code alive for that window so the peer can re-establish. On reconnect, both peers exchange their current exchange number and state hash. Matching hashes resume the match. Mismatched hashes abort it.
- **Long drop.** Exceeding the window ends the match as a loss for the peer that dropped.
- **Drop during REVEAL.** Resolves as caught, per the protocol section. A player losing an exchange must never be able to improve their position by pulling their network cable.

Do not build state resynchronisation. Both peers hold the full event stream, so a resuming peer either agrees or is desynced, and there is no useful third case.

### Turn order

Players alternate turns within a round. Each turn, the active player picks any unused living character. The player whose highest-initiative living character is greater takes the first turn of the round.

## Testing decisions

The rules core is the seam. Test there, not below it.

**Transcript tests.** A test is a list of events and a set of assertions on the resulting state. Store them as data, not as code. An agent adding a kit effect should be able to add a transcript that fails, then make it pass, without touching test scaffolding. This is the primary test form and most coverage should live here.

**Coverage bar.** Every row of both resolution tables, for every kit effect, has a transcript. That is the exhaustiveness criterion: a kit is not done until each of its two effects has a transcript for firing, for not firing, and for interacting with a challenge outcome.

**Protocol tests.** Two in-process peers, no sockets. Assert each property in the protocol section directly: a peer that changes its secret after the challenge phase is rejected, a peer that never reveals is resolved as caught, a peer that sends a CLAIM during COMMIT is dropped.

**Adversarial peer.** A test peer that deliberately misbehaves: wrong hashes, out-of-phase messages, claims below the true roll, claims above 20, silence. Every one of these has a defined outcome in this spec and each outcome gets a test.

**Full-match tests.** Two bots play to a win condition. Assert the match terminates, that no state hash mismatch occurs, and that HP never goes below zero or above maximum.

**One command.** The whole suite runs headless in a single command with no editor and no display. Agentic work depends on a fast red loop more than on anything else in this document.

## Out of scope

- Matchmaking, accounts, ranking, persistence between matches. Connection is by lobby code only.
- Any server-side game logic. The signalling server introduces peers and holds no state.
- More than two players.
- Spectators and replay playback UI. The event stream is recorded, but nothing plays it back.
- The special moves from the original brainstorm that no kit uses: guard, bleed, poison, heal, AOE, stun, generic parry. They are folded into kits or dropped.
- Cheat resistance beyond the protocol described here. A peer reading its own memory to see its own secret gains nothing. A peer that automates optimal bluff frequency is undetectable and out of scope for a jam.

## Open decisions

**Draft format.** Five characters, four drafted, means near-mirror matches. Alternatives: expand the roster to seven and draft four, or allow duplicates, or use fixed asymmetric teams. Blocked on nothing but roster authoring time. Default to draft four of five for the jam.

**Transport stack.** WebRTC plus a self-run signalling server is the default above. Steam Networking Sockets removes the server and the TURN problem at the cost of a Steam dependency and harder headless testing. Decide before step 5 of the build order, because everything before it is transport-agnostic.

**TURN hosting.** A relay is needed for the connections STUN cannot punch through. Hosted service or self-run is unresolved and depends on jam budget. Blocked on nothing but a decision.

**Challenge limits.** Challenges are unlimited. The costs on both sides are steep enough that this may hold, but if playtests show both players challenging every claim, cap challenges at three or four per match. Blocked on playtest data.

**Turn order.** The alternating-with-free-choice rule above is a default, not a settled decision. The alternative is a strict initiative order across both teams, which makes Initiative a much stronger stat and removes a layer of choice. Blocked on playtest data.

**Damage numbers.** Every stat and modifier in this document is a first pass. Check specifically whether a natural 20 plus a large padding plus a heavy attack can remove a third of a health bar in one exchange. If it can, matches will turn on single rolls rather than on reads. Blocked on playtest data.

**Kit effect edge cases.** Bookkeeping and Read the Room can interact in ways not yet enumerated: a Mirror challenge against a Ledger claim that is already immune, for example. Enumerate these while writing the transcripts, and record the resolution here as it is decided.

## Further notes

Build order that keeps the red loop live throughout:

1. Rules core with basic moves only, no kits, no network, driven by a local event list.
2. Transcript test harness and the first transcripts.
3. Commit-reveal protocol with two in-process peers.
4. Desync detection.
5. Signalling server, lobby codes, WebRTC transport.
6. Minimal UI: roster, positions, claim entry, challenge button, outcome log.
7. Kits, one at a time, each with its transcripts before it is considered done.
8. Reconnection window and forfeit handling.
9. Bots and full-match tests.

Steps 1 through 4 have no Godot dependency beyond GDScript itself and no network, so they can be built and tested before any scene or socket exists. Do not let the networking work start earlier than step 5. It is the part most likely to consume the jam, and the game is playable hot-seat without it.

Test the real connection path on the first day it exists, from two different physical networks, not two windows on one machine. NAT traversal failures do not reproduce locally and they are the failure that will surface at the demo.

The design test to apply to every kit effect added later: write down what happens if the player uses it every single turn, and what happens if they never use it. If either is obviously correct, the effect needs reshaping. The target is a kit where lying is right in some board states, honesty is right in others, and the opponent cannot tell which state you are in from public information.
