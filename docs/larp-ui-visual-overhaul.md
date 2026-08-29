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
  - `res://src/presentation/assets/portraits/ledger.png`
  - `res://src/presentation/assets/portraits/bruiser.png`
  - `res://src/presentation/assets/portraits/mirror.png`
  - `res://src/presentation/assets/portraits/gambler.png`
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
- Make Ledger-recorded paddings visually distinct as pinned/ticked numbers.
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
