# Deceptive Dice — LARP UI visual-overhaul implementation specification

## Purpose

This document is the implementation contract for replacing the current dark felt and brass interface with a readable, animated UI themed around a group of modern LARPers fighting, boasting, and cheating at a homemade tournament.

It is written for an autonomous coding agent working in this repository. Follow the project architecture and rules documents; this specification is authoritative only for presentation, visual styling, layout, and presentation-layer animation.

The target is not a generic medieval-fantasy interface. It should feel like real people brought foam weapons, hand-painted shields, stitched tabards, cardboard score cards, and too much competitive energy to a weekend event.

## Required reading before implementation

Read these files before changing code:

1. `CLAUDE.md`
2. `deceptive-dice-dev-doc.md`
3. `docs/state-and-event-schema.md`
4. `src/presentation/main.gd`
5. `src/presentation/theme.gd`
6. `src/presentation/rules_tooltip.gd`
7. `src/core/kits.gd`, for canonical kit names and player-facing descriptions
8. `src/core/combat_resolver.gd`, for resolution fields and calculation order
9. `tests/ui_smoke.gd` and `tests/ui_screenshot.gd`

Do not copy combat rules into presentation code when a canonical value already exists in state, `Moves`, `Kits`, or `CombatResolver`.

## Non-negotiable architectural constraints

- Presentation reads state and emits intents. It does not decide combat results.
- Do not change reducer behavior, networking, commit-reveal behavior, phase order, or hidden-information boundaries for visual convenience.
- Never display an opponent's true roll before the reveal makes it public.
- Never display the other player's unsubmitted claim or challenge choice.
- Internal phase names remain unchanged. The UI may give them thematic display labels.
- All stats, both kit names, HP, position, readiness, and live statuses remain visible during play.
- Critical decision controls must fit without scrolling at 1280×720 and 1024×640.
- Animations must be skippable and must not delay or alter network messages.
- Do not require character art to complete the functional layout. Use a styled placeholder portrait when a final export is absent.
- Preserve unrelated user changes in the dirty worktree.

## Art-reference interpretation

The supplied character-face concept shows the intended character language:

- contemporary people rather than idealized fantasy archetypes;
- thick, imperfect dark outlines;
- flat warm colors with very limited shading;
- distinctive noses, hair, glasses, freckles, facial hair, and expressions;
- slightly awkward, comedic, human proportions;
- readable silhouettes and faces at small sizes;
- an indie-cartoon tone rather than realism, anime, pixel art, or painterly fantasy.

The supplied file is a phone photograph of a drawing application. It is a visual reference only. Do not crop the photograph, application chrome, monitor pixels, or photographed canvas into the game. Request or consume clean transparent exports when they become available.

### Production portrait asset contract

Final portraits should be exported as follows:

- PNG with transparency;
- sRGB;
- 512×512 source canvas;
- head and upper shoulders centered in a consistent safe area;
- at least 24 px transparent padding around the outer black stroke;
- no baked UI frame, team color, shadow, name, or background;
- stable paths:
  - `res://src/presentation/assets/portraits/scribe.png`
  - `res://src/presentation/assets/portraits/knight.png`
  - `res://src/presentation/assets/portraits/wizard.png`
  - `res://src/presentation/assets/portraits/bard.png`
  - `res://src/presentation/assets/portraits/hook.png`

Do not guess which concept face maps to which character. Use placeholders until the mapping or correctly named exports are supplied.

## Visual north star

Use the phrase **“weekend LARP tournament made from real craft materials”** to resolve design choices.

The interface should resemble a play surface assembled from:

- a dark wooden folding table or worn tent floor as the outer frame;
- canvas and burlap team areas;
- cream index cards and rulebook paper for information;
- marker-ink outlines and handwritten annotations;
- colored cloth tape for player ownership;
- stitched patches for kit effects and statuses;
- painted wooden or resin dice;
- rubber stamps for challenge outcomes;
- hard, slightly offset shadows that feel like layered paper.

The joke is affectionate. These players take their homemade battle extremely seriously, even while cheating about dice.

### Explicitly avoid

- neon casino styling;
- dark navy sci-fi panels;
- polished gold, royal marble, or luxury medieval heraldry;
- grimdark blood, horror, or realistic violence;
- generic parchment covering every pixel;
- distressed textures behind small text;
- excessive fake handwriting for body copy;
- soft glassmorphism, neon glows, and large pill-shaped SaaS controls;
- animation that hides arithmetic or turns a decision into spectacle before clarity.

## Color system

Replace the current navy-and-brass system. Centralize all colors in `src/presentation/theme.gd`; presentation components must not introduce arbitrary color literals.

| Token | Hex | Role |
|---|---:|---|
| `COLOR_INK` | `#2A211C` | Primary text, outlines, hard shadows |
| `COLOR_INK_MUTED` | `#67584D` | Secondary text on light surfaces |
| `COLOR_PAPER` | `#FFF8E9` | Highest information surface |
| `COLOR_PARCHMENT` | `#F3E2C2` | Cards, tooltips, secondary information |
| `COLOR_CARDBOARD` | `#C9A878` | Inactive surfaces and craft material |
| `COLOR_CANVAS` | `#A88761` | Team-area background |
| `COLOR_CANVAS_DARK` | `#6E513B` | Recesses, separators, disabled wells |
| `COLOR_WOOD` | `#4A3025` | Main backdrop and framing |
| `COLOR_WOOD_DARK` | `#291C18` | Deepest background and shadow |
| `COLOR_TAPE` | `#E7C95F` | Neutral tape, pinned notes, focus marker |
| `COLOR_ACCENT` | `#E69A32` | Primary actions and current phase |
| `COLOR_ACCENT_DARK` | `#8C541F` | Accent border and pressed state |
| `COLOR_PLAYER_ONE` | `#27738D` | Player 1 ownership only |
| `COLOR_PLAYER_ONE_LIGHT` | `#CFE7E8` | Player 1 pale surface tint |
| `COLOR_PLAYER_TWO` | `#874D82` | Player 2 ownership only |
| `COLOR_PLAYER_TWO_LIGHT` | `#E9D2E4` | Player 2 pale surface tint |
| `COLOR_SUCCESS` | `#3D784C` | Correct call, legal/ready, healing if added |
| `COLOR_DANGER` | `#A93628` | Caught bluff, damage, illegal state |
| `COLOR_WARNING` | `#C47B22` | Timer pressure and risky consequence |
| `COLOR_INFO` | `#4969A3` | Defence, protected, informational state |
| `COLOR_DISABLED` | `#A99B8B` | Disabled text and defeated desaturation |
| `COLOR_HEALTH_HIGH` | `#4F8755` | HP above 60% |
| `COLOR_HEALTH_MID` | `#C38B24` | HP from 31–60% |
| `COLOR_HEALTH_LOW` | `#A93628` | HP at or below 30% |

### Color-use rules

- Player colors communicate ownership, never success or failure.
- Green communicates a favorable or correct result.
- Rust red communicates harm, caught bluffs, and destructive actions.
- Orange communicates focus, progression, and primary actions.
- Never rely on hue alone. Pair color with a label, icon, border pattern, or shape.
- Use `COLOR_INK` on orange, tape yellow, parchment, and paper fills.
- Use `COLOR_PAPER` on dark wood, Player 1, Player 2, success, and danger fills.
- Keep body text on clean, nearly opaque paper surfaces. Grain belongs on the outer frame, not behind 11–15 px text.
- Do not use Player 2 purple for danger borders.

## Typography

Typography should support the handmade theme without sacrificing rules comprehension.

- Body and numbers: a highly readable humanist sans. Preferred: Atkinson Hyperlegible. Acceptable fallback: the current Godot default font until a font asset is deliberately bundled.
- Display headings: a friendly slab or poster face with an amateur-tournament feel. Preferred: Bree Serif SemiBold or another explicitly bundled font with comparable readability.
- Do not use blackletter for functional UI.
- Do not use a handwriting font below 18 px.
- Use tabular figures if the bundled body font supports them.
- Body: 14–16 px at 1280×720.
- Secondary text: never below 12 px.
- Character name: 16–18 px.
- Major claim and die values: 32–48 px.
- Section heading: 14 px uppercase or 18 px title case.

If font files are added, place them under `res://src/presentation/assets/fonts/` and record their license beside them.

## Shape, material, and icon language

- Reduce the current large rounded corners. Use 4–8 px radii for paper and card stock.
- Use 2 px ink-colored outlines around primary cards.
- Replace soft colored glows with a hard shadow offset approximately `(3, 4)` in `COLOR_WOOD_DARK` at 35–50% opacity.
- Player ownership appears as cloth tape, a stitched left edge, or a colored tab—not by tinting the entire card.
- Selected cards lift 3–5 px and gain an orange tape corner plus a stronger hard shadow.
- Disabled and defeated cards desaturate and gain a diagonal grey paper strip labeled `OUT` or `ACTED`.
- Statuses use stitched patch shapes with both icon and text.
- Kit effects use small fabric-patch labels; the full names remain visible.
- Tooltips resemble cream rulebook notes pinned over the interface. They remain fully opaque.
- Use simple, hand-drawn icons with the same dark stroke as the portraits. Never require an icon to understand a rule.

## Player-facing phase language

Keep internal constants unchanged. Use these display labels in the phase ribbon and prompts:

| Internal phase | Main label | Supporting label |
|---|---|---|
| `DRAFT` | Pick the crew | Choose four LARPers |
| `PLACEMENT` | Set the line | Back 1 → 4 front |
| `SELECT` | Pick a fighter | Choose move and target |
| `COMMIT` | Dice in the cup | Rolls are locked |
| `CLAIM` | Make your boast | Tell the truth or pad it |
| `CHALLENGE` | Call their bluff | Challenge or let it stand |
| `REVEAL` | Show the dice | Verify both rolls |
| `RESOLVE` | Settle the hit | Apply calls, kits, and damage |
| `FINISHED` | Match over | Show the winner |

Canonical rules terms such as `claim`, `padding`, `caught`, `wrong call`, and `locked in` must remain in explanatory copy and tooltips.

## Primary layout: the Exchange Theatre

At 1280×720, use a stable three-column grid:

```text
┌──────────────────── Tournament banner + round + phase ribbon ────────────────────┐
│ Player 1 roster      │              Exchange theatre             │ Player 2 roster │
│ four compact cards   │ attacker, move, claims, call, reveal      │ four compact cards│
│ always readable      │ totals, outcome, damage                    │ always readable   │
├──────────────────────┼────────────────────────────────────────────┼───────────────────┤
│ Player 1 claim sheet │ Current decision and primary controls      │ Player 2 claim sheet│
└──────────────────────┴────────────────────────────────────────────┴───────────────────┘
```

Recommended starting dimensions at 1280×720:

- outer margin: 12 px;
- header and phase ribbon: 76–88 px total;
- roster columns: 300–320 px each;
- exchange theatre: remaining width, never below 440 px at 1280;
- bottom claim/decision row: 135–165 px;
- gaps: 8–12 px.

At 1024×640:

- compact roster card vertical spacing and reduce portraits before reducing body text;
- reduce roster columns to approximately 250 px;
- keep the central decision buttons visible;
- allow claim-history content to scroll inside its own bounded sheet;
- never require the entire page or current decision panel to scroll.

The start, connection, draft, and placement screens should not reserve an empty combat board or empty exchange log. Let their primary content use the available width and height.

## Information hierarchy

### Always visible during an active match

Every character card shows:

- portrait or placeholder;
- display name;
- formation position and damage-taken multiplier;
- HP number and bar;
- ATK, DEF, DMG, and INIT;
- both kit-effect names;
- ready, acted, defeated, attacker, or defender state;
- live stance, exposed, armed, claim-cap, and streak counters when present.

### Exchange focus

The centre stage shows only information relevant to the current exchange:

- attacker and defender portraits/names;
- selected move;
- current phase;
- each submitted claim when it is legally public;
- each player's own private roll only on their private claim view;
- effective attack and defence totals;
- challenge branch consequences;
- countdown in online play;
- fired kit effects;
- final damage and movement.

### Historical read

- Put each player's claim history beneath that player's roster rather than mixing both histories in one unrelated panel.
- Show newest claims first.
- Each line shows character face or initials, claim, true roll after reveal, padding, and outcome icon.
- Make Scribe-recorded paddings visually distinct as pinned/ticked numbers.
- Keep the exchange log as a compact chronological ticker or expandable rulebook page. It must not consume a fixed 340 px column while empty.

## Character card component

Extract the card from `main.gd` into a reusable presentation component. The component should accept state; it must not query or mutate the reducer.

Recommended stable API:

```gdscript
func bind_character(player: int, character: Dictionary, view: Dictionary) -> void
func set_interaction_state(state: String) -> void
func animate_hp(from_hp: int, to_hp: int) -> Tween
func animate_position(from_position: int, to_position: int) -> Tween
func pulse_effect(effect_id: String) -> void
```

Suggested interaction states:

- `NORMAL`
- `READY`
- `SELECTED`
- `LEGAL_TARGET`
- `ATTACKER`
- `DEFENDER`
- `ACTED`
- `DEFEATED`

Portrait placeholders should use the character's initial and a simple kit-specific prop silhouette, not an arbitrary stock avatar.

## Phase ribbon

Add a persistent hand-painted tournament score strip across the top:

`FIGHTER → DICE → BOAST → CALL → REVEAL → RESULT`

- Current step: orange painted tab with dark ink text.
- Completed steps: green check or tied cord.
- Future steps: muted cardboard.
- Waiting for opponent: small animated ellipsis on the current step.
- Online timer: a shrinking stitched underline beneath the current step plus exact seconds as text.
- Final five seconds: warning orange, then danger red for the final two seconds. Do not flash the full screen.

## Exchange-theatre behavior

### Select

- Clicking a ready character lifts its roster card and places a paper-token echo in the centre.
- Legal moves appear as four prop cards: light weapon, heavy weapon, shield/stance, and swap/footwork.
- Illegal moves remain visible but crossed with tape and show the exact reason.
- After selecting an attack, draw a rope or chalk line from attacker to each legal target.
- Show the target's position multiplier next to the targeting line.

### Claim

- Present the private roll as a painted d20 token in the acting player's color tab, not a glowing digital tile.
- The claim control should look like rotating or stacked number cards but remain keyboard accessible.
- Always show:
  - true roll;
  - chosen claim;
  - padding as `+N`;
  - effective attack or defence total if the claim stands;
  - what total remains if caught;
  - padding damage before known kit reductions, with relevant kit note beside it.
- Honest claims use a neutral paper edge. Padded claims gain a subtle crooked orange underline visible only to the player making the private claim.

### Challenge

- Flip both public claim cards into the centre simultaneously.
- Present two compact consequence cards side by side:
  - `IF THEY LIED — CORRECT CALL`
  - `IF THEY WERE HONEST — WRONG CALL`
- Show the actual affected character, HP, total, multiplier, exposure result, and relevant kit patch in each branch.
- Keep `PASS` and `CHALLENGE` visible at the bottom of the centre stage at all times.
- Primary challenge button: a red rubber-stamp style labeled `CHALLENGE`.
- Pass button: neutral cardboard labeled `LET IT STAND` with `Pass` retained in supporting text or tooltip.
- Hovering or focusing a decision highlights only the consequences of that decision. Do not reveal hidden truth.

### Reveal and resolution

Play a skippable sequence driven exclusively by public `last_resolution` data:

1. Both claim cards move to the centre.
2. The true-roll token rotates or flips out from behind each claim.
3. Stamp each side with `LOCKED IN`, `CAUGHT`, `WRONG CALL`, or `HONEST`.
4. Assemble attack and defence totals from labeled number chips.
5. Slide the totals together to produce the margin.
6. If defended, show a shield impact and stop.
7. If the attack claim was caught, snap the attack rope and route padding damage back to the attacker.
8. If hit, send the damage marker to the defender card.
9. Animate self-damage, reflected damage, and hit damage separately.
10. Pulse each kit patch immediately before its numeric modification appears.
11. Animate Drag, Slippery, Swap, death, and formation compaction as card movement.
12. Append the exchange and both claims to their history sheets.

The final state and full arithmetic remain on screen after the animation. The player does not have to replay the animation to understand the result.

## Motion specification

Default timings:

| Motion | Duration | Curve |
|---|---:|---|
| Hover/lift | 90–120 ms | ease out |
| Selection settle | 160–220 ms | back/ease out, very small overshoot |
| Claim-card flip | 220–280 ms | ease in/out |
| Die reveal | 450–650 ms | ease out |
| Outcome stamp | 120–180 ms | back/ease out |
| Number-chip assembly | 90–140 ms per chip | ease out |
| Impact | 160–240 ms | sharp ease out |
| HP trail | 500–750 ms | ease in/out |
| Formation move | 300–450 ms | ease in/out |
| Kit pulse | 220–320 ms | back/ease out |

Rules:

- A normal attack resolution should take roughly 2.0–3.0 seconds before settling.
- A non-attack move should take less than 1.2 seconds.
- Provide `Skip animation` during resolution.
- Any click or confirm input during a skippable resolution may fast-forward to the settled view; it must not accidentally activate the next-turn button.
- Add a reduced-motion setting or constant. In reduced motion, replace movement with 80–120 ms crossfades and immediate number updates.
- Do not animate layout reflow by destroying and rebuilding the entire tree each frame.

## Particle and feedback language

Particles are punctuation, not decoration:

- hit: 6–12 short cardboard/foam flecks in orange and ink;
- defended: a brief blue-grey shield ring and two or three sparks;
- caught bluff: torn-paper fragments from the claim card plus a red stamp dust puff;
- wrong call: crooked red question marks or stamp flecks near the challenger;
- kit activation: 4–8 thread/stitch motes in the kit patch color;
- defeat: a small paper slump/tilt and dust, never gore;
- movement: a short chalk or cloth-drag trail.

Use pooled or one-shot lightweight 2D particles. Keep effects inside the exchange stage and affected card bounds. Avoid full-screen shake. A hit may move the affected card 3–6 px for less than 180 ms.

## Theme implementation

Refactor `src/presentation/theme.gd` into semantic helpers rather than scattering handcrafted overrides across `main.gd`.

Add or revise helpers for:

```gdscript
static func paper_style(kind: String = "normal") -> StyleBoxFlat
static func team_card_style(player_color: Color, state: String) -> StyleBoxFlat
static func patch_style(color: Color, state: String = "normal") -> StyleBoxFlat
static func prop_button_style(kind: String, state: String) -> StyleBoxFlat
static func tooltip_style() -> StyleBoxFlat
static func health_color(fraction: float) -> Color
```

Use semantic arguments such as `primary`, `secondary`, `danger`, `selected`, `disabled`, and `stamped`. Do not pass arbitrary colors from every caller.

If a subtle texture is used, implement it once as a low-opacity overlay or reusable material. Texture opacity should remain below 8% on information surfaces and below 15% on the outer canvas/wood frame.

## Presentation code structure

The current `main.gd` owns shell construction, component construction, rendering, networking prompts, interaction, and resolution formatting. Do not add the full overhaul as another thousand lines in that file.

Preferred new structure:

```text
src/presentation/
  main.gd                         # stage routing and intent orchestration
  theme.gd                        # palette and reusable styles
  rules_tooltip.gd
  ui/
    character_card.gd
    team_roster.gd
    phase_ribbon.gd
    exchange_stage.gd
    claim_token.gd
    combat_equation.gd
    claim_sheet.gd
    fx_layer.gd
    larp_grain_overlay.gd         # optional, presentation-only
  animation/
    resolution_sequence.gd
    state_visual_snapshot.gd
```

Use scenes for stable, stateful visual components when that reduces rebuild complexity. It is acceptable to continue creating small labels and patches in code.

### State snapshots and animation queue

The current UI re-renders immediately after state changes. Resolution animation needs both the previous visual state and the resolved state.

Implement a presentation-only snapshot containing:

- character HP by player and id;
- position by player and id;
- alive state;
- statuses and effect counters;
- active player and used-character ids;
- current UI stage.

Capture it before submitting the final challenge or resolving a non-attack move. When the resolved state arrives, build a visual sequence from the old snapshot plus `state["last_resolution"]`.

The sequence must not infer rules. It decides how to show fields already produced by the reducer. If a required visual event cannot be derived unambiguously, add a presentation effect to the reducer's existing `effects` output only after documenting and testing it; do not duplicate resolution logic in UI code.

Online state changes may arrive while animation is playing. Queue the latest public visual state, finish or fast-forward the current sequence, then render the queued state. Never drop a reducer state or resend an intent.

## Start, connection, draft, and placement screens

### Start and connection

- Use a painted tournament-banner title and a small illustrated rules/dice prop.
- Present `Hot-seat`, `Same network`, and `Internet codes` as three distinct paper notices or tabs.
- Do not show an empty exchange log or claim record before a match.
- Keep all main connection choices visible at 1280×720. Secondary explanation may scroll inside its card.
- Connection codes go on a monospaced cream paper strip with a prominent copy button.
- Waiting and reconnection views use a tied-rope progress indicator, exact text, and exact remaining seconds.

### Draft

- Hide the combat board while drafting.
- Show all five roster candidates in a responsive grid with face, stats, both kit descriptions, and a large pick toggle.
- At 1280×720, the confirm button and `N of 4 chosen` counter remain visible without scrolling.
- Picked cards gain a colored clothespin/tape marker and lift slightly.

### Placement

- Replace plain up/down rows with four physical slots labeled `BACK 1`, `2`, `3`, `FRONT 4`.
- Show `70%`, `85%`, `100%`, and `120% damage taken` directly on the slots.
- Allow click-to-swap as a baseline. Drag-and-drop is optional and must not replace keyboard-accessible controls.
- Visually emphasize that Heavy Attack is available only from positions 3 and 4.

## Accessibility and input

- Maintain keyboard focus for every action available by mouse.
- Make focus state a thick ink-and-orange outline, not a faint engine default.
- Minimum functional hit target: 40×40 px.
- Maintain at least 4.5:1 contrast for normal text and 3:1 for large text and essential component boundaries. The foreground/background combinations prescribed in the color-use rules meet the normal-text target.
- Do not use animation, texture, or color as the only state cue.
- Tooltips must also appear on keyboard focus or have equivalent visible help text.
- Provide exact timer seconds; the stitched bar is supplementary.
- Keep text readable at the minimum supported window size.
- Never use rapid flashing.
- Respect reduced motion.
- Use plain rules language beneath thematic labels when there is any ambiguity.

## Implementation order

Complete work in this order so the game stays usable throughout:

### 1. Baseline and regression capture

- Run the current UI smoke test.
- Repair `tests/ui_screenshot.gd`: it currently calls `_start_match()`, which now opens draft, and then immediately indexes `available_actors()[0]` as though a preset match had started.
- Capture current start, draft, placement, select, claim, challenge, resolution, and finished screens at 1280×720.
- Add 1024×640 captures for select, challenge, and resolution.

### 2. Theme tokens

- Replace palette constants in `theme.gd`.
- Implement paper, cardboard, patch, button, field, tooltip, scrollbar, and health styles.
- Preserve functionality and layout while validating contrast.

### 3. Adaptive shell

- Remove empty combat/history regions from pre-match screens.
- Build the three-column combat grid and bounded bottom row.
- Add the phase ribbon.
- Verify no primary action is below a scroll boundary.

### 4. Reusable roster cards

- Extract character and team components.
- Add portrait placeholders and the production asset lookup.
- Preserve every existing stat, kit, status, interaction, and tooltip.
- Add stable selected/target/attacker/defender states.

### 5. Exchange theatre decisions

- Implement select, claim, wait, and challenge presentations.
- Preserve hot-seat handoff privacy.
- Preserve online waiting and countdown behavior.
- Add player-relative claim sheets.

### 6. Resolution sequence

- Add visual snapshots and the sequence runner.
- Implement roll/claim reveal, stamps, totals, margin, damage, kit pulses, HP trail, and movement.
- Add skip and reduced-motion behavior.

### 7. Particles and polish

- Add restrained particles and card impacts.
- Add subtle material grain only after all text remains readable.
- Replace placeholders with final portraits when valid exports exist.

### 8. Verification

- Run targeted UI smoke and screenshot passes after each visual milestone.
- Run the full test suite before handoff.
- Compare screenshots at both supported sizes.
- Manually verify hot-seat privacy and online hidden-information boundaries.

## Required visual test matrix

Capture and inspect at least:

- start screen;
- direct/LAN connection;
- manual offer/answer connection;
- draft with zero, three, and four picks;
- placement;
- select with no actor, selected actor, legal targets, and illegal Heavy Attack;
- attacker private claim with honest and padded values;
- defender private claim;
- challenge as attacker and defender;
- online wait and countdown at normal time and five seconds;
- honest/pass resolution;
- padded/pass resolution;
- caught attack bluff;
- caught defence bluff;
- wrong attack call;
- wrong defence call;
- miss and hit;
- each of the ten kit effects firing;
- Drag movement, Slippery swap, normal Swap, death compaction;
- reconnecting, failed match, winner, and forfeit;
- reduced-motion resolution;
- missing portrait placeholder.

## Automated verification

At minimum:

```powershell
godot --headless --path . --script res://tests/ui_smoke.gd
godot --path . --script res://tests/ui_screenshot.gd
.\run-tests.ps1
```

When the local Godot process cannot write its default Windows log path, pass `--log-file` with a path under `.godot/` rather than changing project behavior.

Add UI assertions for:

- phase ribbon step matches `ui_stage`/public state;
- all eight active-match character cards exist;
- every card exposes both kit names;
- Challenge and Pass/Let It Stand are visible at 1024×640;
- hidden opponent values do not appear before reveal;
- skip produces the same settled values as the full sequence;
- reduced-motion mode completes without queued tweens;
- missing portraits use placeholders without errors;
- resolution sequences do not enable the next action early;
- timer updates do not rebuild or reset the active input.

## Acceptance criteria

The overhaul is complete only when all of the following are true:

1. The interface unmistakably reads as a handmade modern LARP event rather than a casino, sci-fi dashboard, or royal fantasy game.
2. The supplied face style feels native to the cards without needing a separate visual frame language.
3. All public combat information remains visible and legible.
4. The active decision is identifiable within one second without reading the entire screen.
5. The Challenge screen shows both risk branches while keeping both actions on screen.
6. Every resolution communicates true rolls, claims, call outcomes, effective totals, damage, movement, and fired kit effects.
7. HP loss, self-damage, reflection, kit changes, and position changes are visually attributable to their cause.
8. No private information appears early in hot-seat or online play.
9. Start, draft, placement, select, challenge, and resolution have no inaccessible primary controls at 1280×720 or 1024×640.
10. Animation is skippable, reduced motion works, and neither changes game state.
11. UI smoke, screenshot verification, and the full existing test suite pass.
12. No combat rule is duplicated or moved into presentation code.

## Agent handoff requirements

When handing the implementation back:

- summarize the new component structure;
- list every added asset and its source/license;
- identify any remaining placeholder portrait;
- include current screenshots for the required primary stages;
- report test commands and results;
- call out any visual behavior that could not be derived from existing reducer state;
- do not claim the visual pass is complete while primary controls still require scrolling or any hidden-information path is unverified.

---

# Implementation status

*Last verified 2026-09-02 against commit `d444675`. The specification above is
unchanged and remains the contract; this section records how far the
implementation has got against it, and is the thing to update as work continues.*

Steps 1–5 of the implementation order are done. Step 6 is partially done. Steps
7 and 8 are open.

## Verified state

Full suite green as of 2026-09-02 (`.\run-tests.ps1`, all ten stages):
reducer/protocol (81 tests), full-match bot (12 matches, 21–33 exchanges), UI
smoke, WebRTC smoke, online match smoke, WebRTC timeout, disconnect, direct
match, reconnection. Working tree clean.

### Done — step 1, baseline and regression capture

`tests/ui_screenshot.gd` was repaired. It previously called `_start_match()` and
then indexed `available_actors()[0]` as though a preset match had begun, which
had not been true since the draft screen landed. It now walks start → draft →
placement → select → claim → challenge → resolution, and captures at both
1280×720 and 1024×640.

### Done — step 2, theme tokens

`src/presentation/theme.gd` carries the full palette from the colour table above
and the semantic helpers: `paper_style`, `team_card_style`, `patch_style`,
`prop_button_style`, `tooltip_style`, `health_color`, plus `ink_on`, which picks
the printing colour from a fill's luminance so a derived colour still gets a
readable pairing.

No colour literal remains in presentation code outside `theme.gd` (verified by
grep). The old navy-and-brass constant names survive as aliases onto their
nearest craft-material equivalent, so any call site not yet converted renders in
the new palette rather than reintroducing the felt table one widget at a time.

### Done — step 3, adaptive shell

Three-column Exchange Theatre, phase ribbon, and a pinned decision footer. Three
size tiers (compact below 1180px, normal, roomy at 1600×900 and above). Pre-match
screens no longer reserve an empty board or an empty exchange log. The exchange
log is a compact ticker, not a fixed 340px column.

`project.godot` now opens at 1920×1080 with stretch disabled, so the layout uses
the space rather than scaling a 1280-wide design up. 1024×640 remains the floor
and is asserted in the smoke test.

### Done — step 4, reusable roster cards

Extracted from `main.gd` into `src/presentation/ui/`:

| File | Lines | Role |
|---|---:|---|
| `widgets.gd` | 137 | labels, patches, stamps, prop buttons, headings, rules |
| `character_card.gd` | 408 | the full card, with the spec's stable API |
| `team_roster.gd` | 97 | one player's column |
| `phase_ribbon.gd` | 194 | FIGHTER → DICE → BOAST → CALL → REVEAL → RESULT |
| `claim_sheet.gd` | 131 | per-player claim history, newest first |
| `portrait.gd` | 109 | production lookup and the placeholder |
| `animation/resolution_sequence.gd` | 149 | the skippable reveal |

`character_card.gd` implements `bind_character`, `set_interaction_state`,
`animate_hp`, `animate_position`, and `pulse_effect`, and the eight interaction
states. It reads state and reports clicks; it never queries the reducer.

### Done — step 5, exchange theatre decisions

Select, claim, wait, and challenge presentations; hot-seat handoff privacy and
online waiting/countdown preserved; player-relative claim sheets beneath each
roster.

### Partial — step 6, resolution sequence

`resolution_sequence.gd` plays a beat-timed reveal driven exclusively by
`last_resolution` fields: true rolls, the four outcome stamps (`HONEST`,
`LOCKED IN`, `CAUGHT`, `WRONG CALL`), assembled totals, margin, and damage. It
is skippable, and `skip()` is idempotent so a stray click cannot double-run a
beat. Under reduced motion every beat applies at once and no tween is queued —
asserted in the smoke test.

The sequence infers no rules; it orders fields the reducer already produced.

**What is missing from step 6.** There is no
`animation/state_visual_snapshot.gd`. Without a before/after snapshot,
`animate_hp` and `animate_position` on the card have no caller: HP and formation
changes appear by rebuild rather than as a trail or a slide. `pulse_effect` *is*
wired (`main.gd:2415`). The reveal is a text-and-stamp sequence, not the
twelve-beat cinematic of card movement, rope-snapping, and formation compaction
the spec describes.

## Not started

- **Step 7, particles.** None of the feedback language exists: no flecks, shield
  ring, torn paper, stamp dust, stitch motes, defeat slump, or drag trail. No
  card impact offset.
- **Material grain.** No `larp_grain_overlay.gd`.
- **Fonts.** Still the Godot default. No `src/presentation/assets/fonts/`
  directory, so neither Atkinson Hyperlegible nor Bree Serif is bundled, and
  there is no license file to record.

## Assets

**None have been added.** `src/presentation/assets/` does not exist. There is
therefore nothing to report under the handoff requirement to list added assets
and their licenses.

## Portraits — all five are placeholders

No export exists for any character. `portrait.gd` looks up
`res://src/presentation/assets/portraits/<id>.png`, finds nothing, and falls
back to the placeholder in every case. A missing export is treated as a visual
state and never an error, which is asserted in the smoke test.

The placeholder is the character's initial — taken from the name proper, so
"The Scribe" reads as `L` and not a column of `T`s — over a kit-specific prop
glyph, on a pale ownership wash.

Still required, per the production portrait asset contract above:
`scribe.png`, `knight.png`, `wizard.png`, `bard.png`, `hook.png`.

The concept-face-to-character mapping has not been supplied, so nothing has been
guessed.

## Test coverage

`tests/ui_smoke.gd` carries 46 assertions across five groups:
`_check_rules_tooltips`, `_check_visual_contract`, `_check_hidden_before_reveal`,
`_check_challenge_actions_visible`, `_check_reduced_motion`.

Of the assertions the spec asks for under **Automated verification**, these are
covered: phase-ribbon step matches state; all eight cards exist; every card
exposes both kit names; Challenge and Let It Stand visible at 1024×640; hidden
opponent values absent before reveal; reduced motion completes with no queued
tweens; missing portraits use placeholders without error.

**Not covered:** that skip produces the same settled values as the full
sequence; that a resolution sequence does not enable the next action early; that
a timer update does not rebuild or reset the active input.

## Unverified — do not treat the visual pass as complete

Per the handoff rule in this document, two things block that claim:

1. **Every portrait is a placeholder.**
2. **The online hidden-information boundary has never been manually checked.**
   Only the hot-seat path is exercised, and only by the smoke test. The
   `_check_hidden_before_reveal` assertions run against hot-seat state.

The **required visual test matrix** is largely uncovered. Roughly twelve stages
have been captured. Not captured: the ten kit effects firing; Drag movement,
Slippery swap, normal Swap, death compaction; reconnecting, failed match,
winner, and forfeit; the online wait and countdown at five seconds; caught
defence bluff and both wrong-call branches.

## Suggested next steps

1. Manually verify the online hidden-information boundary — the one open item
   that is a correctness risk rather than a polish gap.
2. Add `state_visual_snapshot.gd` and give `animate_hp` / `animate_position`
   their caller, closing step 6.
3. Work the visual test matrix, starting with the kit effects and the movement
   cases, since those are where a reveal is most likely to show a number it
   cannot explain.
4. Bundle the two fonts with their licenses.
5. Step 7 particles, last — they are punctuation on a reveal that should read
   correctly without them first.

---

# Board replacement: the animated field

*Added 2026-09-02. This supersedes the roster-column half of the Exchange
Theatre described above; the phase ribbon, claim sheets, decision footer, and
size tiers are unchanged.*

The two paper roster columns have been replaced by a single field both crews
stand on. `src/presentation/ui/battlefield.gd` lays eight fighters on one ground
line, the teams facing each other, with position 1 farthest from the opponent
and position 4 closest — the same order the position damage multiplier uses, so
the formation is now readable off the formation itself rather than off a printed
multiplier on a card.

Each figure is a `fighter.gd`: an animated rig in a `SubViewport`, plus a
clickable nameplate. The split matters. The rig is decoration and may be absent;
the plate is the whole interface and carries everything the card carried — name,
rank, health, both kit names, live statuses, the full stat tooltip — so nothing
became unreachable in the move and the board is still keyboard-navigable. A
character with no rig gets a paper standee and remains fully playable, which is
the same rule portraits already followed: missing art is a visual state, never
an error.

`character_card.gd` and `team_roster.gd` were deleted rather than left in place;
the draft and placement screens never used them.

## What the field costs, and what pays for it

The field cannot be squeezed to nothing the way the old centre stage could,
because the nameplates are the only place health and rank are legible. It
therefore carries a real minimum height, and at 1024×640 that competes directly
with the decision footer. The decision row is capped at that tier
(`COMPACT_DECISION_CEILING`) and the claim sheets fold into its scroll, which it
can afford because its primary controls are pinned to a footer that never
scrolls. The `1024x640` assertion in the UI smoke test is what holds this
balance honest; it caught the first two attempts at it.

At that floor size the field is tight: plates drop their kit row, and below a
readable width they drop the name too, keeping the rank, the health bar, and the
TARGET / DOWN stamps — the two cues a player acts on. The full name stays in the
tooltip and the claim record. **Eight figures at a legible size do not fit
1024px wide**; this is a real limitation of the layout, not a tuning gap.

## Animation

`fighter_rigs.gd` maps a character id to a rig scene and translates the board's
four beats — idle, move, hurt, attack — into that rig's own animation names,
which differ per rig. Adding art for a character is a row in that table and
nothing else.

Beats are driven from `last_resolution` fields only, under the same rule the
resolution sequence follows: the attacker swings, and anyone whose HP actually
fell flinches, read off the damage fields rather than off `hit` alone so
self-damage is never silent. Attack variants are selected by exchange number,
never randomly, so a replay swings identically on both peers.

## Still open

The two blocking items above are unchanged. The rename below is new context:
the roster is now Scribe, Knight, Wizard, Bard, Rogue. Only the wizard and the
bard have rigs; the other three stand as paper standees until their art lands.
