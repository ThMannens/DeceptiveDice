# Deceptive Dice

Deceptive Dice is a two-player bluffing combat game built with Godot 4.6. The prototype supports local hot-seat play and direct online play between two game clients.

Online attacks use commit-reveal for the hidden d20 rolls. Claims and challenge choices are also committed before either player sees the other choice. Both clients run the same deterministic rules and compare a full-state hash after every exchange. A mismatch stops the match.

Online play requires no lobby or game server. The players exchange a host offer and joiner answer as copyable connection codes. After that, gameplay, rolls, claims, challenges, reveals, and state hashes travel over the direct peer channel.

## Play locally

Open the project in Godot 4.6 and run it. The match starts with fixed teams and formations so two players can begin immediately.

On an attack, pass the device when prompted. Each player sees only their own roll and submits a claim before either claim is shown. Each player then sees the opponent's claim and privately chooses whether to challenge it.

## Play online

Run one copy of the game for each player.

1. The host selects **Create host offer** and sends the generated code to the joiner.
2. The joiner pastes that code on the start screen and selects **Join with offer**.
3. The joiner sends their generated answer code back to the host.
4. The host pastes the answer and selects **Connect with answer**.

Connection codes contain network address information. Share them only with the other player.

Godot's editor can launch two copies through **Debug > Customize Run Instances**.

The same exchange works when the players send the codes through a private chat.

The prototype uses a public STUN lookup to discover internet-facing addresses. STUN does not relay gameplay or hold match data. There is no TURN relay, so direct WebRTC will fail for some restrictive NAT or firewall combinations.

## Run the tests

From PowerShell in the project directory:

```powershell
.\run-tests.ps1
```

The runner imports the bundled native WebRTC extension, runs the rules and interface tests, validates the connection-code format, tests a direct WebRTC channel, and drives two serverless clients through one complete combat exchange.

The native WebRTC extension and its licenses are included under `addons/webrtc_native`.

## Layout

- `docs`: shared design contracts
- `src/core`: deterministic state, events, moves, combat, roster, and reducer
- `src/local`: trusted local hot-seat coordinator
- `src/protocol`: commit-reveal and blind decision protocol
- `src/network`: connection codes, WebRTC transport, online match coordinator, and state checks
- `src/presentation`: playable Godot scene
- `tests/transcripts`: data-driven reducer scenarios
- `tests/run_tests.gd`: transcript test runner

## Prototype limits

- Teams and formations are fixed.
- Character-specific kit effects are not implemented yet.
- There is no TURN relay, reconnect window, or phase timeout resolution yet.
